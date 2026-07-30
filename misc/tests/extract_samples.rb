#!/usr/bin/env ruby
# Extract every form.yml sample from docs/application.html into samples/.
#
# The documentation is the source of truth: this script is re-run by
# run_tests.rb, so samples/ always mirrors the current docs. Each directory is
# named "<N>_<section id>", where N is the sample's position among all code
# blocks in the docs (e.g. 1_number, 21_set). The manifest example is block 0
# and is not extracted, so numbering starts at 1.
#
# A few blocks in the docs are fragments rather than complete form.yml files
# (an alternative "options:" list, script/submit sections, the header section,
# and an ERB conditional). Those are wrapped into complete samples below and
# keep the position number of their original block.

require 'cgi'
require 'fileutils'

DOCS = File.expand_path('../../docs/application.html', __dir__)
OUT  = File.expand_path('samples', __dir__)

src = File.read(DOCS, encoding: "UTF-8")

# Collect <pre> blocks in document order, tagged with the enclosing section id.
samples = []
section = nil
counts  = Hash.new(0)
src.scan(%r{<h[23] id="([^"]+)">|<pre>(.*?)</pre>}m) do |heading, pre|
  if heading
    section = heading
  else
    counts[section] += 1
    samples << { idx: samples.size, sec: section, n: counts[section],
                 text: CGI.unescapeHTML(pre).strip + "\n" }
  end
end

def find(samples, sec, n)
  s = samples.find { |x| x[:sec] == sec && x[:n] == n }
  raise "sample #{sec}#{n} not found in docs" if s.nil?
  s
end

# Like find(), but returns nil instead of raising. Used for the synthesised
# fragment samples below, whose documentation sections are optional: a section
# that has been renamed or removed means "nothing to synthesise here", not a
# broken extractor.
def find_optional(samples, sec, n)
  samples.find { |x| x[:sec] == sec && x[:n] == n }
end

def sample_name(sample)
  "#{sample[:idx]}_#{sample[:sec].tr('-', '_')}"
end

def write_sample(name, text)
  dir = File.join(OUT, name)
  FileUtils.mkdir_p(dir)
  file = text.include?("<%") ? "form.yml.erb" : "form.yml"
  File.write(File.join(dir, file), text)
end

FileUtils.rm_rf(OUT)

# 1. All complete "form:" samples, as-is.
samples.each do |s|
  next unless s[:text].start_with?("form:")
  write_sample(sample_name(s), s[:text])
end

# 2. disable section, 2nd block: an alternative "options:" list (enable-).
#    Substitute it into the first disable sample.
base = find(samples, "disable", 1)[:text]
frag = find(samples, "disable", 2)
raise "unexpected disable fragment" unless frag[:text].start_with?("options:")
new_options = frag[:text].lines[1..].map { |l| "    #{l}" }.join
replaced = base.sub(/^    options:\n      - \[ Fugaku.*\n      - \[ Tsubame.*\n/,
                    "    options:\n#{new_options}")
raise "#{sample_name(frag)} synthesis failed (docs changed?)" if replaced == base
write_sample(sample_name(frag), replaced)

# 3. overwrite_warning section: script/submit fragments, wrapped with a form.
#    Optional: skipped when the docs have no such section.
script_frag = find_optional(samples, "overwrite_warning", 1)
submit_frag = find_optional(samples, "overwrite_warning", 2)
if script_frag && submit_frag
  raise "unexpected overwrite_warning fragments" unless
    script_frag[:text].start_with?("script:") && submit_frag[:text].start_with?("submit:")

  write_sample(sample_name(script_frag), <<~YML)
    form:
      comment:
        widget: text
        label: Comment
        value: test

    #{script_frag[:text].chomp}
        #!/bin/bash
        #comment=\#{comment}
  YML

  write_sample(sample_name(submit_frag), <<~YML)
    form:
      comment:
        widget: text
        label: Comment
        value: test

    script: |
      #!/bin/bash
      #comment=\#{comment}

    #{submit_frag[:text].chomp}
        sbatch \#{OC_SCRIPT_LOCATION}/\#{OC_SCRIPT_NAME}
  YML
end

# 4. header section, 1st block: a custom header, wrapped with a form.
header_frag = find(samples, "header", 1)
raise "unexpected header fragment" unless header_frag[:text].start_with?("header:")
write_sample(sample_name(header_frag), <<~YML)
  #{header_frag[:text].chomp}

  form:
    comment:
      widget: text
      label: Comment
      value: test

  script: |
    #comment=\#{comment}
YML

# 5. header section, 2nd block: an ERB conditional form entry.
#    Indent it into the form section (run_tests.rb renders with
#    @OC_DIR_NAME == "Slurm", so the branch is taken).
erb_frag = find(samples, "header", 2)
raise "unexpected erb fragment" unless erb_frag[:text].start_with?("<% if")
indented = erb_frag[:text].lines.map { |l| l.start_with?("<%") ? l : "  #{l}" }.join
write_sample(sample_name(erb_frag), <<~YML)
  form:
  #{indented.chomp}
    comment:
      widget: text
      label: Comment
      value: test

  script: |
    #SBATCH -p \#{queue}
    #comment=\#{comment}
YML

puts "extracted #{Dir[File.join(OUT, '*')].size} samples into #{OUT}"
