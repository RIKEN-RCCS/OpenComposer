#!/usr/bin/env ruby
# Smoke test for form.yml processing.
#
# Re-extracts every sample from docs/application.html (see
# extract_samples.rb), then runs each sample in samples/ and sample_apps/
# through the form generators in lib/form.rb and checks that:
#
#   1. the YAML (or ERB + YAML) parses,
#   2. the "form:" section passes the same validations as run.rb,
#   3. HTML generation raises no exception and is non-empty,
#   4. every widget key appears as an element id in the generated HTML,
#   5. the generated JavaScript is syntactically valid (node --check).
#
# Usage: ruby misc/tests/run_tests.rb

require "cgi"
require "erb"
require "json"   # lib/form.rb calls to_json when emitting the enabledBy map
require "set"
require "yaml"
require "tmpdir"

ROOT = File.expand_path("../..", __dir__)

load File.join(__dir__, "extract_samples.rb")

# Constants normally defined in run.rb.
OC_SCRIPT_CONTENT      = "_script_content"
SUBMIT_CONTENT         = "_submit_content"
HEADER_SCRIPT_LOCATION = "_script_location"
HEADER_SCRIPT_NAME     = "_script_1"
HEADER_JOB_NAME        = "_script_2"
HEADER_CLUSTER_NAME    = "_cluster_name"

WIDGETS = %w[number text email select multi_select radio checkbox path].freeze

# lib/form.rb defines Sinatra helpers. Load its body into a plain class so the
# generators can be called without booting the web app.
form_src = File.read(File.join(ROOT, "lib", "form.rb"), encoding: "UTF-8")
lines = form_src.lines
raise "unexpected structure of lib/form.rb" unless lines.first.strip == "helpers do"

FormHarness = Class.new do
  def escape_html(str) = CGI.escapeHTML(str.to_s)
  def halt(code, msg) = raise("halt #{code}: #{msg}")

  def initialize
    @table_index = 1
    @conf = {
      "submit_color" => "#fff", "non_script_color" => "#fff",
      "submit_button_color" => "#fff", "non_script_button_color" => "#fff",
    }
  end
  attr_reader :js
end
FormHarness.class_eval(lines[1..-2].join, File.join(ROOT, "lib", "form.rb"), 2)

# Rendering context for *.yml.erb, mirroring the variables run.rb exposes.
# @OC_DIR_NAME is fixed to "Slurm" so conditional samples take their branch.
class ErbContext
  def initialize(app_name)
    @OC_APP_NAME = app_name
    @OC_DIR_NAME = "Slurm"
    @conf = {}
  end

  def render(path)
    ERB.new(File.read(path, encoding: "UTF-8"), trim_mode: "-").result(binding)
  end
end

def load_form(dir)
  name = File.basename(dir)
  erb_path = Dir[File.join(dir, "form.yml.erb")].first
  yml_path = File.join(dir, "form.yml")
  if erb_path
    YAML.load(ErbContext.new(name).render(erb_path))
  elsif File.exist?(yml_path)
    YAML.load_file(yml_path)
  end
end

DEFAULT_HEADER = YAML.load(
  ErbContext.new("test").render(File.join(ROOT, "lib", "header.yml.erb"))
)["header"]

NODE = system("node --version > /dev/null 2>&1")
# macOS ships JavaScriptCore's shell, which parses the same syntax. Used as a
# fallback so the JS check still runs on developer Macs without Node installed.
JSC = "/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc"
JSC_OK = !NODE && File.executable?(JSC)
warn "node not found: using #{JSC} for JavaScript syntax checks" if JSC_OK
warn "neither node nor jsc found: skipping JavaScript syntax checks" if !NODE && !JSC_OK

def check_js_syntax(js, name, errors)
  return unless NODE || JSC_OK
  Dir.mktmpdir do |tmp|
    path = File.join(tmp, "#{name}.js")
    File.write(path, js)
    if NODE
      out = `node --check #{path} 2>&1`
      errors << "generated JS is invalid:\n#{out}" unless $?.success?
    else
      # new Function() parses without executing, matching `node --check`.
      script = File.join(tmp, "check.js")
      File.write(script, <<~JS)
        try { new Function(readFile(#{path.to_json})); }
        catch (e) { print("" + e); }
      JS
      out = `#{JSC} #{script} 2>&1`.strip
      errors << "generated JS is invalid:\n#{out}" unless out.empty?
    end
  end
end

# Assemble the generated JS the same way views/form.erb embeds it.
def assemble_js(js)
  <<~JS
    var ocForm = {};
    ocForm.scriptLinePatterns = [];
    ocForm.enabledBy = {};
    #{js["script_patterns"]}
    ocForm.onceExec = function() {
    #{js["once"]}
    };
    ocForm.execDynamicWidget = function(fromId) {
    #{js["init_dw"].lines.map(&:chomp).sort.uniq.join("\n")}
    #{js["exec_dw"]}
    };
    ocForm.updateScriptContents = function(selectedValues) {
    #{js["script"]}
    };
    ocForm.updateSubmitContents = function(selectedValues) {
    #{js["submit"]}
    };
  JS
end

def run_sample(dir)
  errors = []
  name = File.basename(dir)

  body = load_form(dir)
  return ["no form.yml found"] if body.nil?

  # Same validations as run.rb.
  errors << '"form:" must be defined' unless body.key?("form")
  errors << '"form:" must have a key' if body.key?("form") && !body["form"]
  return errors unless errors.empty?

  body["form"].each do |key, value|
    errors << "invalid widget name: #{key}" unless key.match?(/^[a-zA-Z][a-zA-Z0-9_]*$/)
    widget = value.is_a?(Hash) ? value["widget"] : nil
    errors << "unknown widget for #{key}: #{widget.inspect}" unless WIDGETS.include?(widget)
  end
  return errors unless errors.empty?

  header = body.key?("header") ? body["header"] : DEFAULT_HEADER

  f = FormHarness.new
  html = f.output_header(body, header, name, name)
  html += f.output_body(body, header, name, name)

  errors << "generated HTML is empty" if html.strip.empty?

  # Every widget key must appear as an element id (plain or _1-suffixed).
  keys = body["form"].keys
  keys += header.keys if header
  keys.each do |key|
    next if key.start_with?("_") # internal widgets such as _script_content
    found = ["id=\"#{key}\"", "id=\"#{key}_1\"", "id='#{key}'", "id='#{key}_1'"]
              .any? { |id| html.include?(id) }
    errors << "id for widget \"#{key}\" not found in HTML" unless found
  end

  check_js_syntax(assemble_js(f.js), name, errors)
  errors
rescue Exception => e
  ["exception: #{e.message} (#{e.class})"]
end

# Sample directories are named "<N>_<section>"; sort them by position number.
targets  = Dir[File.join(__dir__, "samples", "*")].sort_by { |d| File.basename(d).to_i }
targets += Dir[File.join(ROOT, "sample_apps", "*")].sort.select { |d| File.directory?(d) }

failed = 0
targets.each do |dir|
  label = dir.sub("#{ROOT}/", "")
  errors = run_sample(dir)
  if errors.empty?
    puts "PASS #{label}"
  else
    failed += 1
    puts "FAIL #{label}"
    errors.each { |e| puts "     #{e}" }
  end
end

puts "-" * 40
puts "#{targets.size - failed}/#{targets.size} samples passed"
exit(failed.zero? ? 0 : 1)
