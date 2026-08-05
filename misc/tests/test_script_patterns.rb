#!/usr/bin/env ruby
# Unit tests for the script-line patterns produced by output_script_js().
#
# Each line of a "script:" template yields two pieces of JavaScript: one that
# writes the line, and one that registers it in ocForm.scriptLinePatterns so the
# browser can patch that line in place and read it back into the widgets. These
# tests pin down the second piece — which lines get a capture regex, which are
# registered for placement only, and which get none at all.
#
# Each generated regex is also run against a rendered line, so a pattern that is
# syntactically fine but captures the wrong text is caught here rather than in
# the browser.
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

F = FormHarness.new

# Pull the interesting fields back out of the generated push(...) call.
def pattern_for(tpl)
  _show, js = F.output_script_js(FORM, tpl, "App", "Dir")
  return nil if js.nil? || js.strip.empty?
  {
    regex:      js[/regex:(null|\/.*?\/), keys:/, 1],
    keys:       js[/keys:\[([^\]]*)\]/, 1].to_s,
    zero_pad:   js[/zeroPad:\[([^\]]*)\]/, 1],
    parse_type: js[/parseType:'([^']*)'/, 1],
    literal:    js.include?("literal:true"),
  }
end

# The compiled form of a pattern's regex, for matching a rendered line.
def regex_for(tpl)
  p = pattern_for(tpl)
  src = p && p[:regex].to_s.start_with?("/") ? p[:regex][1..-2] : nil
  src && Regexp.new(src)
end

# Mimic ocForm.zeroPadding() and the browser's strip, so the round trip below
# exercises the same transformation the page performs.
def pad(value, width) = value.to_s.rjust(width, "0")
def strip_pad(text)   = text.to_i.to_s

$pass = 0
$failures = []

def check(label, got, want)
  if got == want
    $pass += 1
  else
    $failures << "#{label}\n       got:  #{got.inspect}\n       want: #{want.inspect}"
  end
end

# --- 1. which lines get which kind of pattern ----------------------------
# :literal (no interpolation), :regex (parseable), :prefix (patch only),
# :slurm_time (dedicated parser), :none (not registered at all)
[
  ["literal line",
   '#!/bin/bash',                                              :literal],
  ["blank line gets no pattern",
   '',                                                         :none],
  ["line starting with an interpolation gets no pattern",
   '#{name} -n 4',                                             :none],
  ["unknown widget key leaves the line unregistered",
   '#SBATCH --nope=#{not_a_widget}',                           :none],
  ["plain interpolation",
   '#SBATCH -n #{n}',                                          :regex],
  ["several plain interpolations",
   '#SBATCH -t #{h}:#{m}:00',                                  :regex],
  ["zeropadding, bare",
   '#SBATCH -o run-#{zeropadding(n, 4)}.log',                  :regex],
  ["zeropadding, tolerating inner spaces",
   '#SBATCH -o run-#{zeropadding( n , 4 )}.log',               :regex],
  ["zeropadding on a hideable field (:n)",
   '#SBATCH -o run-#{zeropadding(:n, 4)}.log',                 :regex],
  ["zeropadding mixed with a plain field",
   '#SBATCH -J #{name}-#{zeropadding(n, 4)}',                  :regex],
  ["two padded fields separated by literal text",
   '#SBATCH -a #{zeropadding(h, 2)}-#{zeropadding(m, 2)}',     :regex],
  ["zeropadding alongside calc()",
   '#SBATCH -x #{zeropadding(n, 2)}-#{calc(n * 2)}',           :prefix],
  ["zeropadding wrapping calc()",
   '#SBATCH -y #{zeropadding(calc(n * 2), 3)}',                :prefix],
  ["zeropadding alongside dirname()",
   '#SBATCH -z #{zeropadding(n, 2)}-#{dirname(wd)}',           :prefix],
  ["adjacent captures cannot be split",
   '#SBATCH --stamp=#{zeropadding(h, 2)}#{zeropadding(m, 2)}', :prefix],
  ["dirname()",
   'cd #{dirname(wd)}',                                        :prefix],
  ["basename()",
   'echo #{basename(wd)}',                                     :prefix],
  ["--time= keeps its dedicated parser",
   '#SBATCH --time=#{d}-#{zeropadding(h, 2)}:#{zeropadding(m, 2)}:#{zeropadding(s, 2)}', :slurm_time],
].each do |label, tpl, want|
  p = pattern_for(tpl)
  kind = if p.nil?                            then :none
         elsif p[:parse_type] == "slurm_time" then :slurm_time
         elsif p[:literal]                    then :literal
         elsif p[:regex] == "null"            then :prefix
         else                                      :regex
         end
  check("kind: #{label}", kind, want)
end

