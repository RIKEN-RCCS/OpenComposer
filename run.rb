require "sinatra"
require "date"
require "uri"
require "open3"
require "shellwords"
require "net/http"
require "set"
require "sinatra/reloader" if ENV.fetch("RACK_ENV", "production") == "development"
require "yaml"
require "erb"
require "sqlite3"
require "json"
require "pstore"
require "time"
require "fileutils"
require "etc"
require "./lib/index"
require "./lib/form"
require "./lib/history"
require "./lib/scheduler"

set :environment, ENV.fetch("RACK_ENV", "production").to_sym
set :host_authorization, { permitted_hosts: [] } if ENV.fetch("RACK_ENV", "production") == "development"
set :erb, trim: "-"

# When running behind OOD's nginx reverse proxy, TLS is terminated upstream and
# X-Forwarded-Proto: https is set. Rack sees plain HTTP internally, so rewrite
# rack.url_scheme here so that request.url / request.base_url / redirect all
# produce https:// URLs.
before do
  if request.env['HTTP_X_FORWARDED_PROTO'] == 'https'
    request.env['rack.url_scheme'] = 'https'
  end
end

configure :development do
  register Sinatra::Reloader
  also_reload "./lib/**/*.rb"
end

# Internal Constants
VERSION                ||= "2.0.2"
# App root captured once at load time. File lookups resolve against this instead
# of the live process working directory, which Dir.chdir (used in the submit
# path) mutates process-wide — otherwise a concurrent request could resolve
# ./conf.yml or ./generic_apps against the wrong directory.
APP_ROOT               ||= File.expand_path(__dir__)
SCHEDULERS_DIR_PATH    ||= "./lib/schedulers"
HISTORY_ROWS           ||= 10
JOB_STATUS             ||= { "queued" => "QUEUED", "running" => "RUNNING", "completed" => "COMPLETED", "failed" => "FAILED", "cancelled" => "CANCELLED", "unknown" => "UNKNOWN" }
JOB_ID                 ||= "id"
JOB_APP_NAME           ||= "appName"
JOB_DIR_NAME           ||= "appPath"
JOB_STATUS_ID          ||= "status"
HEADER_SCRIPT_LOCATION ||= "_script_location"
HEADER_SCRIPT_NAME     ||= "_script_1"
HEADER_JOB_NAME        ||= "_script_2"
HEADER_CLUSTER_NAME    ||= "_cluster_name"
OC_SCRIPT_CONTENT      ||= "_script_content"
SCRIPT_CONTENT         ||= OC_SCRIPT_CONTENT  # Compatibility with previous versions
FORM_LAYOUT            ||= "_form_layout"
SUBMIT_BUTTON          ||= "_submitButton"
SUBMIT_CONFIRM         ||= "_submitConfirm"
SUBMIT_CONTENT         ||= "_submit_content"
SUBMIT_FORM            ||= "_submit_form"
JOB_NAME               ||= "Job Name"
JOB_PARTITION          ||= "Partition"
JOB_SUBMISSION_TIME    ||= "Submission Time"
JOB_KEYS               ||= "job_keys"
SKIP_KEYS ||= ['splat', OC_SCRIPT_CONTENT]
DEFINED_KEYS ||= {
  JOB_APP_NAME           => 'OC_APP_NAME',
  JOB_DIR_NAME           => 'OC_DIR_NAME',
  HEADER_SCRIPT_LOCATION => 'OC_SCRIPT_LOCATION',
  HEADER_SCRIPT_NAME     => 'OC_SCRIPT_NAME',
  HEADER_JOB_NAME        => 'OC_JOB_NAME',
  HEADER_CLUSTER_NAME    => 'OC_CLUSTER_NAME'
}.freeze
HISTORY_KEY_MAP ||= {
  "OC_HISTORY_JOB_NAME"        => JOB_NAME,
  "OC_HISTORY_PARTITION"       => JOB_PARTITION,
  "OC_HISTORY_SUBMISSION_TIME" => JOB_SUBMISSION_TIME,
  "OC_HISTORY_START_TIME"      => "Start",
  "OC_HISTORY_END_TIME"        => "End",
  "OC_HISTORY_OUTPUT_FILE"     => "StdOut",
  "OC_HISTORY_ERROR_FILE"      => "StdErr"
}.freeze
CLUSTERS_KEYS ||= ["scheduler", "login_node", "ssh_wrapper", "bin", "bin_overrides", "scheduler_env", "copy_environment", "sge_root", "gpu_memory"].freeze
MODULES_CACHE_TTL ||= 86_400  # 24 hours
SCHEDULER_TO_GENERIC_APP ||= {
  "slurm"       => "Slurm",
  "pbspro"      => "PBS",
  "miyabi"      => "PBS",
  "sge"         => "Grid_Engine",
  "fujitsu_tcs" => "Fujitsu_TCS"
}.freeze

# Structure of manifest
Manifest ||= Struct.new(:dirname, :name, :category, :description, :icon, :related_apps, :homepage, :hidden, :documentation, :tags)

# Convert "#RRGGBB" to an "rgba(r, g, b, a)" string, for the focus-ring shadow in
# views/layout.erb. Falls back to Bootstrap's own accent (#0D6EFD) if the value is
# not a 6-digit hex, so a typo in conf.yml.erb cannot break the stylesheet.
def hex_to_rgba(hex, alpha)
  m = /\A#?([0-9A-Fa-f]{6})\z/.match(hex.to_s.strip)
  r, g, b = m ? m[1].scan(/../).map { |c| c.to_i(16) } : [13, 110, 253]
  "rgba(#{r}, #{g}, #{b}, #{alpha})"
end

# Create a YAML or ERB file object. Give priority to ERB.
# If the file does not exist, return nil.
def read_yaml(yml_path)
  erb_path = yml_path + ".erb"
  if File.exist?(erb_path)
    return YAML.load(ERB.new(File.read(erb_path), trim_mode: "-").result(binding))
  elsif File.exist?(yml_path)
    return YAML.load_file(yml_path)
  end
  return nil
end

# Process-wide cache for the parsed application config. Rendering conf.yml.erb
# through ERB and parsing the YAML is comparatively expensive, yet create_conf
# runs on EVERY request — including one per tile on the New Custom Template page.
# On a shared/high-latency filesystem that repeated work made
# icons load slowly and intermittently blank. Cache the parsed result and only
# redo it when the source file's mtime changes. A deep copy is returned so
# callers may mutate their conf freely without corrupting the cache.
CONF_CACHE ||= { mutex: Mutex.new, path: nil, mtime: nil, raw: nil }

def read_yaml_cached(yml_path)
  erb_path = yml_path + ".erb"
  src = File.exist?(erb_path) ? erb_path : (File.exist?(yml_path) ? yml_path : nil)
  return read_yaml(yml_path) if src.nil?  # nothing on disk; preserve original behavior

  mtime = File.mtime(src).to_f
  CONF_CACHE[:mutex].synchronize do
    if CONF_CACHE[:path] != src || CONF_CACHE[:mtime] != mtime
      CONF_CACHE[:raw]   = read_yaml(yml_path)
      CONF_CACHE[:path]  = src
      CONF_CACHE[:mtime] = mtime
    end
    Marshal.load(Marshal.dump(CONF_CACHE[:raw]))
  end
end

# Download (and cache for 24 h) the modules-list JSON.
# Returns a Hash keyed by module name, or {} on failure.
def fetch_modules_list(data_dir, url = nil)
  # No catalog configured: the module widgets and the automatic GPU badge are
  # simply inactive. Sites that want them set "modules_list_url" in conf.yml.erb.
  return {} if url.to_s.strip.empty?

  cache_path = File.join(data_dir, ".module-list-cache.json")

  if File.exist?(cache_path) && (Time.now.to_i - File.mtime(cache_path).to_i) < MODULES_CACHE_TTL
    return JSON.parse(File.read(cache_path))
  end

  uri      = URI(url)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 15, open_timeout: 10) do |http|
    http.get(uri.request_uri)
  end

  if response.is_a?(Net::HTTPSuccess)
    FileUtils.mkdir_p(data_dir)
    File.write(cache_path, response.body)
    return JSON.parse(response.body)
  end

  return JSON.parse(File.read(cache_path)) if File.exist?(cache_path)
  {}
rescue Exception
  JSON.parse(File.read(cache_path)) rescue {}
end

