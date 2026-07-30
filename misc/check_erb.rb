#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Compile-check every ERB view the way the production OnDemand stack does.
#
# WHY: Open Composer renders its views through Sinatra/Tilt, which use Erubi.
# Newer Tilt/Erubi do NOT trim the newline between, e.g., `<% case %>` and the
# first `<% when %>`, so such templates compile on an older local stack but
# raise a SyntaxError on production. This script reproduces the strict
# compilation so those errors are caught before deploy — without needing a
# running server or a browser.
#
# It compiles the generated Ruby (it does NOT execute the templates, so missing
# helpers / instance variables are irrelevant — only true syntax errors fail).
#
# Usage:
#   ruby misc/check_erb.rb            # checks views/*.erb (default)
#   ruby misc/check_erb.rb path ...   # checks the given files/dirs
#
# Exit code 0 = all good, 1 = at least one template failed (CI-friendly).

require "erb"

targets = ARGV.empty? ? ["views"] : ARGV
files = targets.flat_map do |t|
  if File.directory?(t)
    Dir.glob(File.join(t, "**", "*.erb"))
  else
    [t]
  end
end.uniq.sort

abort "No .erb files found in: #{targets.join(', ')}" if files.empty?

# Build the candidate compilers. Erubi (used by Tilt in production) is preferred
# and added when available; the stdlib ERB modes are always run and already
# reproduce the case/when class of failure.
def erb_src(src, trim)
  ERB.new(src, trim_mode: trim).src
end

# Production's Tilt renders through STDLIB ERB (Erubi is not on its load path),
# and stdlib ERB does NOT trim the newline between e.g. `<% case %>` and the
# first `<% when %>`. So the stdlib `trim: nil` mode below is the prod-faithful,
# strict check — it is what reproduces the production SyntaxError. The other
# modes are extra coverage. (Erubi, if ever used, is MORE lenient and would
# hide such bugs, so it is deliberately not relied upon here.)
compilers = {
  "ERB(trim: nil)" => ->(s) { erb_src(s, nil) },   # == prod (Tilt stdlib ERB); catches case/when
  "ERB(trim: '-')" => ->(s) { erb_src(s, "-") },
  "ERB(trim: '>')" => ->(s) { erb_src(s, ">") },
}

failures = 0
files.each do |file|
  src = File.read(file)
  file_failed = false
  compilers.each do |name, build|
    begin
      ruby = build.call(src)
      # Wrap in a method so layout templates' `yield` is valid — Tilt compiles
      # templates into a method too. Still raises on real syntax errors; never runs.
      RubyVM::InstructionSequence.compile("def __oc_tmpl__\n#{ruby}\nend")
    rescue SyntaxError => e
      file_failed = true
      detail = e.message.lines.grep(/unexpected|expecting/).first&.strip || e.message.lines.first&.strip
      puts "FAIL  #{file}  [#{name}]  #{detail}"
    end
  end
  puts "ok    #{file}" unless file_failed
  failures += 1 if file_failed
end

puts
if failures.zero?
  puts "All #{files.size} ERB template(s) compile cleanly."
  exit 0
else
  puts "#{failures} of #{files.size} ERB template(s) FAILED to compile."
  exit 1
end
