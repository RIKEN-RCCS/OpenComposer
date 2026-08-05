#!/usr/bin/env ruby
# Unit tests for the script-line patterns produced by output_script_js().
#
# Each line of a "script:" template yields two pieces of JavaScript: one that
# writes the line, and one that registers it in ocForm.scriptLinePatterns so the
# browser can patch that line in place and read it back into the widgets. These
# tests pin down the second piece — which lines get a capture regex, which are
# registered for placement only, and which get none at all.
#
# They also check each generated regex against a rendered line, so a pattern
# that is syntactically fine but captures the wrong text is caught here rather
# than in the browser.
#
# Usage: ruby misc/tests/test_script_patterns.rb

require "cgi"
require "erb"
require "json"
require "yaml"

ROOT = File.expand_path("../..", __dir__)

# Constants normally defined in run.rb.
OC_SCRIPT_CONTENT      = "_script_content"
SUBMIT_CONTENT         = "_submit_content"
HEADER_SCRIPT_LOCATION = "_script_location"
HEADER_SCRIPT_NAME     = "_script_1"
HEADER_JOB_NAME        = "_script_2"
HEADER_CLUSTER_NAME    = "_cluster_name"

# lib/form.rb defines Sinatra helpers. Load its body into a plain class so the
# generators can be called without booting the web app (same trick as run_tests.rb).
form_src = File.read(File.join(ROOT, "lib", "form.rb"), encoding: "UTF-8")
lines = form_src.lines
raise "unexpected structure of lib/form.rb" unless lines.first.strip == "helpers do"

FormHarness = Class.new do
  def escape_html(str) = CGI.escapeHTML(str.to_s)
  def halt(code, msg) = raise("halt #{code}: #{msg}")
  def initialize
    @table_index = 1
    @conf = {}
  end
end
FormHarness.class_eval(lines[1..-2].join, File.join(ROOT, "lib", "form.rb"), 2)

# Widgets the templates below refer to.
FORM = {
  "d"    => { "widget" => "number" }, "h"  => { "widget" => "number" },
  "m"    => { "widget" => "number" }, "s"  => { "widget" => "number" },
  "n"    => { "widget" => "number" }, "wd" => { "widget" => "path"   },
  "name" => { "widget" => "text"   },
  "tags" => { "widget" => "multi_select", "separator" => " " },
}.freeze

# Pull the interesting fields back out of the generated push(...) call.
def parse_pattern(js)
  return nil if js.nil? || js.strip.empty?
  {
    prefix:     js[/prefix:'((?:[^'\\]|\\.)*)'/, 1],
    regex:      js[/regex:(null|\/.*?\/), keys:/, 1],
    keys:       js[/keys:\[([^\]]*)\]/, 1].to_s,
    zero_pad:   js[/zeroPad:\[([^\]]*)\]/, 1],
    parse_type: js[/parseType:'([^']*)'/, 1],
    literal:    js.include?("literal:true"),
  }
end

PASS = []
FAIL = []

def check(label, got, want)
  if got == want
    PASS << label
  else
    FAIL << "#{label}\n       got:  #{got.inspect}\n       want: #{want.inspect}"
  end
end

f = FormHarness.new

# --- which lines get which kind of pattern -------------------------------
# kind: :literal (no interpolation), :regex (parseable), :prefix (patch only),
#       :slurm_time (dedicated parser), :none (not registered at all)
[
  ["literal line",
   '#!/bin/bash',                                            :literal],
  ["blank line gets no pattern",
   '',                                                       :none],
  ["line starting with an interpolation gets no pattern",
   '#{name} -n 4',                                           :none],
  ["plain interpolation",
   '#SBATCH -n #{n}',                                        :regex],
  ["several plain interpolations",
   '#SBATCH -t #{h}:#{m}:00',                                :regex],
  ["zeropadding only",
   '#SBATCH -o run-#{zeropadding(n, 4)}.log',                :regex],
  ["zeropadding mixed with a plain field",
   '#SBATCH -J #{name}-#{zeropadding(n, 4)}',                :regex],
  ["zeropadding alongside calc",
   '#SBATCH -x #{zeropadding(n, 2)}-#{calc(n * 2)}',         :prefix],
  ["zeropadding wrapping calc",
   '#SBATCH -y #{zeropadding(calc(n * 2), 3)}',              :prefix],
  ["dirname",
   'cd #{dirname(wd)}',                                      :prefix],
  ["basename",
   'echo #{basename(wd)}',                                   :prefix],
  ["adjacent captures cannot be split",
   '#SBATCH --stamp=#{zeropadding(h, 2)}#{zeropadding(m, 2)}', :prefix],
  ["--time= keeps its dedicated parser",
   '#SBATCH --time=#{d}-#{zeropadding(h, 2)}:#{zeropadding(m, 2)}:#{zeropadding(s, 2)}', :slurm_time],
  ["unknown widget key leaves the line unregistered",
   '#SBATCH --nope=#{not_a_widget}',                         :none],
].each do |label, tpl, want|
  _show, pat_js = f.output_script_js(FORM, tpl, "App", "Dir")
  p = parse_pattern(pat_js)
  kind = if p.nil?                              then :none
         elsif p[:parse_type] == "slurm_time"   then :slurm_time
         elsif p[:literal]                      then :literal
         elsif p[:regex] == "null"              then :prefix
         else                                        :regex
         end
  check("kind: #{label}", kind, want)