# Create a configuration object.
# Defaults are applied for any missing values.
def create_conf
  begin
    conf = read_yaml_cached(File.join(APP_ROOT, "conf.yml"))
    halt 500, "./conf.yml.erb does not be found." if conf.nil?
  rescue Exception => e
    halt 500, "There is something wrong with ./conf.yml or ./conf.yml.erb."
  end

  # Check required values
  ## app_dir
  halt 500, "In ./conf.yml.erb, \"apps_dir:\" must be defined." unless conf.key?("apps_dir")

  ## Reject deprecated "cluster:" configuration in v1.8.0 and later
  halt 500, 'In ./conf.yml.erb, "cluster:" is deprecated.' if conf["cluster"]

  ## Check scheduler
  if !conf.key?("scheduler")
    if !conf.key?("clusters")
      halt 500, "The ./conf.yml.erb must have \"scheduler:\""
    else
      conf["clusters"].each do |name, settings|
        if settings.nil? || !settings.key?("scheduler")
          halt 500, "In ./conf.yml.erb, the cluster \"#{name}\" must have \"scheduler:\""
        end
      end
    end
  end

  # Set initial values if not defined
  conf["data_dir"]                ||= ENV["HOME"] + "/composer"
  conf["history"]                 ||= HISTORY_KEY_MAP.keys
  conf["history"] = conf["history"].each_with_object({}) { |k, h| h[k] = nil } if conf["history"].is_a?(Array)
  conf["history_store_script"]    = conf.fetch("history_store_script", true)
  conf["history_efficiency"]      = conf.fetch("history_efficiency",   false)
  # Optional external module catalog. Empty means the module_load and
  # dependent_module_select widgets offer no versions and no GPU badge is
  # auto-applied; both degrade quietly rather than erroring.
  conf["modules_list_url"]        = conf.fetch("modules_list_url", "").to_s
  conf["footer"]                  ||= "&nbsp;"
  conf["thumbnail_width"]         ||= "100"
  conf["navbar_color"]            ||= "#3D3B40"
  conf["navbar_text_color"]       ||= "#FFFFFF"
  conf["footer_color"]            ||= conf["navbar_color"]
  conf["footer_text_color"]       ||= "#FFFFFF"
  conf["category_color"]          ||= "#5522BB"
  conf["category_text_color"]     ||= "#FFFFFF"
  conf["description_color"]       ||= conf["category_color"]
  conf["description_text_color"] ||= "#FFFFFF"
  # Application page: the title and the description sit on the description_color
  # band and default to its text color, but can each be set independently.
  conf["app_title_color"]            ||= conf["description_text_color"]
  conf["app_description_text_color"] ||= conf["description_text_color"]
  conf["form_color"]              ||= "#BFCFE7"
  conf["non_script_color"]        ||= "#FFE28A"
  conf["non_script_button_color"] ||= "#FFBF00"
  conf["submit_color"]            ||= "#FFCCCC"
  conf["submit_button_color"]     ||= "#FFAAAA"
  conf["history_action_color"]    ||= "#DC3545"
  # Accent palette. These drive the Bootstrap overrides in views/layout.erb —
  # links, the primary buttons, input focus rings, ticked checkboxes and the
  # history sort links. The defaults are Bootstrap's own values, so leaving them
  # unset renders exactly as stock Bootstrap; set them to restyle Open Composer
  # for a site without editing the view.
  conf["accent_color"]            ||= "#0D6EFD"
  conf["accent_contrast_color"]   ||= "#0A58CA"
  conf["body_text_color"]         ||= "#212529"
  conf["highlight_theme"]         ||= "vs"
  conf["directive_color"]         ||= "#D73A49"
  conf["show_home_directory"]   = conf.fetch("show_home_directory",   true)
  conf["show_shell_access"]     = conf.fetch("show_shell_access",     true)
  conf["show_open_ondemand"]    = conf.fetch("show_open_ondemand",    true)
  conf["open_ondemand_label"]   = conf.fetch("open_ondemand_label",   "Open OnDemand")

  # Set the values for "clusters:" and "history_db"
  if conf.key?("clusters")
    clusters  = conf["clusters"] || {}
    defaults  = CLUSTERS_KEYS.to_h { |k| [k, conf[k]] }
    CLUSTERS_KEYS.each { |k| conf[k] = {} }
    conf["history_db"] = {}

    clusters.each_key do |name|
      cluster_conf = clusters[name] || {}
      CLUSTERS_KEYS.each do |key|
        conf[key][name] = cluster_conf.fetch(key, defaults[key]) || defaults[key]
      end

      conf["history_db"][name] = File.join(conf["data_dir"], "#{name}.sqlite3")
    end
  else
    conf["history_db"] = File.join(conf["data_dir"], "#{conf["scheduler"]}.sqlite3")
  end

  # Normalize "gpu_memory:" once the per-cluster split above has run, so both the
  # single-cluster value and each cluster's own value end up in the same shape.
  if conf.key?("clusters")
    conf["gpu_memory"] = conf["gpu_memory"].transform_values { |v| normalize_gpu_memory(v) }
  else
    conf["gpu_memory"] = normalize_gpu_memory(conf["gpu_memory"])
  end

  # Create data directory
  FileUtils.mkdir_p(conf["data_dir"])

  return conf
end

# Normalize a "gpu_memory:" block into { "<model>" => { "default" => GB, "<partition>" => GB } }.
#
# Each model may be written either as a plain capacity in GB, or as a hash when
# cards of the same model differ in memory and the scheduler reports them under
# one GRES name (an A100 is "gpu:a100" whether it has 40 GB or 80 GB). In that
# case the keys are partition names, plus "default" for every other partition:
#
#   gpu_memory:
#     h100: 94
#     a100:
#       default: 80
#       genoa:   40
#
# Model names are matched case-insensitively against the job's "gpu:<model>"
# resources. An empty or malformed block yields {}, which leaves the Job
# Efficiency report showing GPU memory used without a percentage.
def normalize_gpu_memory(raw)
  return {} unless raw.is_a?(Hash)

  raw.each_with_object({}) do |(model, value), out|
    out[model.to_s.downcase.strip] =
      if value.is_a?(Hash)
        # Partition names keep their case, because the scheduler's are case-sensitive.
        # Only the literal "default" is folded, so "Default:" works as expected too.
        value.each_with_object({}) do |(part, gb), caps|
          key = part.to_s.strip
          caps[key =~ /\Adefault\z/i ? "default" : key] = gb.to_i
        end
      else
        { "default" => value.to_i }
      end
  end
end

# Export SGE_ROOT for the active cluster so Grid Engine commands can find their
# installation. Called on every request, not just submissions: the History and
# Nodes pages shell out to qstat/qacct/qhost too. An SGE_ROOT already present in
# the environment always wins.
def export_sge_root(conf, cluster_name)
  root = conf.key?("clusters") ? conf["sge_root"]&.[](cluster_name) : conf["sge_root"]
  ENV['SGE_ROOT'] ||= root unless root.to_s.empty?
end

# Create a manifest object in a specified application.
# If the name is not defined, the directory name is used.
def create_manifest(app_path)
  begin
    manifest = read_yaml(File.join(app_path, "manifest.yml"))
  rescue Exception => e
    return nil
  end

  ## Reject deprecated "related_app:" configuration in v1.8.0 and later
  halt 500, "In #{File.join(app_path, "manifest.yml")}, related_app: is deprecated." if manifest&.key?("related_app")

  dirname = File.basename(app_path)
  return Manifest.new(dirname, dirname, nil, nil, nil, nil, nil, false, nil) if manifest.nil?

  manifest["name"] ||= dirname
  return Manifest.new(dirname, manifest["name"], manifest["category"], manifest["description"], manifest["icon"], manifest["related_apps"], manifest["homepage"], manifest.fetch("hidden", false), manifest["documentation"], Array(manifest["tags"]))
end

# Create an array of manifest objects for all applications.
def create_all_manifests(apps_dir)
  halt 500, "apps_dir (#{apps_dir}) does not exist. Create the directory or update apps_dir in conf.yml.erb." unless Dir.exist?(apps_dir)

  all_manifests = Dir.children(apps_dir).each_with_object([]) do |dir, manifests|
    next if dir.start_with?(".") # Skip hidden files and directories

    app_path = File.join(apps_dir, dir)
    if ["form.yml", "form.yml.erb"].any? { |file| File.exist?(File.join(app_path, file)) }
      manifests << create_manifest(app_path)
    end
  end

  return all_manifests.compact
end

# Build a natural-sort key so that numeric prefixes/segments are ordered by
# value rather than lexically (e.g. "10_App" sorts after "2_App", not before).
# Digit runs become integers and are compared against a sentinel so that a
# number always sorts before text at the same position.
def natural_sort_key(str)
  str.to_s.downcase.scan(/\d+|\D+/).map { |s| s =~ /\A\d/ ? [0, s.to_i, ""] : [1, 0, s] }
end