# The --time= line must keep its fields even though it has no regex; that is
# what lets the Slurm-time parser fill days/hours/minutes/seconds in order.
tt = pattern_for('#SBATCH --time=#{d}-#{zeropadding(h, 2)}:#{zeropadding(m, 2)}:#{zeropadding(s, 2)}')
check("--time= keeps all four fields", tt[:keys], "'d', 'h', 'm', 's'")

# --- 2. generated regexes capture the right text -------------------------
# Each case renders the template the way showLine() would, then feeds it back
# through the generated regex and compares the captures.
[
  ['#SBATCH -n #{n}',                         '#SBATCH -n 12',           ["12"]],
  ['#SBATCH -t #{h}:#{m}:00',                 '#SBATCH -t 3:45:00',      ["3", "45"]],
  ['#SBATCH --mem #{n}G',                     '#SBATCH --mem 64G',       ["64"]],
  ['#SBATCH -o run-#{zeropadding(n, 4)}.log', '#SBATCH -o run-0125.log', ["0125"]],
  ['module load #{tags}',                     'module load gcc openmpi', ["gcc openmpi"]],
  # The last capture is greedy, so a trailing value keeps its spaces.
  ['#SBATCH --comment=#{name}',               '#SBATCH --comment=a b c', ["a b c"]],
  # An earlier capture is lazy, so the separator splits at the first match.
  ['#SBATCH --range=#{h}-#{m}',               '#SBATCH --range=1-2-3',   ["1", "2-3"]],
  # ...but lazy still backtracks until the rest of the pattern fits: here it
  # takes "my-job" rather than "my", because "job-0042" is not all digits.
  ['#SBATCH -J #{name}-#{zeropadding(n, 4)}', '#SBATCH -J my-job-0042',  ["my-job", "0042"]],
].each do |tpl, rendered, want|
  re = regex_for(tpl)
  md = re && re.match(rendered)
  check("capture: #{tpl}", re.nil? ? "no regex generated" : (md ? md.captures : "no match"), want)
end

# --- 3. zeroPad flags line up with the captures --------------------------
[
  ['#SBATCH -o run-#{zeropadding(n, 4)}.log',              "true"],
  ['#SBATCH -J #{name}-#{zeropadding(n, 4)}',              "false, true"],
  ['#SBATCH -a #{zeropadding(h, 2)}-#{zeropadding(m, 2)}', "true, true"],
  ['#SBATCH -n #{n}',                                      nil],  # nothing padded -> flag omitted
].each do |tpl, want|
  check("zeroPad: #{tpl}", pattern_for(tpl)[:zero_pad], want)
end

# --- 4. zeropadding round trip: value -> line -> capture -> value ---------
# zeropadding() is the only reversible template function, so this is the
# transformation that has to survive both directions intact.
re_tpl = ->(width) { "\#SBATCH -o run-\#{zeropadding(n, #{width})}.log" }
[
  [5,     2],   # ordinary case
  [125,   4],
  [0,     3],   # pads to 000 and must come back as 0, not blank
  [7,     1],   # width 1, nothing to pad
  [12345, 3],   # value wider than the pad is left as-is
].each do |value, width|
  rendered = "#SBATCH -o run-#{pad(value, width)}.log"
  md = regex_for(re_tpl.call(width)).match(rendered)
  check("round trip width #{width} value #{value} (#{rendered})",
        md && strip_pad(md.captures[0]), value.to_s)
end

# A padded capture is \d+, so it must not swallow anything else.
padded = regex_for('#SBATCH -o run-#{zeropadding(n, 4)}.log')
check("padded capture accepts digits",     !padded.match("#SBATCH -o run-0125.log").nil?, true)
check("padded capture rejects letters",     padded.match("#SBATCH -o run-abcd.log").nil?, true)
check("padded capture rejects empty",       padded.match("#SBATCH -o run-.log").nil?,     true)

# --- 5. keys stay aligned with the widgets -------------------------------
[
  ['#SBATCH -t #{h}:#{m}:00',                 "'h', 'm'"],
  ['#SBATCH -J #{name}-#{zeropadding(n, 4)}', "'name', 'n'"],
  # A prefix-only line carries no fields, so nothing is written back to a widget.
  ['cd #{dirname(wd)}',                       ""],
].each do |tpl, want|
  check("keys: #{tpl}", pattern_for(tpl)[:keys], want)
end

# --- 6. literal lines are flagged so patchScript keeps a user's edit ------
[
  ['#!/bin/bash',               true],
  ['srun ./a.out',              true],
  # A calc() line is also registered without a regex, but it IS regenerated from
  # its widgets, so it must NOT be marked literal.
  ['#SBATCH -x #{calc(n * 2)}', false],
].each do |tpl, want|
  check("literal flag: #{tpl}", pattern_for(tpl)[:literal], want)
end

puts "#{$pass} passed, #{$failures.size} failed"
unless $failures.empty?
  puts
  $failures.each { |m| puts "FAIL #{m}" }
  exit 1
end
