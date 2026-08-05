#!/usr/bin/env ruby
# Tests for reading a zeropadding() line back into its widget.
#
# zeropadding(field, N) is the only template function that can be reversed: it
# just left-pads with zeros, so the original value is recovered by matching
# digits and dropping the padding. calc() has no unique set of inputs, and
# dirname()/basename() each discard half a path, so a line using those is
# registered for placement only and never parsed.
#
# The tests below cover three things:
#   1. which templates qualify for inversion, and which are refused,
#   2. the shape of the generated regex and its zeroPad flags,
#   3. a full round trip — pad a value the way the browser would, match it with
#      the generated regex, strip the padding, and compare with the original.
#
# Usage: ruby misc/tests/test_zeropadding.rb

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

FORM = {
  "d" => { "widget" => "number" }, "h"    => { "widget" => "number" },
  "m" => { "widget" => "number" }, "s"    => { "widget" => "number" },
  "n" => { "widget" => "number" }, "name" => { "widget" => "text"   },
  "wd" => { "widget" => "path" },
}.freeze

F = FormHarness.new

def pattern_for(tpl)
  _show, js = F.output_script_js(FORM, tpl, "App", "Dir")
  return nil if js.nil? || js.strip.empty?
  {
    regex:      js[/regex:(null|\/.*?\/), keys:/, 1],
    keys:       js[/keys:\[([^\]]*)\]/, 1].to_s,
    zero_pad:   js[/zeroPad:\[([^\]]*)\]/, 1],
    parse_type: js[/parseType:'([^']*)'/, 1],
  }
end

# Mimic ocForm.zeroPadding() / the browser's strip, so the round trip below
# exercises the same transformation the page performs.
def pad(value, width)  = value.to_s.rjust(width, "0")
def strip_pad(text)    = text.to_i.to_s

PASS = 0
FAILURES = []

def check(label, got, want)
  if got == want
    $stdout.print "."
    Object.const_set(:PASS, PASS + 1)
  else
    FAILURES << "#{label}\n       got:  #{got.inspect}\n       want: #{want.inspect}"
    $stdout.print "F"
  end
end

puts "1. which templates are inverted"
[
  # [template, parseable?]
  ['#SBATCH -o run-#{zeropadding(n, 4)}.log',                true,  "bare zeropadding"],
  ['#SBATCH -o run-#{zeropadding( n , 4 )}.log',             true,  "tolerates inner spaces"],
  ['#SBATCH -o run-#{zeropadding(:n, 4)}.log',               true,  "hideable field (:n)"],
  ['#SBATCH -J #{name}-#{zeropadding(n, 4)}',                true,  "mixed with a plain field"],
  ['#SBATCH -a #{zeropadding(h, 2)}-#{zeropadding(m, 2)}',   true,  "two padded fields, separated"],
  ['#SBATCH -x #{zeropadding(n, 2)}-#{calc(n * 2)}',         false, "alongside calc()"],
  ['#SBATCH -y #{zeropadding(calc(n * 2), 3)}',              false, "wrapping calc()"],
  ['#SBATCH -z #{zeropadding(n, 2)}-#{dirname(wd)}',         false, "alongside dirname()"],
  ['#SBATCH --stamp=#{zeropadding(h, 2)}#{zeropadding(m, 2)}', false, "adjacent, cannot be split"],
].each do |tpl, want, why|
  p = pattern_for(tpl)
  parseable = !p.nil? && p[:regex].to_s.start_with?("/")
  check("#{why}: #{tpl}", parseable, want)
end
puts

puts "2. --time= keeps its dedicated parser, not a zeropad regex"
p = pattern_for('#SBATCH --time=#{d}-#{zeropadding(h, 2)}:#{zeropadding(m, 2)}:#{zeropadding(s, 2)}')
check("parseType is slurm_time", p[:parse_type], "slurm_time")
check("no regex is generated",   p[:regex],      "null")
check("all four fields kept",    p[:keys],       "'d', 'h', 'm', 's'")
puts

puts "3. generated regex and zeroPad flags"
[
  ['#SBATCH -o run-#{zeropadding(n, 4)}.log',              '(\d+)',              "true"],
  ['#SBATCH -J #{name}-#{zeropadding(n, 4)}',              '(.*?)\-(\d+)',       "false, true"],
  ['#SBATCH -a #{zeropadding(h, 2)}-#{zeropadding(m, 2)}', '(\d+)\-(\d+)',       "true, true"],
].each do |tpl, want_fragment, want_flags|
  p = pattern_for(tpl)
  check("regex contains #{want_fragment}", p[:regex].include?(want_fragment), true)
  check("zeroPad flags for #{tpl}",        p[:zero_pad],                      want_flags)
end
# A line with no padded field must not carry the flag array at all.
check("no zeroPad key when nothing is padded", pattern_for('#SBATCH -n #{n}')[:zero_pad], nil)
puts

puts "4. round trip: value -> padded line -> capture -> value"
[
  # [value, pad width]
  [5,     2],   # ordinary case
  [125,   4],
  [0,     3],   # zero pads to 000 and must come back as 0
  [7,     1],   # width 1, nothing to pad
  [12345, 3],   # value longer than the pad width, so it is left as-is
].each do |value, width|
  tpl      = "\#SBATCH -o run-\#{zeropadding(n, #{width})}.log"
  rendered = "#SBATCH -o run-#{pad(value, width)}.log"
  p        = pattern_for(tpl)
  src      = p[:regex][1..-2]
  md       = Regexp.new(src).match(rendered)
  captured = md ? md.captures[0] : nil
  check("width #{width}, value #{value}: line is #{rendered.inspect}", !md.nil?, true)
  check("width #{width}, value #{value}: recovered", captured && strip_pad(captured), value.to_s)
end
puts

puts "5. round trip with a neighbouring plain field"
tpl      = '#SBATCH -J #{name}-#{zeropadding(n, 4)}'
rendered = "#SBATCH -J my-job-#{pad(42, 4)}"
md       = Regexp.new(pattern_for(tpl)[:regex][1..-2]).match(rendered)
check("line matches", !md.nil?, true)
# The first capture is lazy, but it still backtracks until the rest of the
# pattern fits — so it takes "my-job" rather than stopping at the first hyphen,
# because "job-0042" is not all digits.
check("plain field captured", md && md.captures[0], "my-job")
check("padded field captured and stripped", md && strip_pad(md.captures[1]), "42")
puts

puts "6. a padded capture will not match non-digits"
src = pattern_for('#SBATCH -o run-#{zeropadding(n, 4)}.log')[:regex][1..-2]
check("digits match",      !Regexp.new(src).match("#SBATCH -o run-0125.log").nil?, true)
check("letters do not",    Regexp.new(src).match("#SBATCH -o run-abcd.log").nil?,  true)
check("empty does not",    Regexp.new(src).match("#SBATCH -o run-.log").nil?,      true)
puts
puts

puts "#{PASS} passed, #{FAILURES.size} failed"
unless FAILURES.empty?
  puts
  FAILURES.each { |m| puts "FAIL #{m}" }
  exit 1
end
