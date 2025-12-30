require "sinatra"
require "yaml"
require "erb"
require "pstore"
require "fileutils"
require "./lib/index"
require "./lib/form"
require "./lib/history"
require "./lib/scheduler"

set :environment, :production
#set :environment, :development
set :erb, trim: "-"

# Internal Constants
VERSION                = "1.9.0-dev"
SCHEDULERS_DIR_PATH    = "./lib/schedulers"
HISTORY_ROWS           = 10
JOB_STATUS             = { "queued" => "QUEUED", "running" => "RUNNING", "completed" => "COMPLETED", "failed" => "FAILED" }
JOB_ID                 = "id"
JOB_APP_NAME           = "appName"
JOB_DIR_NAME           = "appPath"
JOB_STATUS_ID          = "status"
HEADER_SCRIPT_LOCATION = "_script_location"
HEADER_SCRIPT_NAME     = "_script_1"
HEADER_JOB_NAME        = "_script_2"
HEADER_CLUSTER_NAME    = "_cluster_name"
OC_SCRIPT_CONTENT      = "_script_content"
SCRIPT_CONTENT         = OC_SCRIPT_CONTENT  # Compatibility with previous versions
FORM_LAYOUT            = "_form_layout"
SUBMIT_BUTTON          = "_submitButton"
SUBMIT_CONFIRM         = "_submitConfirm"
SUBMIT_CONTENT         = "_submit_content"
SUBMIT_FORM            = "_submit_form"
JOB_NAME               = "Job Name"
JOB_PARTITION          = "Partition"
JOB_SUBMISSION_TIME    = "Submission Time"
JOB_KEYS               = "job_keys"
SKIP_KEYS = ['splat', OC_SCRIPT_CONTENT]
DEFINED_KEYS = {
  JOB_APP_NAME           => 'OC_APP_NAME',
  JOB_DIR_NAME           => 'OC_DIR_NAME',
  HEADER_SCRIPT_LOCATION => 'OC_SCRIPT_LOCATION',
  HEADER_SCRIPT_NAME     => 'OC_SCRIPT_NAME',
  HEADER_JOB_NAME        => 'OC_JOB_NAME',
  HEADER_CLUSTER_NAME    => 'OC_CLUSTER_NAME'
}.freeze
HISTORY_KEY_MAP = {
  "OC_HISTORY_JOB_NAME"        => JOB_NAME,
  "OC_HISTORY_PARTITION"       => JOB_PARTITION,
  "OC_HISTORY_SUBMISSION_TIME" => JOB_SUBMISSION_TIME
}.freeze
CLUSTERS_KEYS = ["scheduler", "login_node", "ssh_wrapper", "bin", "bin_overrides", "sge_root"].freeze

# Structure of manifest
Manifest = Struct.new(:dirname, :name, :category, :description, :icon, :related_apps)

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

# Create a configuration object.
# Defaults are applied for any missing values.
def create_conf
  begin
    conf = read_yaml("./conf.yml")
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
  conf["data_dir"]          ||= ENV["HOME"] + "/composer"
  conf["history"]           ||= HISTORY_KEY_MAP.keys
  conf["footer"]            ||= "&nbsp;"
  conf["thumbnail_width"]   ||= "100"
  conf["navbar_color"]      ||= "#3D3B40"
  conf["dropdown_color"]    ||= conf["navbar_color"]
  conf["footer_color"]      ||= conf["navbar_color"]
  conf["category_color"]    ||= "#5522BB"
  conf["description_color"] ||= conf["category_color"]
  conf["form_color"]        ||= "#BFCFE7"

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
      
      conf["history_db"][name] = File.join(conf["data_dir"], "#{name}.db")
    end
  else
    conf["history_db"] = File.join(conf["data_dir"], "#{conf["scheduler"]}.db")
  end

  # Create data directory
  FileUtils.mkdir_p(conf["data_dir"])

  return conf
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
  return Manifest.new(dirname, dirname, nil, nil, nil, nil) if manifest.nil?

  manifest["name"] ||= dirname
  return Manifest.new(dirname, manifest["name"], manifest["category"], manifest["description"], manifest["icon"], manifest["related_apps"])