end

# --- generated regexes capture the right text ----------------------------
# Each case renders the template the way showLine() would, then feeds it back
# through the generated regex and compares the captures.
[
  ['#SBATCH -n #{n}',                         '#SBATCH -n 12',            ["12"]],
  ['#SBATCH -t #{h}:#{m}:00',                 '#SBATCH -t 3:45:00',       ["3", "45"]],
  ['#SBATCH --mem #{n}G',                     '#SBATCH --mem 64G',        ["64"]],
  ['#SBATCH -o run-#{zeropadding(n, 4)}.log', '#SBATCH -o run-0125.log',  ["0125"]],
  ['#SBATCH -J #{name}-#{zeropadding(n, 4)}', '#SBATCH -J job-0007',      ["job", "0007"]],
  # The last capture is greedy, so a trailing value keeps its spaces.
  ['#SBATCH --comment=#{name}',               '#SBATCH --comment=a b c',  ["a b c"]],
  # An earlier capture is lazy, so the separator splits at the first match.
  ['#SBATCH --range=#{h}-#{m}',               '#SBATCH --range=1-2-3',    ["1", "2-3"]],
  ['module load #{tags}',                     'module load gcc openmpi',  ["gcc openmpi"]],
].each do |tpl, rendered, want|
  _show, pat_js = f.output_script_js(FORM, tpl, "App", "Dir")
  p = parse_pattern(pat_js)
  src = p && p[:regex].to_s.start_with?("/") ? p[:regex][1..-2] : nil
  if src.nil?
    check("capture: #{tpl}", "no regex generated", want)
    next
  end
  md = Regexp.new(src).match(rendered)
  check("capture: #{tpl}", md ? md.captures : "no match", want)
end

# --- zeroPad flags line up with the captures -----------------------------
[
  ['#SBATCH -o run-#{zeropadding(n, 4)}.log', "true"],
  ['#SBATCH -J #{name}-#{zeropadding(n, 4)}', "false, true"],
  ['#SBATCH -n #{n}',                         nil],   # no padding -> flag omitted
].each do |tpl, want|
  _show, pat_js = f.output_script_js(FORM, tpl, "App", "Dir")
  check("zeroPad: #{tpl}", parse_pattern(pat_js)[:zero_pad], want)
end

# --- keys stay aligned with the widgets ----------------------------------
[
  ['#SBATCH -t #{h}:#{m}:00',                 "'h', 'm'"],
  ['#SBATCH -J #{name}-#{zeropadding(n, 4)}', "'name', 'n'"],
  # A prefix-only line carries no fields, so nothing is written back to a widget.
  ['cd #{dirname(wd)}',                       ""],
].each do |tpl, want|
  _show, pat_js = f.output_script_js(FORM, tpl, "App", "Dir")
  check("keys: #{tpl}", parse_pattern(pat_js)[:keys], want)
end

# --- literal lines are flagged so patchScript keeps a user's edit ---------
[
  ['#!/bin/bash',       true],
  ['srun ./a.out',      true],
  # A calc() line is also registered without a regex, but it IS regenerated
  # from its widgets, so it must NOT be marked literal.
  ['#SBATCH -x #{calc(n * 2)}', false],
].each do |tpl, want|
  _show, pat_js = f.output_script_js(FORM, tpl, "App", "Dir")
  check("literal flag: #{tpl}", parse_pattern(pat_js)[:literal], want)
end

puts "#{PASS.size} passed, #{FAIL.size} failed"
unless FAIL.empty?
  puts
  FAIL.each { |m| puts "FAIL #{m}" }
  exit 1
end