# Parse #SBATCH directives in a batch script into a cache hash suitable for
# replace_with_cache, driven by the app's own script template so no hardcoded
# field mappings are needed.
def parse_sbatch_into_cache(script_content, body, app_name, dir_name)
  return {} if script_content.nil? || !body.is_a?(Hash)

  script_template = body["script"].to_s
  return {} if script_template.strip.empty?

  form_fields = body["form"] || {}

  # Mirror substitute_oc_constants + normalize_interpolation from form.rb
  # without requiring a Sinatra helper context.
  t = script_template.dup
  t.gsub!(/#\{\s*(.*?)\s*\}/, '#{\1}')
  t.gsub!(/\#\{OC_APP_NAME\}/,        app_name.to_s)
  t.gsub!(/\#\{:OC_APP_NAME\}/,       app_name.to_s)
  t.gsub!(/\#\{OC_DIR_NAME\}/,        dir_name.to_s)
  t.gsub!(/\#\{:OC_DIR_NAME\}/,       dir_name.to_s)
  t.gsub!(/\#\{OC_JOB_NAME\}/,        "\#{#{HEADER_JOB_NAME}}")
  t.gsub!(/\#\{:OC_JOB_NAME\}/,       "\#{#{HEADER_JOB_NAME}}")
  t.gsub!(/\#\{OC_SCRIPT_LOCATION\}/, "\#{#{HEADER_SCRIPT_LOCATION}}")
  t.gsub!(/\#\{:OC_SCRIPT_LOCATION\}/,"\#{#{HEADER_SCRIPT_LOCATION}}")
  t.gsub!(/\#\{OC_SCRIPT_NAME\}/,     "\#{#{HEADER_SCRIPT_NAME}}")
  t.gsub!(/\#\{:OC_SCRIPT_NAME\}/,    "\#{#{HEADER_SCRIPT_NAME}}")
  t.gsub!(/\#\{OC_CLUSTER_NAME\}/,    "\#{#{HEADER_CLUSTER_NAME}}")
  t.gsub!(/\#\{:OC_CLUSTER_NAME\}/,   "\#{#{HEADER_CLUSTER_NAME}}")

  # Build one regex pattern per #SBATCH template line
  directive_patterns = []
  t.each_line do |tline|
    tline = tline.strip
    next unless tline.start_with?('#SBATCH')

    fields      = []
    pattern_str = Regexp.escape(tline)

    tline.scan(/#\{([^}]+)\}/).each do |interp|
      expr = interp[0]
      if (m = expr.match(/^zeropadding\((\w+),\s*\d+\)$/))
        fields      << m[1]
        pattern_str  = pattern_str.sub(Regexp.escape("\#{#{expr}}"), '(\d+)')
      else
        fields      << expr
        pattern_str  = pattern_str.sub(Regexp.escape("\#{#{expr}}"), '(.*?)')
      end
    end

    next if fields.empty?
    begin
      directive_patterns << { regex: Regexp.new("^#{pattern_str}$"), fields: fields }
    rescue RegexpError
    end
  end

  # Match each #SBATCH line in the script against the template patterns.
  # Also record which fields were identified by an UNAMBIGUOUS line — one that
  # maps to a single widget. A line that several fields share (e.g.
  # "#SBATCH --ntasks=", emitted by BOTH the simple "Number of Cores" field and
  # the advanced "Number of Tasks" field) is ambiguous and must not, on its own,
  # auto-expand a hidden section. The advanced CPU section is identified
  # unambiguously only by its own "#SBATCH --cpus-per-task=" line.
  raw_cache = {}
  unambiguous_fields = Set.new
  script_content.each_line do |sline|
    sline = sline.strip
    next unless sline.start_with?('#SBATCH')
    line_fields = []
    directive_patterns.each do |dp|
      next unless (m = dp[:regex].match(sline))
      dp[:fields].each_with_index do |field, idx|
        val = m[idx + 1]&.strip
        raw_cache[field] = val if val && !val.empty? && !raw_cache.key?(field)
        line_fields << field
      end
    end
    # Unambiguous when every field this single line maps to belongs to one widget
    # (same base key once the _1/_2 suffix is stripped).
    if line_fields.map { |f| f.sub(/_\d+$/, '') }.uniq.length == 1
      line_fields.each { |f| unambiguous_fields << f }
    end
  end

  # Expand checkbox fields: split captured comma-separated values into
  # the per-option cache keys that replace_with_cache expects.
  cache = {}
  raw_cache.each do |field, val|
    widget_def = form_fields[field]
    if widget_def.is_a?(Hash) && widget_def["widget"] == "checkbox"
      sep          = widget_def["separator"] || ","
      checked_vals = val.split(sep).map(&:strip)
      (widget_def["options"] || []).each_with_index do |opt, idx|
        opt_val   = (opt.is_a?(Array) ? opt[1] : opt).to_s
        opt_label = (opt.is_a?(Array) ? opt[0] : opt).to_s
        cache["#{field}_#{idx + 1}"] = opt_label if checked_vals.include?(opt_val)
      end
    else
      cache[field] = val
    end
  end

  # Auto-check toggle checkboxes (e.g. "Show advanced options") whose enable-X
  # targets are already in the cache so the section renders expanded.
  form_fields.each do |key, field_def|
    next unless field_def.is_a?(Hash) && field_def["widget"] == "checkbox"
    (field_def["options"] || []).each_with_index do |opt, idx|
      next unless opt.is_a?(Array) && opt.length > 2
      enabled_fields = opt[2..-1].grep(/^enable-/).map { |a| a.sub(/^enable-/, '') }
      # Only auto-expand the section if one of its fields was identified by an
      # UNAMBIGUOUS script line — never from a line shared with another field.
      # This is what makes "Show advanced CPU options" tick only when
      # "--cpus-per-task" is present, not merely because a shared "--ntasks="
      # line happened to match the hidden advanced field too.
      next unless enabled_fields.any? do |f|
        present     = cache.keys.any? { |k| k == f || k.start_with?("#{f}_") }
        unambiguous = unambiguous_fields.any? { |uf| uf == f || uf.start_with?("#{f}_") }
        present && unambiguous
      end
      cache["#{key}_#{idx + 1}"] ||= opt[0].to_s
    end
  end

  cache
end

# Replace with cached value.
def replace_with_cache(form, cache)
  form.each do |key, value|
    next unless value.is_a?(Hash)
    value["value"] = case value["widget"]
                     when "number", "text", "email"
                       if value.key?("size")
                         value["size"].times.map do |i|
                           cache["#{key}_#{i+1}"] || Array(value["value"])[i]  # Array(nil)[i] is nil
                         end
                       else
                         cache[key] || value["value"]
                       end
                     when "select", "radio"
                       cache[key] || value["value"]
                     when "multi_select"
                       length = cache["#{key}_length"]&.to_i || 0
                       length.times.map { |i| cache["#{key}_#{i+1}"] }
                     when "checkbox"
                       value["options"].size.times.map { |i| cache["#{key}_#{i+1}"] }.compact
                     when "path"
                       cache["#{key}"] || value["value"]
                     end
  end
end

# Create a scheduler object.
def create_scheduler(conf)
  available = Dir.glob("#{SCHEDULERS_DIR_PATH}/*.rb").map { |f| File.basename(f, ".rb") }
  if conf.key?("clusters")
    schedulers = {}
    conf["scheduler"].each do |cluster_name, scheduler_name|
      halt 500, "No such scheduler_name (#{scheduler_name}) found." unless available.include?(scheduler_name)

      require "#{SCHEDULERS_DIR_PATH}/#{scheduler_name}.rb"
      schedulers[cluster_name] = Object.const_get(scheduler_name.capitalize).new
    end
  else
    scheduler_name = conf["scheduler"]
    halt 500, "No such scheduler_name (#{scheduler_name}) found." unless available.include?(scheduler_name)

    require "#{SCHEDULERS_DIR_PATH}/#{scheduler_name}.rb"
    schedulers = Object.const_get(scheduler_name.capitalize).new
  end

  schedulers
end

# Determine the action key based on script and submit sections.
# Rules:
# - Neither set:             -> "submit"
# - Both set:                -> "confirm-save"
# - Only script section set: -> "save"
# - Only submit section set: -> "confirm"
def get_form_action(body)
  script = body["script"]
  submit = body["submit"]

  # Determine script action
  script_action = if script.is_a?(Hash)
                    action = script["action"] || "submit"
                    ["submit", "save"].include?(action) ? action : "submit"
                  else
                    "submit"
                  end

  # Determine submit action
  submit_action = if submit.is_a?(Hash)
                    action = submit["action"] || "submit"
                    ["submit", "confirm"].include?(action) ? action : "submit"
                  else
                    "submit"
                  end

  # Combine rules
  case [script_action, submit_action]
  when ["submit", "submit"]
    "submit"
  when ["save", "confirm"]
    "confirm-save"
  when ["save", "submit"]
    "save"
  else # ["submit", "confirm"]
    "confirm"
  end
end

# Returns the directory where user templates are stored.
def templates_dir(conf)
  File.join(conf["data_dir"], "templates")
end

# Load all user-saved templates from the templates directory.
def load_templates(conf)
  dir = templates_dir(conf)
  return [] unless Dir.exist?(dir)
  Dir.glob(File.join(dir, "*.yml")).filter_map do |path|
    begin
      yaml = YAML.safe_load(File.read(path))
      next unless yaml.is_a?(Hash) && yaml["name"]
      app_path = yaml["app_path"].to_s.strip
      app_path = yaml.dig("values", "appPath").to_s.strip if app_path.empty?
      app_path = "_generic/Slurm" if app_path.empty?
      {
        "slug"        => File.basename(path, ".yml"),
        "name"        => yaml["name"],
        "description" => yaml["description"].to_s,
        "app_path"    => app_path,
        "icon"        => yaml["icon"].to_s,
        "position"    => yaml["position"].is_a?(Numeric) ? yaml["position"] : nil
      }
    rescue
      nil
    end
  end.sort_by { |t| [t["position"] ? 0 : 1, t["position"] || 0, t["name"].downcase] }
  # Positioned templates first (drag-and-drop order); unpositioned ones
  # (e.g. newly saved) follow alphabetically.
end

# Create a website of Home, Application, and History.
def show_website(job_id = nil, error_msg = nil, error_params = nil, script_path = nil)
  @conf          = create_conf
  @apps_dir      = @conf["apps_dir"]
  @version       = VERSION
  @my_ood_url        = request.base_url
  # Defaults to the OOD dashboard on the same host the request came in on, so the
  # "Return to OnDemand" link and navbar logo point back to OnDemand automatically
  # (no open_ondemand_url needed in conf). Admins can still override it.
  @open_ondemand_url = @conf.fetch("open_ondemand_url", "#{@my_ood_url}/pun/sys/dashboard")
  @script_name   = request.script_name
  @dir_name      = request.path_info.sub(/^\//, '')
  @cluster_name  = if @conf.key?("clusters")
                     escape_html(params[["history", "nodes"].include?(@dir_name) ? "cluster" : HEADER_CLUSTER_NAME] || @conf["clusters"].keys.first)
                   else
                     nil
                   end
  @login_node    = if @conf.key?("clusters")
                     @conf["login_node"][@cluster_name]
                   else
                     @conf["login_node"]
                   end
  export_sge_root(@conf, @cluster_name)

  @ood_logo_path = URI.join(@my_ood_url, @script_name + "/", "ood.png")
  @current_path  = File.join(@script_name, @dir_name)
  _modules_list  = fetch_modules_list(@conf["data_dir"], @conf["modules_list_url"])
  @gpu_names     = _modules_list.filter_map { |k, v| k.downcase if Array(v["domains"]).include?("gpu") }
  # category may be a single string or a list; sort by the primary (first) one.
  @all_manifests = create_all_manifests(@apps_dir).sort_by { |m| _c = Array(m.category).first; [_c&.downcase == "others" ? 1 : 0, natural_sort_key(_c || ""), natural_sort_key(m.name)] }
  @manifests     = @all_manifests.reject(&:hidden)
  @manifests_w_category, @manifests_wo_category = @manifests.partition(&:category)
  # User-saved custom templates. Loaded for every page so the navbar search
  # (ALL_APPS in layout.erb) can include them alongside the app templates.
  @templates     = load_templates(@conf)

  case @dir_name
  when ""
    @name = "Home"
    return erb :index
  when "history"
    @name          = "History"
    @scheduler     = create_scheduler(@conf)
    @bin           = @conf["bin"]
    @bin_overrides = @conf["bin_overrides"]
    @ssh_wrapper   = @conf["ssh_wrapper"]
    @statuses      = parse_history_statuses(params["statuses"])
    @filter        = escape_html(params["filter"])
    @filter_column = parse_history_filter_column(params["filter_column"], @conf)
    @sort          = parse_history_sort(params["sort"], @conf)
    @order         = parse_history_order(params["order"])
    @date_range, raw_date_from, raw_date_to = parse_history_date_range(params["date_range"], params["date_from"], params["date_to"])
    @date_from     = escape_html(raw_date_from)
    @date_to       = escape_html(raw_date_to)
    @filter_mode   = escape_html(params["filter_mode"] || "and")
    @detail_open   = escape_html(params["detail_open"] || "false")
    requested_rows = [(params["rows"] || HISTORY_ROWS).to_i, HISTORY_ROWS].max
    @current_page  = (params["p"] || 1).to_i
    offset         = (@current_page - 1) * requested_rows

    scheduler_s     = @conf.key?("clusters") ? @scheduler[@cluster_name]        : @scheduler
    bin_s           = @conf.key?("clusters") ? @bin[@cluster_name]               : @bin
    bin_overrides_s = @conf.key?("clusters") ? @bin_overrides[@cluster_name]     : @bin_overrides
    ssh_wrapper_s   = @conf.key?("clusters") ? @ssh_wrapper[@cluster_name]       : @ssh_wrapper
    sched_env_s     = @conf.key?("clusters") ? @conf["scheduler_env"][@cluster_name] : @conf["scheduler_env"]
    scancel_path = if bin_overrides_s&.key?("scancel")
      bin_overrides_s["scancel"]
    elsif bin_s && File.exist?(File.join(bin_s, "scancel"))
      File.join(bin_s, "scancel")
    else
      "scancel"
    end
    @cancel_command_prefix = [ssh_wrapper_s, scancel_path].compact.join(" ")

    db         = open_history_db(@conf, @cluster_name)
    deleted_db = open_deleted_db(@conf, @cluster_name, main_db: db)
    deleted_ids = Set.new(deleted_db.execute("SELECT _job_id FROM deleted_jobs").map { |r| r["_job_id"] })

    sacct_from = raw_date_from.to_s.empty? ? (Date.today - 6).strftime("%Y-%m-%d") : raw_date_from.to_s
    sacct_to   = raw_date_to.to_s.empty?   ? Date.today.strftime("%Y-%m-%d")        : raw_date_to.to_s
    all_sacct_jobs, @sacct_error, _cmd = scheduler_s.sacct_all_jobs(sacct_from, sacct_to, bin_s, bin_overrides_s, ssh_wrapper_s, sched_env_s)

    sacct_map = {}
    (all_sacct_jobs || []).each do |j|
      jid = j["JobID"].to_s.strip
      next unless valid_oc_job_id?(jid, scheduler_s)
      sacct_map[jid] = j
    end

    # Supplement sacct with squeue to catch PENDING jobs sacct may not report
    # (e.g. jobs submitted so recently they haven't appeared in sacct yet, or
    # Slurm configurations that omit PENDING jobs from sacct output).
    squeue_jobs, @squeue_error = scheduler_s.squeue_active_jobs(bin_s, bin_overrides_s, ssh_wrapper_s, sched_env_s)
    (squeue_jobs || []).each do |j|
      jid = j["JobID"].to_s.strip
      next unless valid_oc_job_id?(jid, scheduler_s)
      next if sacct_map.key?(jid)
      sacct_map[jid] = j
    end

    # Load DB rows for all known job IDs (sacct + squeue) so OC metadata
    # (app name, script, etc.) is joined for any newly discovered jobs too.
    db1_map = if sacct_map.empty?
                {}
              elsif sacct_map.size <= 900
                placeholders = (['?'] * sacct_map.size).join(',')
                db.execute("SELECT * FROM jobs WHERE _job_id IN (#{placeholders})", sacct_map.keys)
                  .each_with_object({}) { |r, h| h[r["_job_id"]] = r }
              else
                db.execute("SELECT * FROM jobs").each_with_object({}) { |r, h| h[r["_job_id"]] = r }
              end

    history_conf = @conf["history"].is_a?(Hash) ? @conf["history"] : {}
    oc_col_defs = {
      "OC_HISTORY_JOB_NAME"        => { "default_label" => "Job Name",        "job_key" => JOB_NAME,            "type" => "job_name",  "sortable" => true,  "responsive" => false },
      "OC_HISTORY_PARTITION"       => { "default_label" => "Partition",       "job_key" => JOB_PARTITION,       "type" => "text",      "sortable" => true,  "responsive" => true  },
      "OC_HISTORY_SUBMISSION_TIME" => { "default_label" => "Submission Time", "job_key" => JOB_SUBMISSION_TIME, "type" => "text",      "sortable" => true,  "responsive" => true  },
      "OC_HISTORY_START_TIME"      => { "default_label" => "Start Time",      "job_key" => "Start",             "type" => "text",      "sortable" => true,  "responsive" => true  },
      "OC_HISTORY_END_TIME"        => { "default_label" => "End Time",        "job_key" => "End",               "type" => "text",      "sortable" => true,  "responsive" => true  },
      "OC_HISTORY_OUTPUT_FILE"     => { "default_label" => "Output",          "job_key" => "StdOut",            "type" => "file_link", "sortable" => false, "responsive" => true  },
      "OC_HISTORY_ERROR_FILE"      => { "default_label" => "Error",           "job_key" => "StdErr",            "type" => "file_link", "sortable" => false, "responsive" => true  },
    }
    @conf_history_cols = history_conf.map do |k, v|
      conf_label = v.is_a?(Hash) ? v["label"] : nil
      defn = oc_col_defs[k]
      label = conf_label || (defn && defn["default_label"]) || k
      if defn
        defn.merge("key" => k, "label" => label)
      else
        { "key" => k, "job_key" => k, "label" => label, "type" => "text", "sortable" => false, "responsive" => true }
      end
    end
    extra_field_keys = history_conf.keys.reject { |k| k.start_with?("OC_HISTORY_") }

    history_search_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @jobs, @jobs_size = build_merged_history_jobs(
      sacct_map, db1_map, deleted_ids,
      @statuses, @filter, @filter_column, @filter_mode,
      raw_date_from.to_s, raw_date_to.to_s,
      @sort, @order, requested_rows, offset, scheduler_s,
      extra_field_keys
    )
    @history_search_elapsed_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - history_search_started_at

    @rows        = [requested_rows, @jobs_size].min
    @page_size   = (@rows == 0) ? 1 : ((@jobs_size - 1) / @rows) + 1
    @start_index = @jobs_size == 0 ? 0 : (@current_page - 1) * @rows
    @end_index   = @jobs_size == 0 ? 0 : [@current_page * @rows, @jobs_size].min - 1
    url_msg      = params["error_msg"]
    @error_msg   = error_msg || (url_msg.nil? || url_msg.empty? ? nil : escape_html(url_msg))

    @filter_column_items = history_filter_column_items(@conf)
    @date_range_items    = history_date_range_items
    @history_search_elapsed_label = format("%.3f", @history_search_elapsed_seconds || 0.0)

    return erb :history
  when "nodes"
    @name = "Nodes"
    return erb :nodes
  when "load_script"
    @name            = @conf.fetch("load_script_label", "Load or Create a Script from Disk")
    @ls_home         = Dir.home
    @ls_new_template = params["new_template"] == "1"
    return erb :load_script
  when "new_script"
    @name            = "New Script"
    @ls_new_template = params["new_template"] == "1"
    @ns_path         = params["path"].to_s.strip   # directory carried from the file browser
    # Mirror the All Templates list: every app, INCLUDING hidden ones. Pull the
    # featured "Slurm Submit Templates" (Job Script (Slurm) + GPU Job Script
    # (Slurm)) to the top; configurable via conf["new_script_featured_category"].
    featured_cat = (@conf["new_script_featured_category"] || "Slurm Submit Templates").to_s.downcase
    featured, rest = @all_manifests.partition do |m|
      Array(m.category).map { |c| c.to_s.downcase }.include?(featured_cat)
    end
    @ns_manifests = sort_featured(featured) + rest.sort_by { |m| natural_sort_key(m.name) }
    return erb :new_script
  when "all_templates"
    @name = "All Templates"
    # Order: featured Slurm templates (GPU Job Script + Job Script) first, then
    # the user's own custom templates, then every other app alphabetically.
    featured_cat = (@conf["new_script_featured_category"] || "Slurm Submit Templates").to_s.downcase
    featured, rest = @all_manifests.partition do |m|
      Array(m.category).map { |c| c.to_s.downcase }.include?(featured_cat)
    end
    @at_featured = sort_featured(featured)
    @at_rest     = rest.sort_by { |m| natural_sort_key(m.name) }
    # @templates (custom templates) is loaded in the preamble above.
    @show_all_templates_subfooter = true
    return erb :all_templates
  when "templates/new"
    @name = "New Template"
    generic_apps_dir = @conf["generic_apps_dir"] || "./generic_apps"
    configured_schedulers = if @conf["scheduler"].is_a?(Hash)
                               @conf["scheduler"].values.uniq.map(&:to_s)
                             else
                               [@conf["scheduler"].to_s]
                             end
    # Case-insensitive lookup so "Slurm", "SLURM", "slurm" all match
    applicable_generic_dirs = configured_schedulers
                                .map { |s| SCHEDULER_TO_GENERIC_APP[s.downcase] }
                                .compact.uniq
    all_generic = Dir.glob(File.join(generic_apps_dir, "*/manifest.yml")).filter_map do |path|
      create_manifest(File.dirname(path))
    end.sort_by { |m| natural_sort_key(m.name) }
    # Filter to the configured scheduler; if the lookup produced nothing, show all
    applicable_generic_dirs_down = applicable_generic_dirs.map(&:downcase)
    @generic_manifests = if applicable_generic_dirs_down.any?
                           all_generic.select { |m| applicable_generic_dirs_down.include?(m.dirname.downcase) }
                         else
                           all_generic
                         end
    return erb :new_template
  else # application form
    @table_index     = 1
    generic_apps_dir = @conf["generic_apps_dir"] || "./generic_apps"

    # Apps under the _generic/ URL prefix are loaded from generic_apps_dir and
    # are intentionally excluded from the main index listing shown to users.
    if @dir_name.start_with?("_generic/")
      @app_base_path = File.join(generic_apps_dir, @dir_name.sub(/\A_generic\//, ""))
      @manifest      = create_manifest(@app_base_path)
    else
      @manifest      = @all_manifests.find { |m| "#{m.dirname}" == @dir_name }
      @app_base_path = File.join(@apps_dir, @dir_name)
    end

    unless @manifest.nil?
      begin
        @name = @manifest["name"]
        @OC_APP_NAME = @name
        @OC_DIR_NAME = @manifest["dirname"]
        @body = read_yaml(File.join(@app_base_path, "form.yml"))

        # If the app's form file is missing (moved, deleted, or app not set),
        # fall back to the generic Slurm app so the history script can still be loaded.
        if @body.nil?
          generic_apps_dir = @conf["generic_apps_dir"] || "./generic_apps"
          fallback_app     = @conf["external_reload_app"] || "Slurm"
          @app_base_path   = File.join(generic_apps_dir, fallback_app)
          @manifest        = create_manifest(@app_base_path)
          @name            = @manifest&.[]("name") || fallback_app
          @OC_APP_NAME     = @name
          @OC_DIR_NAME     = @manifest&.[]("dirname") || "_generic/#{fallback_app}"
          @body            = read_yaml(File.join(@app_base_path, "form.yml")) || {}
        end

        @header = if @body.is_a?(Hash) && @body.key?("header")
                    @body["header"]
                  else
                    read_yaml("./lib/header.yml")["header"]
                  end
      rescue Exception => e
        @error_msg = e.message
        return erb :error
      end

      # Check if the form key exists. The form body may legitimately be empty
      # (a header-only app such as the generic Slurm app), so a "form:" with no
      # widgets is allowed. It is normalized to an empty hash below so the
      # rendering helpers (which call body["form"].merge(...)) do not crash.
      ["form.yml", "form.yml.erb"].each do |name|
        file = File.join(@app_base_path, name)
        next unless File.exist?(file)

        halt 500, "In ./#{file}, \"form:\" must be defined." unless @body.is_a?(Hash) && @body.key?("form")
      end
      @body["form"] ||= {} if @body.is_a?(Hash) && @body.key?("form")

      @form_action = get_form_action(@body)

      # Since the widget name is used as a variable in Ruby, it should consist of only
      # alphanumeric characters and underscores, and numbers should not be used at the
      # beginning of the name. Furthermore, underscores are also prohibited at the
      # beginning of the name to avoid conflicts with Open Composer's internal variables.
      if @body&.dig("form")
        invalid_keys = @body["form"].each_key.reject { |key| key.match?(/^[a-zA-Z][a-zA-Z0-9_]*$/) }
        unless invalid_keys.empty?
          @error_msg = "Widget name(s) (#{invalid_keys.join(', ')}) cannot be used.\n"
          return erb :error
        end
      end

      # Load cache
      @script_content = nil
      @submit_content = nil
      if params["template"]
        slug      = params["template"].gsub(/[^a-zA-Z0-9_\-]/, '')
        tmpl_path = File.join(templates_dir(@conf), "#{slug}.yml")
        if File.exist?(tmpl_path)
          begin
            tmpl  = YAML.safe_load(File.read(tmpl_path))
            cache = tmpl.is_a?(Hash) ? (tmpl["values"] || {}) : {}
            replace_with_cache(@header, cache)
            replace_with_cache(@body["form"], cache)
            @script_content          = escape_html(cache[OC_SCRIPT_CONTENT].to_s) if cache[OC_SCRIPT_CONTENT]
            @submit_content          = escape_html(cache[SUBMIT_CONTENT].to_s) if cache[SUBMIT_CONTENT]
            @template_slug           = slug
            @template_name           = tmpl.is_a?(Hash) ? tmpl["name"].to_s : ''
            @template_description    = tmpl.is_a?(Hash) ? tmpl["description"].to_s : ''
          rescue
          end
        end
      elsif params["jobId"] || job_id
        cluster_name = if @conf.key?("clusters")
                         params[params["jobId"] ? "cluster" : HEADER_CLUSTER_NAME] || @conf["clusters"].keys.first
                       end

        cache = nil
        id = if params["jobId"]
               params["jobId"]
             else
               job_id.is_a?(Array) ? job_id[0].to_s : job_id.to_s
             end
        begin
          db = open_history_db(@conf, cluster_name)
        rescue StandardError
          history_db = @conf.key?("clusters") ? @conf["history_db"][cluster_name] : @conf["history_db"]
          @error_msg = history_db.nil? ? "#{cluster_name} is invalid." : "#{history_db} is not found."
          return erb :error
        end
        record = find_job(db, id)
        cache = job_record_to_legacy_hash(record)

        if cache.nil?
          if @dir_name == "Slurm"
            sched_inst = create_scheduler(@conf)
            bin_val    = @conf["bin"]
            bin_ov_val = @conf["bin_overrides"]
            ssh_val    = @conf["ssh_wrapper"]
            sched_s    = @conf.key?("clusters") ? sched_inst[cluster_name] : sched_inst
            bin_s2     = @conf.key?("clusters") ? bin_val[cluster_name]    : bin_val
            bin_ov_s2  = @conf.key?("clusters") ? bin_ov_val[cluster_name] : bin_ov_val
            ssh_s2     = @conf.key?("clusters") ? ssh_val[cluster_name]    : ssh_val
            env_s2     = @conf.key?("clusters") ? @conf["scheduler_env"][cluster_name] : @conf["scheduler_env"]
            script_content, _err = sched_s.batch_script(id, bin_s2, bin_ov_s2, ssh_s2, env_s2)
            if script_content
              @script_content = escape_html(script_content)
              sbatch_cache = parse_sbatch_into_cache(script_content, @body, @OC_APP_NAME, @OC_DIR_NAME)
              replace_with_cache(@header, sbatch_cache)
              replace_with_cache(@body["form"], sbatch_cache)
            end
          else
            @error_msg = "Specified Job ID (#{id}) is not found."
            return erb :error
          end
        else
          replace_with_cache(@header, cache)
          replace_with_cache(@body["form"], cache)
          if !cache[OC_SCRIPT_CONTENT].to_s.strip.empty?
            @script_content = escape_html(cache[OC_SCRIPT_CONTENT])
          else
            # Script content not stored in DB — fetch from sacct -B
            sched_inst = create_scheduler(@conf)
            bin_val    = @conf["bin"]
            bin_ov_val = @conf["bin_overrides"]
            ssh_val    = @conf["ssh_wrapper"]
            sched_s    = @conf.key?("clusters") ? sched_inst[cluster_name] : sched_inst
            bin_s2     = @conf.key?("clusters") ? bin_val[cluster_name]    : bin_val
            bin_ov_s2  = @conf.key?("clusters") ? bin_ov_val[cluster_name] : bin_ov_val
            ssh_s2     = @conf.key?("clusters") ? ssh_val[cluster_name]    : ssh_val
            env_s2     = @conf.key?("clusters") ? @conf["scheduler_env"][cluster_name] : @conf["scheduler_env"]
            script_content, _err = sched_s.batch_script(id, bin_s2, bin_ov_s2, ssh_s2, env_s2)
            if script_content
              @script_content = escape_html(script_content)
              sbatch_cache = parse_sbatch_into_cache(script_content, @body, @OC_APP_NAME, @OC_DIR_NAME)
              replace_with_cache(@header, sbatch_cache)
              replace_with_cache(@body["form"], sbatch_cache)
            end
          end
          @submit_content = escape_html(cache[SUBMIT_CONTENT].to_s)
        end
      elsif !error_msg.nil? || !script_path.nil? # When job submission failed or script_path != nil (because after script file has been saved)
        replace_with_cache(@header, error_params)
        replace_with_cache(@body["form"], error_params)
        @script_content = escape_html(error_params[OC_SCRIPT_CONTENT])
        @submit_content = escape_html(error_params[SUBMIT_CONTENT])
      end

      # Set script content
      @script_label = if @body["script"].is_a?(Hash)
                        @body["script"]["label"] || "Script Content"
                      else
                        "Script Content"
                      end

      # Pre-fill the script location from ?path= — the directory the user was
      # browsing in the Load/Create file browser when they clicked New Script.
      ns_path = params["path"].to_s.strip
      if !ns_path.empty? && @header.is_a?(Hash) && @header[HEADER_SCRIPT_LOCATION].is_a?(Hash)
        @header[HEADER_SCRIPT_LOCATION]["value"] = ns_path
      end

      @job_id      = job_id.is_a?(Array) ? job_id.join(", ") : job_id
      @error_msg   = error_msg&.force_encoding('UTF-8')
      @script_path = script_path
      @new_template = params["new_template"] == "1"
      return erb :form
    else
      @error_msg = "#{request.url} is not found."
      return erb :error
    end
  end
end

# Raise a RuntimeError with the given message if the condition is false.
# This function is used in a check section of form.yml[.erb].
def oc_assert(condition, message = "Error exists in script content.")
  raise RuntimeError, message unless condition
end

# Set value to the specified instance variable (@#{key}) in the check section.
# If a value already exists, add value like [old, value] or "#{old}#{separator}#{value}".
def set_check_value(key, value, separator = nil)
  k = :"@#{key}"

  if instance_variable_defined?(k)
    old = instance_variable_get(k)

    if separator.nil?
      new_val =
        if old.is_a?(Array)
          if value.is_a?(Array)
            old.first.is_a?(Array) ? (old + [value]) : [old, value]
          else
            old + [value]
          end
        else
          [old, value]
        end
      instance_variable_set(k, new_val)
    else
      instance_variable_set(k, "#{old}#{separator}#{value}")
    end
  else
    instance_variable_set(k, value)
  end
end

# Output log
def output_log(action, scheduler, **details)
  base = "[#{Time.now}] [Open Composer] #{action} : scheduler=#{scheduler.class.name}"
  extra = details
            .reject { |_k, v| v.nil? || v.to_s.strip.empty? }
            .map    { |k, v| "#{k}=#{v}" }
            .join(" : ")
  puts [base, extra].reject(&:empty?).join(" : ")
end

# Return available module versions for the module_load widget.
# Looks up the given module name in the cached modules-list JSON and returns
# full "Name/version" strings, default version first.
get "/_module_avail" do
  content_type :json
  mod = params[:module].to_s.strip
  return [].to_json if mod.empty?

  conf       = create_conf
  all_mods   = fetch_modules_list(conf["data_dir"], conf["modules_list_url"])
  entry      = all_mods.find { |k, _| k.casecmp(mod).zero? }
  return [].to_json unless entry

  name, data    = entry
  versions      = Array(data["versions"])
  default_ver   = data["default"].to_s.strip
  default_full  = default_ver.empty? ? nil : "#{name}/#{default_ver}"

  full = versions.map { |v| "#{name}/#{v}" }
  sorted = full.sort.reverse  # newest first by string sort
  sorted.unshift(default_full) if default_full && sorted.delete(default_full)

  sorted.to_json
rescue Exception
  [].to_json
end

# Send a static application icon. Resolved against the app root (so it is immune
# to any Dir.chdir happening in a concurrent request), served with a browser
# cache header (icons are static — this stops the New Custom Template page from
# re-fetching every tile on each visit, which is what made them intermittently
# blank on remote/shared filesystems), and returning an honest 404 — instead of
# a silent, blank 200 — when the file is missing or the path escapes base_dir.
def serve_icon(base_dir, folder, icon)
  base      = File.expand_path(base_dir, APP_ROOT)
  icon_path = File.expand_path(File.join(folder.to_s, icon.to_s), base)
  halt 404 unless icon_path.start_with?(base + File::SEPARATOR) && File.file?(icon_path)
  cache_control :public, max_age: 86_400
  send_file(icon_path)
end

# Send a generic application icon.
get "/_generic_icon/:folder/:icon" do
  serve_icon(create_conf["generic_apps_dir"] || "./generic_apps", params[:folder], params[:icon])
end

# Send an application icon.
get "/:apps_dir/:folder/:icon" do
  serve_icon(create_conf["apps_dir"], params[:folder], params[:icon])
end

# Order the featured Slurm templates so the plain "Job Script" leads and the
# "GPU Job Script" follows, then any others alphabetically. Used by both the
# New Script picker and the All Templates list.
def sort_featured(manifests)
  manifests.sort_by { |m| [m.name.to_s.downcase.include?("gpu") ? 1 : 0, natural_sort_key(m.name)] }
end

# Ensure the current user has an SSH key in ~/.ssh, generating a passphrase-less
# one if none exists. On typical HPC/OOD deployments the user's home is shared
# with the login node, so the freshly generated public key is also appended to
# ~/.ssh/authorized_keys — that lets Open Composer submit jobs over SSH without
# a password prompt. Because the key uses a non-default name (e.g.
# opencomposer_ed25519), an IdentityFile line is also added to ~/.ssh/config so
# ssh actually offers it. Returns :exists, :created or :failed.
def ensure_user_ssh_key(key_type = "ed25519", key_name = "opencomposer")
  ssh_dir = File.join(Dir.home, ".ssh")
  FileUtils.mkdir_p(ssh_dir)
  File.chmod(0o700, ssh_dir)

  key_type = "ed25519" unless %w[ed25519 rsa ecdsa].include?(key_type.to_s)
  key_name = key_name.to_s.gsub(/[^A-Za-z0-9_.-]/, "")
  key_name = "opencomposer" if key_name.empty?
  base     = "#{key_name}_#{key_type}"

  # Leave any existing key in place — never overwrite a key the user already has
  # (standard default names or a previously generated Open Composer key).
  existing = (%w[id_ed25519 id_rsa id_ecdsa id_dsa] +
              %w[ed25519 rsa ecdsa dsa].map { |t| "#{key_name}_#{t}" })
             .map { |k| File.join(ssh_dir, k) }
  return :exists if existing.any? { |k| File.exist?(k) }

  key_path = File.join(ssh_dir, base)
  args = ["ssh-keygen", "-t", key_type, "-N", "", "-f", key_path, "-C", "Open Composer auto-generated key"]
  args += ["-b", "4096"] if key_type == "rsa"
  _out, _err, status = Open3.capture3(*args)
  return :failed unless status.success? && File.exist?(key_path)

  File.chmod(0o600, key_path)
  File.chmod(0o644, "#{key_path}.pub") if File.exist?("#{key_path}.pub")

  # Authorize the new key for passwordless SSH to the (shared-home) login node.
  pub  = File.read("#{key_path}.pub").strip
  auth = File.join(ssh_dir, "authorized_keys")
  unless File.exist?(auth) && File.read(auth).include?(pub)
    File.open(auth, "a") { |f| f.puts(pub) }
  end
  File.chmod(0o600, auth) if File.exist?(auth)

  # ssh only auto-offers id_* keys, so point it at our named key for all hosts.
  cfg = File.join(ssh_dir, "config")
  unless File.exist?(cfg) && File.read(cfg).include?(base)
    File.open(cfg, "a") { |f| f.write("\n# Added by Open Composer so ssh offers its auto-generated key\nHost *\n    IdentityFile ~/.ssh/#{base}\n") }
  end
  File.chmod(0o600, cfg) if File.exist?(cfg)
  :created
end

# Render a File::Stat#mode as an ls-style symbolic permission string, e.g.
# 0o100644 -> "rw-r--r--" (the three owner/group/other rwx triads only).
def symbolic_mode(mode)
  [(mode >> 6) & 7, (mode >> 3) & 7, mode & 7].map do |bits|
    "#{bits & 4 != 0 ? 'r' : '-'}#{bits & 2 != 0 ? 'w' : '-'}#{bits & 1 != 0 ? 'x' : '-'}"
  end.join
end

# Return a list of files and/or directories in JSON format.
get "/_files" do
  path = params[:path] || "."
  path = File.dirname(path) if File.file?(path)

  content_type :json
  if File.exist?(path)
    begin
      entries = Dir.children(path).map do |entry|
        full_path = File.join(path, entry)
        is_dir    = File.directory?(full_path)
        # size/mtime/owner/mode are best-effort: a broken symlink or permission
        # issue on a single entry must not break the whole listing, so fall back
        # to nil. owner/mode mirror OOD's optional "Owner"/"Mode" columns.
        size, mtime, owner, mode =
          begin
            st = File.stat(full_path)
            owner_name = (Etc.getpwuid(st.uid).name rescue st.uid.to_s)
            [is_dir ? nil : st.size, st.mtime.to_i, owner_name, symbolic_mode(st.mode)]
          rescue SystemCallError
            [nil, nil, nil, nil]
          end
        { name: entry, path: full_path, type: is_dir ? "directory" : "file",
          size: size, mtime: mtime, owner: owner, mode: mode }
      end.sort_by { |entry| entry[:name].downcase }
    rescue SystemCallError
      # Unreadable directory (e.g. permission denied) — report it the same way
      # as a non-existent one instead of raising a 500.
      entries = ""
    end
  else
    # When a non-existent directory is specified using the set-value statement of the dynamic form widget.
    entries = ""
  end

  { files: entries }.to_json
end

# Return the text content of a file for the history file overlay.
get "/_read_file" do
  path = params[:path].to_s.strip
  content_type :json
  return { error: "No path specified" }.to_json if path.empty?
  return { error: "File not found" }.to_json unless File.file?(path)

  max_bytes = 1_048_576 # 1 MB
  begin
    size    = File.size(path)
    return { empty: true }.to_json if size == 0
    content = File.open(path, "rb") { |f| f.read(max_bytes) } || ""
    { content: content.force_encoding("UTF-8").scrub("?"), truncated: size > max_bytes }.to_json
  rescue => e
    { error: "Could not read file: #{e.message}" }.to_json
  end
end

# Return whether the specified PATH is a file or a directory.
get "/_file_or_directory" do
  path = params[:path] || "."
  content_type :json

  if File.file?(path)
    { type: "file" }.to_json
  else
    { type: "directory" }.to_json
  end
end

post "/history/save_external_script" do
  conf         = create_conf
  cluster_name = conf.key?("clusters") ? (params["cluster"] || conf["clusters"].keys.first) : nil
  target_app   = conf["external_reload_app"] || "Slurm"
  cluster_param = cluster_name ? "?#{HEADER_CLUSTER_NAME}=#{URI.encode_www_form_component(cluster_name)}" : ""
  content_type :json
  { url: "#{request.script_name}/_generic/#{target_app}#{cluster_param}" }.to_json
end

get "/job_details" do
  content_type :json

  job_id = (params["jobId"] || "").strip
  return { "error" => "No job ID specified" }.to_json if job_id.empty?
  return { "error" => "Invalid job ID" }.to_json unless job_id.match?(/\A[\d_.\[\]+]+\z/) # '+' allows Slurm heterogeneous-job component IDs (e.g. 1234+0).

  conf         = create_conf
  cluster_name = conf.key?("clusters") ? (params["cluster"] || conf["clusters"].keys.first) : nil
  scheduler    = conf.key?("clusters") ? create_scheduler(conf)[cluster_name] : create_scheduler(conf)
  bin          = conf.key?("clusters") ? conf["bin"][cluster_name]          : conf["bin"]
  bin_overrides= conf.key?("clusters") ? conf["bin_overrides"][cluster_name]: conf["bin_overrides"]
  ssh_wrapper  = conf.key?("clusters") ? conf["ssh_wrapper"][cluster_name]  : conf["ssh_wrapper"]
  scheduler_env= conf.key?("clusters") ? conf["scheduler_env"][cluster_name]: conf["scheduler_env"]

  result = {
    "job_id"          => job_id,
    "source"          => "none",
    "data"            => {},
    "script_location" => nil,
    "script_name"     => nil,
    "script_content"  => nil
  }

  # Route to sacct first to determine if job is terminal; if not, use scontrol.
  terminal = [JOB_STATUS["completed"], JOB_STATUS["cancelled"], JOB_STATUS["failed"]]
  sacct_data, sacct_err, sacct_cmd = scheduler.sacct_job(job_id, bin, bin_overrides, ssh_wrapper, scheduler_env)
  oc_status = sacct_data && !sacct_data.empty? ? sacct_state_to_oc_status(sacct_data["State"].to_s, scheduler) : nil

  if sacct_data && !sacct_data.empty? && terminal.include?(oc_status)
    # Terminal job confirmed by sacct — use sacct data
    result["source"]  = "sacct"
    result["command"] = sacct_cmd
    result["data"]    = sacct_data
    workdir = sacct_data["WorkDir"]
    result["script_location"] = workdir unless workdir.to_s.strip.empty? || workdir == "None"
  else
    # Active or unknown — try scontrol first, then sacct
    scontrol_data, scontrol_err, scontrol_cmd = scheduler.scontrol_job(job_id, bin, bin_overrides, ssh_wrapper, scheduler_env)
    if scontrol_data && !scontrol_data.empty?
      result["source"]  = "scontrol"
      result["command"] = scontrol_cmd
      result["data"]    = scontrol_data
      cmd = scontrol_data["Command"]
      if cmd && cmd != "(null)" && !cmd.strip.empty?
        result["script_location"] = File.dirname(cmd)
        result["script_name"]     = File.basename(cmd)
      end
      result["script_location"] ||= scontrol_data["WorkDir"]
    elsif sacct_data && !sacct_data.empty?
      result["source"]  = "sacct"
      result["command"] = sacct_cmd
      result["data"]    = sacct_data
      workdir = sacct_data["WorkDir"]
      result["script_location"] = workdir unless workdir.to_s.strip.empty? || workdir == "None"
    else
      errors = { "scontrol" => scontrol_err, "sacct" => sacct_err }.compact
      result["errors"] = errors unless errors.empty?
    end
  end

  script_content, _err = scheduler.batch_script(job_id, bin, bin_overrides, ssh_wrapper, scheduler_env)
  result["script_content"] = script_content

  result.to_json
rescue Exception => e
  { "error" => e.message }.to_json
end

get "/history/job_efficiency" do
  content_type :json

  job_id = (params["job_id"] || "").strip
  return { "error" => "No job ID specified" }.to_json if job_id.empty?

  conf         = create_conf
  cluster_name = conf.key?("clusters") ? (params["cluster"] || conf["clusters"].keys.first) : nil
  scheduler    = conf.key?("clusters") ? create_scheduler(conf)[cluster_name] : create_scheduler(conf)
  bin          = conf.key?("clusters") ? conf["bin"][cluster_name]           : conf["bin"]
  bin_overrides= conf.key?("clusters") ? conf["bin_overrides"][cluster_name] : conf["bin_overrides"]
  ssh_wrapper  = conf.key?("clusters") ? conf["ssh_wrapper"][cluster_name]   : conf["ssh_wrapper"]
  scheduler_env= conf.key?("clusters") ? conf["scheduler_env"][cluster_name] : conf["scheduler_env"]
  gpu_memory   = conf.key?("clusters") ? conf["gpu_memory"][cluster_name]    : conf["gpu_memory"]

  unless scheduler.respond_to?(:efficiency)
    next({ "error" => "Efficiency not supported by this scheduler." }.to_json)
  end

  result, error = scheduler.efficiency(job_id, bin, bin_overrides, ssh_wrapper, scheduler_env, gpu_memory)
  if error
    { "error" => error }.to_json
  else
    (result || {}).to_json
  end
end

post "/history/cancel_one" do
  conf         = create_conf
  job_id       = params["jobId"].to_s.strip.gsub(/\[([^\]]+)\]/) { "[#{$1.gsub(/[:%]\d+/, '')}]" }
  content_type :json
  return JSON.generate({ ok: false, error: "No job ID" }) if job_id.empty?
  return JSON.generate({ ok: false, error: "Invalid job ID" }) unless job_id.match?(/\A[\d_.\[\]+\-]+\z/)

  cluster_name  = conf.key?("clusters") ? (params["cluster"] || conf["clusters"].keys.first) : nil
  scheduler     = conf.key?("clusters") ? create_scheduler(conf)[cluster_name] : create_scheduler(conf)
  bin           = conf.key?("clusters") ? conf["bin"][cluster_name]           : conf["bin"]
  bin_overrides = conf.key?("clusters") ? conf["bin_overrides"][cluster_name] : conf["bin_overrides"]
  ssh_wrapper   = conf.key?("clusters") ? conf["ssh_wrapper"][cluster_name]   : conf["ssh_wrapper"]
  scheduler_env = conf.key?("clusters") ? conf["scheduler_env"][cluster_name] : conf["scheduler_env"]

  error_msg = scheduler.cancel([job_id], bin, bin_overrides, ssh_wrapper, scheduler_env)
  if error_msg.nil?
    output_log("Cancel job", scheduler, cluster: cluster_name, job_ids: [job_id])
    JSON.generate({ ok: true })
  else
    JSON.generate({ ok: false, error: error_msg.to_s })
  end
rescue => e
  content_type :json
  JSON.generate({ ok: false, error: e.message })
end

get "/history/active_job_ids" do
  conf         = create_conf
  content_type :json
  cluster_name  = conf.key?("clusters") ? (params["cluster"] || conf["clusters"].keys.first) : nil
  scheduler     = conf.key?("clusters") ? create_scheduler(conf)[cluster_name] : create_scheduler(conf)
  bin           = conf.key?("clusters") ? conf["bin"][cluster_name]           : conf["bin"]
  bin_overrides = conf.key?("clusters") ? conf["bin_overrides"][cluster_name] : conf["bin_overrides"]
  ssh_wrapper   = conf.key?("clusters") ? conf["ssh_wrapper"][cluster_name]   : conf["ssh_wrapper"]
  scheduler_env = conf.key?("clusters") ? conf["scheduler_env"][cluster_name] : conf["scheduler_env"]

  deleted_db  = open_deleted_db(conf, cluster_name)
  deleted_ids = Set.new(deleted_db.execute("SELECT _job_id FROM deleted_jobs").map { |r| r["_job_id"] })

  from = (Date.today - 29).strftime("%Y-%m-%d")
  to   = Date.today.strftime("%Y-%m-%d")
  all_jobs, _err, _cmd = scheduler.sacct_all_jobs(from, to, bin, bin_overrides, ssh_wrapper, scheduler_env)

  active_statuses = [JOB_STATUS["queued"], JOB_STATUS["running"]]
  seen_ids = Set.new
  ids = (all_jobs || []).filter_map do |j|
    jid = j["JobID"].to_s.strip
    next unless valid_oc_job_id?(jid, scheduler)
    next if deleted_ids.include?(jid)
    seen_ids.add(jid)
    oc_status = sacct_state_to_oc_status(j["State"].to_s, scheduler)
    jid if active_statuses.include?(oc_status)
  end

  # Supplement sacct with squeue to catch PENDING jobs not yet in sacct
  squeue_jobs, _sq_err = scheduler.squeue_active_jobs(bin, bin_overrides, ssh_wrapper, scheduler_env)
  (squeue_jobs || []).each do |j|
    jid = j["JobID"].to_s.strip
    next unless valid_oc_job_id?(jid, scheduler)
    next if deleted_ids.include?(jid)
    next if seen_ids.include?(jid)
    oc_status = sacct_state_to_oc_status(j["State"].to_s, scheduler)
    ids << jid if active_statuses.include?(oc_status)
  end

  JSON.generate(ids)
rescue => e
  content_type :json
  JSON.generate([])
end

get "/nodes/data" do
  conf = create_conf
  if conf.key?("clusters")
    cluster_name    = params["cluster"] || conf["clusters"].keys.first
    scheduler_s     = create_scheduler(conf)[cluster_name]
    bin_s           = conf["bin"][cluster_name]
    bin_overrides_s = conf["bin_overrides"][cluster_name]
    ssh_wrapper_s   = conf["ssh_wrapper"][cluster_name]
    scheduler_env_s = conf["scheduler_env"][cluster_name]
  else
    scheduler_s     = create_scheduler(conf)
    bin_s           = conf["bin"]
    bin_overrides_s = conf["bin_overrides"]
    ssh_wrapper_s   = conf["ssh_wrapper"]
    scheduler_env_s = conf["scheduler_env"]
  end
  nodes, error, command = scheduler_s.sinfo_nodes(bin_s, bin_overrides_s, ssh_wrapper_s, scheduler_env_s)
  rows = (nodes || []).map do |cols|
    { node: cols[0], state: cols[1], cpus: cols[2], memory: cols[3], freemem: cols[4], gres: cols[5], gresused: cols[6] }
  end
  # The command a user could run themselves on the cluster — strip the
  # ssh wrapper prefix the web app uses to reach the login node.
  display_cmd = command.to_s
  display_cmd = display_cmd.sub(/\A#{Regexp.escape(ssh_wrapper_s.to_s)}\s*/, "") unless ssh_wrapper_s.to_s.empty?
  content_type :json
  { error: error, rows: rows, command: display_cmd, fetched_at: Time.now.strftime("%H:%M:%S") }.to_json
end

# Persist the drag-and-drop order of the My Custom Templates grid.
# Expects "order" = comma-separated template slugs in their new order;
# writes a numeric "position" into each template's YAML.
post "/templates/reorder" do
  conf = create_conf
  dir  = templates_dir(conf)
  content_type :json
  slugs = params["order"].to_s.split(",").map { |s| s.gsub(/[^a-zA-Z0-9_\-]/, '') }.reject(&:empty?)
  halt 400, { ok: false, error: "No order given." }.to_json if slugs.empty?

  slugs.each_with_index do |slug, idx|
    path = File.join(dir, "#{slug}.yml")
    next unless File.exist?(path)
    begin
      data = YAML.safe_load(File.read(path))
      data = {} unless data.is_a?(Hash)
      data["position"] = idx
      File.write(path, data.to_yaml)
    rescue
    end
  end
  { ok: true }.to_json
end

post "/templates/:slug/overwrite" do
  conf = create_conf
  slug = params["slug"].gsub(/[^a-zA-Z0-9_\-]/, '')
  path = File.join(conf["data_dir"], "templates", "#{slug}.yml")
  halt 404, "Template not found." unless File.exist?(path)

  begin
    existing = YAML.safe_load(File.read(path))
  rescue
    existing = {}
  end
  existing = {} unless existing.is_a?(Hash)

  skip   = %w[template_name template_description _tmpl_icon splat captures]
  values = params.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s unless skip.include?(k) }

  File.write(path, existing.merge({
    "app_path" => params[JOB_DIR_NAME].to_s.strip,
    "icon"     => params["_tmpl_icon"].to_s,
    "values"   => values
  }).to_yaml)

  redirect request.script_name.empty? ? "/" : request.script_name
end

post "/templates/:slug/rename" do
  conf = create_conf
  slug = params["slug"].gsub(/[^a-zA-Z0-9_\-]/, '')
  path = File.join(conf["data_dir"], "templates", "#{slug}.yml")
  halt 404, "Template not found." unless File.exist?(path)

  name = params["template_name"].to_s.strip
  halt 400, "Template name is required." if name.empty?

  begin
    data = YAML.safe_load(File.read(path))
  rescue
    data = {}
  end
  data = {} unless data.is_a?(Hash)

  File.write(path, data.merge({
    "name"        => name,
    "description" => params["template_description"].to_s.strip
  }).to_yaml)

  redirect request.script_name.empty? ? "/" : request.script_name
end

post "/templates" do
  conf = create_conf
  dir  = File.join(conf["data_dir"], "templates")
  FileUtils.mkdir_p(dir)

  name = params["template_name"].to_s.strip
  halt 400, "Template name is required." if name.empty?

  slug      = name.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
  slug      = "template" if slug.empty?
  base_slug = slug
  i = 1
  while File.exist?(File.join(dir, "#{slug}.yml"))
    slug = "#{base_slug}_#{i}"
    i += 1
  end

  skip   = %w[template_name template_description _tmpl_icon splat captures]
  values = params.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s unless skip.include?(k) }

  File.write(File.join(dir, "#{slug}.yml"), {
    "name"        => name,
    "description" => params["template_description"].to_s.strip,
    "app_path"    => params[JOB_DIR_NAME].to_s.strip,
    "icon"        => params["_tmpl_icon"].to_s,
    "values"      => values
  }.to_yaml)

  redirect request.script_name.empty? ? "/" : request.script_name
end

post "/templates/:slug/delete" do
  conf = create_conf
  slug = params["slug"].gsub(/[^a-zA-Z0-9_\-]/, '')
  path = File.join(conf["data_dir"], "templates", "#{slug}.yml")
  File.delete(path) if File.exist?(path)
  redirect request.script_name.empty? ? "/" : request.script_name
end

get "/*" do
  show_website
end

post "/*" do
  # Keep POST handlers on the local conf object. @conf is initialized in show_website.
  conf          = create_conf
  cluster_name  = if conf.key?("clusters")
                    params[request.path_info == "/history" ? "cluster" : HEADER_CLUSTER_NAME] || conf["clusters"].keys.first
                  else
                    nil
                  end
  scheduler     = conf.key?("clusters") ? create_scheduler(conf)[cluster_name] : create_scheduler(conf)
  ssh_wrapper   = conf.key?("clusters") ? conf["ssh_wrapper"][cluster_name] : conf["ssh_wrapper"]
  bin           = conf.key?("clusters") ? conf["bin"][cluster_name] : conf["bin"]
  bin_overrides = conf.key?("clusters") ? conf["bin_overrides"][cluster_name] : conf["bin_overrides"]
  scheduler_env    = conf.key?("clusters") ? conf["scheduler_env"][cluster_name] : conf["scheduler_env"]
  copy_environment = conf.key?("clusters") ? conf["copy_environment"][cluster_name] : conf["copy_environment"]
  history_db    = conf.key?("clusters") ? conf["history_db"][cluster_name] : conf["history_db"]
  data_dir      = conf["data_dir"]
  export_sge_root(conf, cluster_name)

  if request.path_info == "/history"
    job_ids   = params["JobIds"].to_s.split(",").reject(&:empty?)
    error_msg = nil

    case params["action"]
    when "CancelJob"
      error_msg = scheduler.cancel(job_ids.reverse, bin, bin_overrides, ssh_wrapper, scheduler_env)
      output_log("Cancel job", scheduler, cluster: cluster_name, job_ids: job_ids)
    when "DeleteInfo"
      if history_db
        db         = open_history_db(conf, conf.key?("clusters") ? cluster_name : nil)
        deleted_db = open_deleted_db(conf, conf.key?("clusters") ? cluster_name : nil, main_db: db)
        delete_all_jobs(db, deleted_db, job_ids)
        output_log("Delete job information", scheduler, cluster: cluster_name, job_ids: job_ids)
        redirect request.url
      end
    when "CancelAll"
      from = (Date.today - 29).strftime("%Y-%m-%d")
      to   = Date.today.strftime("%Y-%m-%d")
      all_sacct, _err2, _cmd2 = scheduler.sacct_all_jobs(from, to, bin, bin_overrides, ssh_wrapper, scheduler_env)
      active_statuses = [JOB_STATUS["queued"], JOB_STATUS["running"]]
      cancel_ids = (all_sacct || []).filter_map do |j|
        jid = j["JobID"].to_s.strip
        next unless valid_oc_job_id?(jid, scheduler)
        jid if active_statuses.include?(sacct_state_to_oc_status(j["State"].to_s, scheduler))
      end
      unless cancel_ids.empty?
        error_msg = scheduler.cancel(cancel_ids.reverse, bin, bin_overrides, ssh_wrapper, scheduler_env)
        output_log("Cancel all jobs", scheduler, cluster: cluster_name, job_ids: cancel_ids)
      end
    when "DeleteAll"
      if history_db
        db         = open_history_db(conf, conf.key?("clusters") ? cluster_name : nil)
        deleted_db = open_deleted_db(conf, conf.key?("clusters") ? cluster_name : nil, main_db: db)
        from = (Date.today - 29).strftime("%Y-%m-%d")
        to   = Date.today.strftime("%Y-%m-%d")
        all_sacct, _err2, _cmd2 = scheduler.sacct_all_jobs(from, to, bin, bin_overrides, ssh_wrapper, scheduler_env)
        active_statuses = [JOB_STATUS["queued"], JOB_STATUS["running"]]
        active_count = (all_sacct || []).count do |j|
          jid = j["JobID"].to_s.strip
          valid_oc_job_id?(jid, scheduler) && active_statuses.include?(sacct_state_to_oc_status(j["State"].to_s, scheduler))
        end
        if active_count > 0
          noun = active_count == 1 ? "job is" : "jobs are"
          msg  = "#{active_count} #{noun} still Running or Queued. Cancel them all first, then delete all history."
          sep  = request.query_string.empty? ? "?" : "&"
          redirect request.url + sep + "error_msg=" + URI.encode_www_form_component(msg)
        else
          sacct_ids = (all_sacct || []).filter_map do |j|
            jid = j["JobID"].to_s.strip
            valid_oc_job_id?(jid, scheduler) ? jid : nil
          end
          delete_all_jobs(db, deleted_db, sacct_ids)
          output_log("Delete all job history", scheduler, cluster: cluster_name)
          redirect request.url
        end
      end
    end

    return show_website(nil, error_msg)
  else # application form
    generic_apps_dir = conf["generic_apps_dir"] || "./generic_apps"
    app_path = if request.path_info.start_with?("/_generic/")
                 File.join(generic_apps_dir, request.path_info.sub(/\A\/_generic\//, ""))
               else
                 File.join(conf["apps_dir"], request.path_info)
               end
    manifest = create_manifest(app_path)

    script_location = params[HEADER_SCRIPT_LOCATION]
    script_name     = params[HEADER_SCRIPT_NAME]
    job_name        = params[HEADER_JOB_NAME]
    error_msg =
      if script_location.nil?
        "#{HEADER_SCRIPT_LOCATION} is not defined in #{app_path}/form.yml[.erb]."
      elsif script_name.nil?
        "#{HEADER_SCRIPT_NAME} is not defined in #{app_path}/form.yml[.erb]."
      elsif job_name.nil?
        "#{HEADER_JOB_NAME} is not defined in #{app_path}/form.yml[.erb]."
      else
        nil
      end
    return show_website(nil, error_msg, params) if error_msg

    begin
      form = read_yaml(File.join(app_path, "form.yml"))
    rescue Exception => e
      @error_msg = e.message
      return erb :error
    end
    form["form"] ||= {} if form.is_a?(Hash) # Allow a header-only app with an empty form body.

    script_path    = File.join(script_location, script_name)
    script_dir     = File.dirname(script_path)
    script_content = params[OC_SCRIPT_CONTENT].gsub("\r\n", "\n") # Since HTML textarea for OC_SCRIPT_CONTENT is required, params[OC_SCRIPT_CONTENT] must not be nil.
    form_action    = get_form_action(form)
    job_id         = nil
    submit_options = nil

    # Run commands in the check section
    check_content = form["check"]
    if !check_content.nil?
      params.each do |key, value|
        next if SKIP_KEYS.include?(key)
        if DEFINED_KEYS.key?(key)
          set_check_value(DEFINED_KEYS[key], value)
          next
        end

        base_key = num = nil
        if key =~ /^(.*)_(\d+)$/
          base_key, num = $1, $2
        end
        widget = form["form"][key]&.dig("widget") || (base_key && form["form"][base_key]&.dig("widget"))
        next unless widget

        if ["number"].include?(widget)
          set_check_value(key, value.to_f == value.to_i ? value.to_i : value.to_f)
        elsif ["text", "email", "path", "module_load", "dependent_module_select"].include?(widget)
          # These submit their value directly rather than through an options list.
          set_check_value(key, value)
        elsif ["select", "radio"].include?(widget)
          option = form["form"][key]["options"].find { |x| x[0].to_s == value }
          if option.size == 1
            set_check_value(key, option[0])
          else
            set_check_value(key, option[1])
            if option[1].is_a?(Array)
              option[1].each_with_index { |v, i| set_check_value("#{key}_#{i+1}", v) }
            end
          end
        elsif ["multi_select", "checkbox"].include?(widget)
          separator = form["form"][base_key]["separator"]
          option = form["form"][base_key]["options"].find { |x| x[0].to_s == value }
          if option.size == 1
            set_check_value(base_key, option[0], separator)
          else
            set_check_value(base_key, option[1], separator)
            if option[1].is_a?(Array)
              option[1].each_with_index { |v, i| set_check_value("#{base_key}_#{i+1}", v, separator) }
            end
          end
        end
      end

      begin
        output_log("Run commands in the check section", scheduler, command: check_content)
        Dir.chdir(script_dir) do
          eval(check_content)
        end
      rescue Exception => e
        return show_website(nil, e.message, params)
      end
    end

    # Save a job script
    FileUtils.mkdir_p(script_location)
    File.open(script_path, "w") { |file| file.write(script_content) }

    # Run commands in the submit section
    submit_content = params[SUBMIT_CONTENT].nil? ? nil : params[SUBMIT_CONTENT].gsub("\r\n", "\n")

    if !submit_content.nil?
      submit_with_echo = <<~BASH
        #{submit_content}
        if [ -n "$OC_SUBMIT_OPTIONS" ]; then
          echo "$OC_SUBMIT_OPTIONS"
        else
          echo "__UNDEFINED__"
        fi
        BASH

      output_log("Run commands in the submit section", scheduler, command: submit_with_echo)
      # chdir: keeps the subprocess in script_dir without mutating the whole
      # process's working directory (which would corrupt relative-path lookups,
      # e.g. icon serving, in any concurrent request).
      stdout, stderr, status = Open3.capture3("bash", "-c", submit_with_echo, chdir: script_dir)
      unless status.success?
        return show_website(nil, stderr, params)
      end

      last_line = stdout.lines.last&.strip
      submit_options = (last_line == "__UNDEFINED__") ? nil : last_line
    end

    # Submit a job script
    if form_action == "save" || form_action == "confirm-save"
      output_log("Save job file", scheduler, cluster: cluster_name, app_dir: manifest["dirname"], app_name: manifest["name"], category: manifest["category"], script_path: script_path)
      return show_website(nil, nil, params, script_path)
    end

    # Optionally make sure the user has an SSH key before we submit over SSH.
    # If none exists we generate (and authorize) one so submission does not fail
    # on a missing/unauthorized key. A failure here is logged but not fatal — the
    # submit below still runs and surfaces any real SSH error to the user.
    if conf.fetch("ensure_ssh_key", false)
      ssh_key_result = ensure_user_ssh_key(conf.fetch("ssh_key_type", "ed25519"), conf.fetch("ssh_key_name", "opencomposer"))
      output_log("Ensure SSH key", scheduler, cluster: cluster_name, result: ssh_key_result) unless ssh_key_result == :exists
    end

    Dir.chdir(script_dir) do
      job_id, error_msg = scheduler.submit(script_path, escape_html(job_name.strip), submit_options, bin, bin_overrides, ssh_wrapper, scheduler_env, copy_environment)
      params[JOB_SUBMISSION_TIME] = Time.now.iso8601
    end

    # Save a job history (only valid job IDs per the active scheduler's format)
    FileUtils.mkdir_p(data_dir)
    db = open_history_db(conf, conf.key?("clusters") ? cluster_name : nil)
    store_script = conf.fetch("history_store_script", true)
    db.transaction do
      Array(job_id).each do |id|
        next unless valid_oc_job_id?(id.to_s, scheduler)
        upsert_job(db, {
          "_job_id"          => id.to_s,
          "_app_name"        => params[JOB_APP_NAME],
          "_app_dir_name"    => params[JOB_DIR_NAME],
          "_script_location" => params[HEADER_SCRIPT_LOCATION],
          "_script_name"     => params[HEADER_SCRIPT_NAME],
          "_submission_time" => normalize_time_for_db(params[JOB_SUBMISSION_TIME]),
          "_script_content"  => store_script ? script_content : nil
        })
      end
    end

    # Output log
    output_log("Submit job", scheduler, cluster: cluster_name, job_ids: Array(job_id), app_dir: manifest["dirname"], app_name: manifest["name"], category: manifest["category"])

    return show_website(job_id, error_msg, params, script_path)
  end
end