end

# Create an array of manifest objects for all applications.
def create_all_manifests(apps_dir)
  all_manifests = Dir.children(apps_dir).each_with_object([]) do |dir, manifests|
    next if dir.start_with?(".") # Skip hidden files and directories

    app_path = File.join(apps_dir, dir)
    if ["form.yml", "form.yml.erb"].any? { |file| File.exist?(File.join(app_path, file)) }
      manifests << create_manifest(app_path)
    end
  end

  return all_manifests.compact
end

# Replace with cached value.
def replace_with_cache(form, cache)
  form.each do |key, value|
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

# Create a website of Home, Application, and History.
def show_website(job_id = nil, error_msg = nil, error_params = nil, script_path = nil)
  @conf          = create_conf
  @apps_dir      = @conf["apps_dir"]
  @version       = VERSION
  @my_ood_url    = request.base_url
  @script_name   = request.script_name
  @dir_name      = request.path_info.sub(/^\//, '')
  @cluster_name  = if @conf.key?("clusters")
                     escape_html(params[@dir_name == "history" ? "cluster" : HEADER_CLUSTER_NAME] || @conf["clusters"].keys.first)
                   else
                     nil
                   end
  @login_node    = if @conf.key?("clusters")
                     @conf["login_node"][@cluster_name]
                   else
                     @conf["login_node"]
                   end

  @ood_logo_path = URI.join(@my_ood_url, @script_name + "/", "ood.png")
  @current_path  = File.join(@script_name, @dir_name)
  @manifests     = create_all_manifests(@apps_dir).sort_by { |m| [(m.category || "").downcase, m.name.downcase] }
  @manifests_w_category, @manifests_wo_category = @manifests.partition(&:category)

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
    @error_msg     = update_status(@conf, @scheduler, @bin, @bin_overrides, @ssh_wrapper, @cluster_name)
    return erb :error if @error_msg != nil

    @status       = escape_html(params["status"] || "all")
    @filter       = escape_html(params["filter"])
    all_jobs      = get_all_jobs(@conf, @cluster_name, @status, @filter)
    @jobs_size    = all_jobs.size
    @rows         = [[(params["rows"] || HISTORY_ROWS).to_i, 1].max, @jobs_size].min
    @page_size    = (@rows == 0) ? 1 : ((@jobs_size - 1) / @rows) + 1
    @current_page = (params["p"] || 1).to_i
    @start_index  = @jobs_size == 0 ? 0 : (@current_page - 1) * @rows
    @end_index    = @jobs_size == 0 ? 0 : [@current_page * @rows, @jobs_size].min - 1
    @jobs         = @start_index >= @jobs_size ? [] : all_jobs[@start_index..@end_index]
    @error_msg    = error_msg

    @history_hash = @conf["history"].each_with_object({}) do |(key, opt), h|
      key = key.to_s
      label = opt && opt["label"] || HISTORY_KEY_MAP.fetch(key, key)
      h[key] = label
    end

    return erb :history
  else # application form
    @table_index = 1
    @manifest = @manifests.find { |m| "#{m.dirname}" == @dir_name }
    unless @manifest.nil?
      begin
        @name = @manifest["name"]
        @OC_APP_NAME = @name
        @OC_DIR_NAME = @manifest["dirname"]
        @body = read_yaml(File.join(@apps_dir, @dir_name, "form.yml"))
        @header = if @body.key?("header")
                    @body["header"]
                  else
                    read_yaml("./lib/header.yml")["header"]
                  end
      rescue Exception => e
        @error_msg = e.message
        return erb :error
      end
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
      if params["jobId"] || job_id
        history_db = if @conf.key?("clusters")
                       cluster_name = params[params["jobId"] ? "cluster" : HEADER_CLUSTER_NAME] || @conf["clusters"].keys.first
                       @conf["history_db"][cluster_name]
                     else
                       @conf["history_db"]
                     end

        if history_db.nil? || !File.exist?(history_db)
          @error_msg = history_db.nil? ? "#{cluster_name} is not invalid." : "#{history_db} is not found."
          return erb :error
        end

        cache = nil
        id = nil
        db = PStore.new(history_db)
        db.transaction(true) do
          id = if params["jobId"]
                 params["jobId"]
               else
                 job_id.is_a?(Array) ? job_id[0].to_s : job_id.to_s
               end
          cache = db[id]
        end

        if cache.nil?
          @error_msg = "Specified Job ID (#{id}) is not found."
          return erb :error
        end

        replace_with_cache(@header, cache)
        replace_with_cache(@body["form"], cache)
        @script_content = escape_html(cache[OC_SCRIPT_CONTENT])
        @submit_content = escape_html(cache[SUBMIT_CONTENT])
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

      @job_id    = job_id.is_a?(Array) ? job_id.join(", ") : job_id
      @error_msg = error_msg&.force_encoding('UTF-8')
      @script_path = script_path
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

# Send an application icon.
get "/:apps_dir/:folder/:icon" do
  icon_path = File.join(create_conf["apps_dir"], params[:folder], params[:icon])
  send_file(icon_path) if File.exist?(icon_path)
end

# Return a list of files and/or directories in JSON format.
get "/_files" do
  path = params[:path] || "."
  path = File.dirname(path) if File.file?(path)

  content_type :json
  if File.exist?(path)
    entries = Dir.children(path).map do |entry|
      full_path = File.join(path, entry)
      { name: entry, path: full_path, type: File.directory?(full_path) ? "directory" : "file" }
    end.sort_by { |entry| entry[:name].downcase }
  else
    # When a non-existent directory is specified using the set-value statement of the dynamic form widget.
    entries = ""
  end
  
  { files: entries }.to_json
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
    
get "/*" do
  show_website
end

post "/*" do
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
  history_db    = conf.key?("clusters") ? conf["history_db"][cluster_name] : conf["history_db"]
  data_dir      = conf["data_dir"]
  ENV['SGE_ROOT'] ||= conf.key?("clusters") ? conf["sge_root"][cluster_name] : conf["sge_root"]

  if request.path_info == "/history"
    job_ids   = params["JobIds"].split(",")
    error_msg = nil

    case params["action"]
    when "CancelJob"
      error_msg = scheduler.cancel(job_ids, bin, bin_overrides, ssh_wrapper)
      output_log("Cancel job", scheduler, cluster: cluster_name, job_ids: job_ids)
    when "DeleteInfo"
      if File.exist?(history_db)
        db = PStore.new(history_db)
        db.transaction do
          job_ids.each do |job_id|
            db.delete(job_id)
          end
        end
        output_log("Delete job information", scheduler, cluster: cluster_name, job_ids: job_ids)
      end
    end

    return show_website(nil, error_msg)
  else # application form
    app_path = File.join(conf["apps_dir"], request.path_info)
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
        elsif ["text", "email", "path"].include?(widget)
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
      stdout, stderr, status = nil
      Dir.chdir(script_dir) do
        stdout, stderr, status = Open3.capture3("bash", "-c", submit_with_echo)
      end
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
    
    Dir.chdir(script_dir) do
      job_id, error_msg = scheduler.submit(script_path, escape_html(job_name.strip), submit_options, bin, bin_overrides, ssh_wrapper)
      params[JOB_SUBMISSION_TIME] = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    end

    # Save a job history
    FileUtils.mkdir_p(data_dir)
    db = PStore.new(history_db)
    db.transaction do
      Array(job_id).each do |id|
        db[id] = params
      end
    end

    # Output log
    output_log("Submit job", scheduler, cluster: cluster_name, job_ids: Array(job_id), app_dir: manifest["dirname"], app_name: manifest["name"], category: manifest["category"])

    return show_website(job_id, error_msg, params)
  end
end
