

helpers do
  # Generate HTML for icons linking to related applications.
  def output_related_apps_icon(job_app_path, apps)
    return [] if apps.nil?

    apps.map do |name, conf|
      href = "#{@my_ood_url}/pun/sys/dashboard/apps/show/#{name}"
      icon = conf&.dig('icon')
      if icon.nil?
        icon_path = "#{@my_ood_url}/pun/sys/dashboard/apps/icon/#{name}/sys/sys"
        icon_html = "<img width=20 title=\"#{name}\" alt=\"#{name}\" src=\"#{icon_path}\">"
      else
        is_bi_or_fa_icon, icon_path = get_icon_path(job_app_path, icon)

        icon_html = if is_bi_or_fa_icon
                      "<i class=\"#{icon} fs-5\"></i>"
                    else
                      "<img width=20 title=\"#{name}\" alt=\"#{name}\" src=\"#{icon_path}\">"
                    end
      end

      "<a style=\"color: black; text-decoration: none;\" target=\"_blank\" href=\"#{href}\">\n  #{icon_html}\n</a>\n"
    end
  end

  # Output a modal for a specific action (e.g., CancelJob or DeleteInfo).
  def output_action_modal(action)
    id = "_history#{action}"
    form_action = history_path_with_query

    abort_buttons = action == "CancelJob" ? \
      "\n          <button type=\"button\" id=\"#{id}AbortBtn\" class=\"btn btn-warning d-none\">Abort</button>" \
      "\n          <button type=\"button\" id=\"#{id}CloseBtn\" class=\"btn btn-secondary d-none\" onclick=\"window.location.reload()\">Close</button>" \
      : ""

    <<~HTML
    <div class="modal" id="#{id}" aria-hidden="true" tabindex="-1">
      <div class="modal-dialog modal-dialog-scrollable">
        <div class="modal-content">
          <div class="modal-body" id="#{id}Body">
            (Something wrong)
          </div>
          <div class="modal-footer" id="#{id}Footer">
            <form action="#{form_action}" method="post" id="#{id}Form">
              <input type="hidden" name="action" value="#{action}">
              <input type="hidden" name="JobIds" id="#{id}Input">
              <button type="button" class="btn btn-secondary" data-bs-dismiss="modal" tabindex="-1">Cancel</button>
              <button type="submit" class="btn btn-primary" tabindex="-1">OK</button>
            </form>#{abort_buttons}
          </div>
        </div>
      </div>
    </div>
    HTML
  end

  # Output a badge for an action button (e.g., CancelJob or DeleteInfo) with a modal trigger.
  def output_action_badge(action)
    return if action != "CancelJob" && action != "DeleteInfo"

    <<~HTML
    <button id="_history#{action}Badge" data-bs-toggle="modal" data-bs-target="#_history#{action}" class="btn btn-sm disabled" style="background-color:#{@conf['history_action_color']};border-color:#{@conf['history_action_color']};color:#fff;" disabled>
      #{(action == "CancelJob") ? "Cancel Job" : "Delete Info"}
      <span id="_history#{action}Count" class="badge bg-secondary">0</span>
    </button>
    HTML
  end

  # Output compact ascending/descending sort controls for a History table column.
  def output_history_sort_controls(sort_key)
    asc_class = ["history-sort-link", (@sort == sort_key && @order == "asc" ? "history-sort-active" : nil)].compact.join(" ")
    desc_class = ["history-sort-link", (@sort == sort_key && @order == "desc" ? "history-sort-active" : nil)].compact.join(" ")

    <<~HTML
    <span class="history-sort-controls">
      <a
        href="#{history_path_with_query(sort: sort_key, order: 'asc', p: 1)}"
        class="#{asc_class}"
        aria-label="Sort #{sort_key} ascending"
      ><span class="history-sort-icon">&#9650;</span></a>
      <a
        href="#{history_path_with_query(sort: sort_key, order: 'desc', p: 1)}"
        class="#{desc_class}"
        aria-label="Sort #{sort_key} descending"
      ><span class="history-sort-icon">&#9660;</span></a>
    </span>
    HTML
  end

  # Output a modal for displaying live job details fetched from scontrol/sacct.
  # Content is lazy-loaded via AJAX when the modal is opened.
  def output_job_id_modal(job, filter)
    modal_id     = "_historyJobId#{job[JOB_ID]}"
    job_id_esc   = escape_html(job[JOB_ID].to_s)
    status_esc   = escape_html(job[JOB_STATUS_ID].to_s)
    cluster_attr = @cluster_name ? " data-cluster=\"#{escape_html(@cluster_name)}\"" : ""

    terminal_statuses = [JOB_STATUS["completed"], JOB_STATUS["cancelled"], JOB_STATUS["failed"]]
    show_efficiency   = terminal_statuses.include?(job[JOB_STATUS_ID]) && @conf.fetch("history_efficiency", true)

    eff_section = show_efficiency ? <<~EFF : ""
      <div id="#{modal_id}EffRow" class="px-3 pb-3">
        <div class="text-center py-2 text-muted small">Loading efficiency&#8230;</div>
      </div>
    EFF

    <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1" data-job-status="#{status_esc}">
      <div class="modal-dialog modal-dialog-scrollable modal-lg">
        <div class="modal-content" style="resize: horizontal; padding-right: 16px;">
          <div class="modal-header">
            <h5>Job Details</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body" data-job-id="#{job_id_esc}"#{cluster_attr}>
            <div class="text-center py-3">
              <div class="spinner-border text-primary" role="status">
                <span class="visually-hidden">Loading...</span>
              </div>
            </div>
          </div>
          #{eff_section}
        </div>
      </div>
    </div>
    HTML
  end

  # Output a modal displaying a job script and a link to load parameters.
  # If _script_content is blank, the script is lazy-loaded via sacct -B on modal open.
  def output_job_script_modal(job, filter)
    modal_id    = "_historyJobScript#{job[JOB_ID]}"
    job_link    = "#{File.join(@script_name.to_s, job[JOB_DIR_NAME].to_s)}?jobId=#{URI.encode_www_form_component(job[JOB_ID].to_s)}"
    job_link   += "&cluster=#{@cluster_name}" if @cluster_name
    has_content = !job[OC_SCRIPT_CONTENT].to_s.strip.empty?

    if has_content
      body_html = <<~HTML
      <div class="modal-body">
        #{output_text(job[OC_SCRIPT_CONTENT], filter)}
      </div>
      HTML
    else
      job_id_esc   = escape_html(job[JOB_ID].to_s)
      cluster_attr = @cluster_name ? " data-cluster=\"#{escape_html(@cluster_name)}\"" : ""
      body_html = <<~HTML
      <div class="modal-body" data-script-job-id="#{job_id_esc}"#{cluster_attr}>
        <div class="text-center py-3">
          <div class="spinner-border text-primary" role="status">
            <span class="visually-hidden">Loading...</span>
          </div>
        </div>
      </div>
      HTML
    end

    <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1">
      <div class="modal-dialog modal-dialog-scrollable modal-lg">
        <div class="modal-content" style="resize: horizontal; padding-right: 16px;">
          <div class="modal-header">
            <h5>Job Script</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          #{body_html}
          <div class="modal-footer">
            <a href="#{job_link}" class="btn btn-primary text-white text-decoration-none">Load script</a>
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal" tabindex="-1">Close</button>
          </div>
        </div>
      </div>
    </div>
    HTML
  end

  # Output a script modal with lazy-load for jobs without an OC app directory.
  def output_job_slurm_script_modal(job)
    modal_id     = "_historyJobScript#{job[JOB_ID]}"
    job_id_esc   = escape_html(job[JOB_ID].to_s)
    cluster_attr = @cluster_name ? " data-cluster=\"#{escape_html(@cluster_name)}\"" : ""

    <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1">
      <div class="modal-dialog modal-dialog-scrollable modal-lg">
        <div class="modal-content" style="resize: horizontal; padding-right: 16px;">
          <div class="modal-header">
            <h5>Job Script</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body" data-script-job-id="#{job_id_esc}"#{cluster_attr}>
            <div class="text-center py-3">
              <div class="spinner-border text-primary" role="status">
                <span class="visually-hidden">Loading...</span>
              </div>
            </div>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-primary" onclick="ocHistory.loadExtScript(this)">Load script</button>
            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal" tabindex="-1">Close</button>
          </div>
        </div>
      </div>
    </div>
    HTML
  end

  # Output a pagination link for history navigation.
  def output_link(is_active, i, rows = 1)
    if is_active
      "<li class=\"page-item active\"><a href=\"#\" class=\"page-link\">#{i}</a></li>\n"
    elsif i == "..."
      "<li class=\"page-item\"><a href=\"#\" class=\"page-link\">...</a></li>\n"
    else
      link = history_path_with_query(p: i, rows: rows)
      "<li class=\"page-item\"><a href=\"#{link}\" class=\"page-link\">#{i}</a></li>\n"
    end
  end

  # Output a pagination component for navigating through pages of history records.
  def output_pagination(current_page, page_size, rows)
    html = "<nav class=\"mt-1\">\n"
    html += "  <ul class=\"pagination justify-content-center\">\n"

    if current_page == 1
      html += "    <li class=\"page-item disabled\"><a href=\"#\" class=\"page-link\">&laquo;</a></li>\n"
    else
      previous_link = history_path_with_query(p: current_page - 1, rows: rows)
      html += "    <li class=\"page-item\"><a href=\"#{previous_link}\" class=\"page-link\">&laquo;</a></li>\n"
    end

    if page_size <= 7
      (1..page_size).each do |i|
        html += output_link(current_page == i, i, rows)
      end
    else
      if current_page <= 4
        (1..5).each { |i| html += output_link(current_page == i, i, rows) }
        html += output_link(false, "...")
        html += output_link(false, page_size, rows)
      elsif current_page >= page_size - 3
        html += output_link(false, 1, rows)
        html += output_link(false, "...")
        ((page_size - 4)..page_size).each { |i| html += output_link(current_page == i, i, rows) }
      else
        html += output_link(false, 1, rows)
        html += output_link(false, "...")
        html += output_link(false, current_page - 1, rows)
        html += output_link(true, current_page, rows)
        html += output_link(false, current_page + 1, rows)
        html += output_link(false, "...")
        html += output_link(false, page_size, rows)
      end
    end

    if current_page == page_size
      html += "   <li class=\"page-item disabled\"><a href=\"#\" class=\"page-link\">&raquo;</a></li>\n"
    else
      next_link = history_path_with_query(p: current_page + 1, rows: rows)
      html += "   <li class=\"page-item\"><a href=\"#{next_link}\" class=\"page-link\">&raquo;</a></li>\n"
    end

    html += "  </ul>\n"
    html += "</nav>\n"
  end

  def history_valid_statuses
    %w[running queued completed cancelled failed unknown]
  end

  def parse_history_statuses(raw_statuses)
    return history_valid_statuses.dup if raw_statuses.nil?
    return [] if raw_statuses == "nothing"

    raw_statuses.to_s.split(/\s+/).map(&:strip).reject(&:empty?).select do |status|
      history_valid_statuses.include?(status)
    end
  end

  def serialize_history_statuses(statuses)
    selected_statuses = Array(statuses).map(&:to_s).select { |status| history_valid_statuses.include?(status) }
    return "nothing" if selected_statuses.empty?
    return nil if selected_statuses.sort == history_valid_statuses.sort

    selected_statuses.join(" ")
  end

  def history_path_with_query(overrides = {})
    values = {
      "statuses"      => @statuses,
      "filter"        => @filter,
      "filter_column" => @filter_column,
      "sort"          => @sort,
      "order"         => @order,
      "date_range"    => @date_range,
      "filter_mode"   => @filter_mode,
      "date_from"     => @date_from,
      "date_to"       => @date_to,
      "detail_open"   => @detail_open,
      "rows"          => @rows,
      "p"             => @current_page,
      "cluster"       => @cluster_name,
    }

    overrides.each { |key, value| values[key.to_s] = value }

    query_params = []
    serialized_statuses = serialize_history_statuses(values["statuses"])
    query_params << ["statuses", serialized_statuses] if serialized_statuses
    query_params << ["filter", values["filter"]] if values["filter"] && !values["filter"].empty?
    query_params << ["filter_column", values["filter_column"]] if values["filter_column"] && values["filter_column"] != "all"
    query_params << ["sort", values["sort"]] if values["sort"] && !values["sort"].empty?
    query_params << ["order", values["order"]] if values["order"] && !values["order"].empty?
    query_params << ["date_range", values["date_range"]] if values["date_range"] && values["date_range"] != "all"
    query_params << ["filter_mode", values["filter_mode"]] if values["filter_mode"] && values["filter_mode"] != "and"
    if values["date_range"] == "custom"
      query_params << ["date_from", values["date_from"]] if values["date_from"] && !values["date_from"].empty?
      query_params << ["date_to", values["date_to"]] if values["date_to"] && !values["date_to"].empty?
    end
    query_params << ["detail_open", "true"] if values["detail_open"] == "true"
    query_params << ["rows", values["rows"]] if values["rows"] && values["rows"].to_i != HISTORY_ROWS
    query_params << ["p", values["p"]] if values["p"] && values["p"].to_i != 1
    query_params << ["cluster", values["cluster"]] if values["cluster"]
    query_params.empty? ? "./history" : "./history?#{URI.encode_www_form(query_params)}"
  end

  def history_filter_terms(filter_text)
    filter_text.to_s.split(/\s+/).reject(&:empty?)
  end

  def parse_history_sort(raw_sort, conf)
    sort = raw_sort.to_s
    return JOB_ID if sort.empty?

    valid_columns = history_sort_column_items(conf).map(&:first)
    valid_columns.include?(sort) ? sort : JOB_ID
  end

  def parse_history_order(raw_order)
    order = raw_order.to_s
    return "desc" if order.empty?

    %w[asc desc].include?(order) ? order : "desc"
  end

  def history_date_range_items
    [
      ["all",      "(ALL)"],
      ["today",    "Today"],
      ["yesterday","Yesterday and Today"],
      ["last7",    "Last 7 days"],
      ["last30",   "Last 30 days"],
      ["custom",   "Custom"]
    ]
  end

  def parse_history_date_range(raw_date_range, raw_date_from, raw_date_to)
    date_range = raw_date_range.to_s
    date_range = "custom" if date_range.empty? && (!raw_date_from.to_s.empty? || !raw_date_to.to_s.empty?)
    date_range = "all" if date_range.empty?
    valid_ranges = history_date_range_items.map(&:first)
    date_range = "all" unless valid_ranges.include?(date_range)

    today = Date.today
    case date_range
    when "today"
      [date_range, today.strftime("%Y-%m-%d"), today.strftime("%Y-%m-%d")]
    when "yesterday"
      [date_range, (today - 1).strftime("%Y-%m-%d"), today.strftime("%Y-%m-%d")]
    when "last7"
      [date_range, (today - 6).strftime("%Y-%m-%d"), today.strftime("%Y-%m-%d")]
    when "last30"
      [date_range, (today - 29).strftime("%Y-%m-%d"), today.strftime("%Y-%m-%d")]
    when "custom"
      [date_range, raw_date_from.to_s, raw_date_to.to_s]
    else
      [date_range, "", ""]
    end
  end

  # Return a natural sort key for scheduler-specific job IDs.
  def history_job_id_sort_key(job_id)
    value = job_id.to_s
    case value
    when /\A(\d+)\z/            then [$1.to_i, -1, value]
    when /\A(\d+)[_.](\d+)\z/   then [$1.to_i, $2.to_i, value]
    when /\A(\d+)\[(\d+)\]\z/   then [$1.to_i, $2.to_i, value]
    when /\A(\d+)_\[(\d+)/      then [$1.to_i, $2.to_i, value]
    else                             [Float::INFINITY, Float::INFINITY, value]
    end
  end

  # Filter a list of job hashes by status.
  def filter_history_jobs_by_status(jobs, statuses)
    selected_statuses = Array(statuses).map(&:to_s).filter_map { |s| JOB_STATUS[s] }
    return [] if selected_statuses.empty?

    active_vals    = [JOB_STATUS["queued"], JOB_STATUS["running"]]
    include_active = selected_statuses.any? { |s| active_vals.include?(s) }
    terminal_vals  = selected_statuses.reject { |s| active_vals.include?(s) }

    jobs.select do |job|
      oc_status = job[JOB_STATUS_ID]
      if include_active && (oc_status.nil? || active_vals.include?(oc_status))
        true
      elsif terminal_vals.include?(oc_status)
        true
      else
        false
      end
    end
  end

  # Filter a list of job hashes by submission date range.
  def filter_history_jobs_by_date(jobs, date_from, date_to)
    return jobs if date_from.to_s.empty? && date_to.to_s.empty?

    jobs.select do |job|
      submit = job[JOB_SUBMISSION_TIME].to_s
      next false if submit.empty?

      submit_date = submit[0, 10] # "YYYY-MM-DD" prefix
      after  = date_from.to_s.empty? || submit_date >= date_from.to_s
      before = date_to.to_s.empty?   || submit_date <= date_to.to_s
      after && before
    end
  rescue ArgumentError, Date::Error
    jobs
  end

  # Filter a list of job hashes by free-text search.
  def filter_history_jobs_by_text(jobs, filter, filter_column, filter_mode)
    terms = history_filter_terms(filter)
    return jobs if terms.empty?

    jobs.select do |job|
      search_vals = case filter_column
                    when JOB_APP_NAME           then [job[JOB_APP_NAME]]
                    when HEADER_SCRIPT_LOCATION then [job[HEADER_SCRIPT_LOCATION]]
                    when HEADER_SCRIPT_NAME     then [job[HEADER_SCRIPT_NAME], job[OC_SCRIPT_CONTENT]]
                    when JOB_NAME               then [job[JOB_NAME]]
                    when JOB_ID                 then [job[JOB_ID], job[JOB_NAME], job[JOB_APP_NAME]]
                    else                             [job[JOB_ID], job[JOB_APP_NAME], job[HEADER_SCRIPT_LOCATION], job[HEADER_SCRIPT_NAME], job[JOB_NAME]]
                    end
      combined = search_vals.compact.join(" ").downcase

      if filter_mode == "or"
        terms.any? { |term| combined.include?(term.downcase) }
      else
        terms.all? { |term| combined.include?(term.downcase) }
      end
    end
  end

  # Sort a list of job hashes by the given sort key and order.
  def sort_history_jobs(jobs, sort, order)
    sorted = case sort
             when JOB_ID
               jobs.sort_by { |j| history_job_id_sort_key(j[JOB_ID]) }
             when JOB_APP_NAME
               jobs.sort_by { |j| [j[JOB_APP_NAME].to_s.downcase, history_job_id_sort_key(j[JOB_ID])] }
             when HEADER_SCRIPT_LOCATION
               jobs.sort_by { |j| [j[HEADER_SCRIPT_LOCATION].to_s.downcase, history_job_id_sort_key(j[JOB_ID])] }
             when HEADER_SCRIPT_NAME
               jobs.sort_by { |j| [j[HEADER_SCRIPT_NAME].to_s.downcase, history_job_id_sort_key(j[JOB_ID])] }
             when JOB_NAME
               jobs.sort_by { |j| [j[JOB_NAME].to_s.downcase, history_job_id_sort_key(j[JOB_ID])] }
             when JOB_PARTITION
               jobs.sort_by { |j| [j[JOB_PARTITION].to_s.downcase, history_job_id_sort_key(j[JOB_ID])] }
             when JOB_SUBMISSION_TIME
               jobs.sort_by { |j| [j[JOB_SUBMISSION_TIME].to_s, history_job_id_sort_key(j[JOB_ID])] }
             when "Start"
               jobs.sort_by { |j| [j["Start"].to_s, history_job_id_sort_key(j[JOB_ID])] }
             when "End"
               jobs.sort_by { |j| [j["End"].to_s, history_job_id_sort_key(j[JOB_ID])] }
             when JOB_STATUS_ID
               status_order = {
                 JOB_STATUS["queued"]    => 0,
                 JOB_STATUS["running"]   => 1,
                 JOB_STATUS["completed"] => 2,
                 JOB_STATUS["cancelled"] => 3,
                 JOB_STATUS["failed"]    => 4,
                 JOB_STATUS["unknown"]   => 5
               }
               jobs.sort_by { |j| [status_order.fetch(j[JOB_STATUS_ID], -1), history_job_id_sort_key(j[JOB_ID])] }
             else
               jobs.sort_by { |j| history_job_id_sort_key(j[JOB_ID]) }
             end
    order == "asc" ? sorted : sorted.reverse
  end

  # Merge sacct data and DB1 metadata into one page of job hashes.
  # All filtering, sorting, and pagination is done in Ruby.
  def build_merged_history_jobs(sacct_map, db1_map, deleted_ids, statuses, filter, filter_column, filter_mode, date_from, date_to, sort, order, limit, offset, scheduler = nil, extra_sacct_fields = [])
    # sacct is the sole source of which jobs exist. DB1 only enriches (app name, script, etc.).
    all_ids = sacct_map.keys

    jobs = all_ids.filter_map do |jid|
      next if deleted_ids.include?(jid)
      sacct_row = sacct_map[jid]
      db1_row   = db1_map[jid]
      oc_status = sacct_state_to_oc_status(sacct_row["State"].to_s, scheduler)
      submit_time = db1_row&.[]("_submission_time") || normalize_time_for_db(sacct_row&.[]("Submit"))
      {
        JOB_ID                 => jid,
        JOB_APP_NAME           => db1_row&.[]("_app_name"),
        JOB_DIR_NAME           => db1_row&.[]("_app_dir_name"),
        HEADER_SCRIPT_LOCATION => db1_row&.[]("_script_location"),
        HEADER_SCRIPT_NAME     => db1_row&.[]("_script_name"),
        JOB_SUBMISSION_TIME    => submit_time,
        JOB_STATUS_ID          => oc_status,
        JOB_NAME               => sacct_row&.[]("JobName"),
        JOB_PARTITION          => sacct_row&.[]("Partition"),
        OC_SCRIPT_CONTENT      => db1_row&.[]("_script_content"),
        "Start"                => normalize_time_for_db(sacct_row&.[]("Start")),
        "End"                  => normalize_time_for_db(sacct_row&.[]("End")),
        "StdOut"               => sacct_row&.[]("StdOut"),
        "StdErr"               => sacct_row&.[]("StdErr"),
        "_has_db"              => db1_row ? 1 : 0
      }.merge(
        extra_sacct_fields.each_with_object({}) { |f, h| h[f] = sacct_row&.[](f) }
      )
    end

    jobs = filter_history_jobs_by_status(jobs, statuses)
    jobs = filter_history_jobs_by_date(jobs, date_from, date_to)
    jobs = filter_history_jobs_by_text(jobs, filter, filter_column, filter_mode)
    jobs = sort_history_jobs(jobs, sort, order)
    total = jobs.length
    [jobs[offset, limit] || [], total]
  end

  def history_filter_hits_text?(text, filter)
    terms = history_filter_terms(filter)
    return false if terms.empty?

    normalized_text = text.to_s.downcase
    terms.any? { |term| normalized_text.include?(term.downcase) }
  end

  def history_filter_column_items(conf)
    [
      ["all",                  "(ALL)"],
      [JOB_ID,                 "Job ID"],
      [JOB_APP_NAME,           "Application"],
      [HEADER_SCRIPT_LOCATION, "Script Location"],
      [HEADER_SCRIPT_NAME,     "Script Name / Job Script"],
      [JOB_NAME,               "Job Name"]
    ]
  end

  def history_sort_column_items(conf)
    [
      [JOB_ID,                 "Job ID"],
      [JOB_APP_NAME,           "Application"],
      [HEADER_SCRIPT_LOCATION, "Script Location"],
      [HEADER_SCRIPT_NAME,     "Script Name"],
      [JOB_NAME,               "Job Name"],
      [JOB_PARTITION,          "Partition"],
      [JOB_SUBMISSION_TIME,    "Submission Time"],
      ["Start",                "Start Time"],
      ["End",                  "End Time"],
      [JOB_STATUS_ID,          "Status"]
    ]
  end

  def parse_history_filter_column(raw_filter_column, conf)
    valid_columns = history_filter_column_items(conf).map(&:first)
    selected_column = raw_filter_column.to_s
    return "all" if selected_column.empty?
    return selected_column if valid_columns.include?(selected_column)

    "all"
  end

  # Return the filter text only when the selected column should be highlighted.
  def history_highlight_filter(filter, filter_column, column_key)
    return filter if filter_column.to_s == "all" || filter_column.to_s == column_key.to_s

    nil
  end

  # Return whether the Job Script modal contains a filter hit.
  def job_script_modal_matches_filter?(job, filter)
    history_filter_hits_text?(job[OC_SCRIPT_CONTENT], filter)
  end

  # Return whether the Job Details modal contains a filter hit.
  # Returns false when JOB_KEYS is absent (lazy-loaded modal content).
  def job_details_modal_matches_filter?(job, filter)
    return false if job[JOB_KEYS].nil?

    filtered_keys = job[JOB_KEYS] - [JOB_NAME, JOB_PARTITION, JOB_STATUS_ID]
    filtered_keys.any? do |key|
      history_filter_hits_text?(key, filter) || history_filter_hits_text?(job[key], filter)
    end
  end

  # Output a styled status badge for a job based on its current status.
  def output_status(job_status)
    badge_class, status_text = case job_status
                               when JOB_STATUS["queued"]    then ["bg-info text-white", "Queued"]
                               when JOB_STATUS["running"]   then ["bg-primary", "Running"]
                               when JOB_STATUS["completed"] then ["badge-completed", "Completed"]
                               when JOB_STATUS["cancelled"] then ["badge-cancelled", "Cancelled"]
                               when JOB_STATUS["failed"]    then ["bg-danger", "Failed"]
                               else                              ["bg-secondary", "Unknown"]
                               end

    "<span class=\"badge fs-6 #{badge_class}\">#{status_text}</span>\n"
  end

  def output_text(text, filter)
    terms = history_filter_terms(filter)

    text = if text.nil? || terms.empty?
             escape_html(text)
           else
             highlighted_text = escape_html(text)
             terms.uniq.sort_by { |term| -term.length }.each do |term|
               highlighted_text = highlighted_text.gsub(/(#{Regexp.escape(term)})/i, '<span class="bg-warning text-dark">\1</span>')
             end
             highlighted_text
           end

    text.gsub("\n", "<br>")
  end

  def format_history_table_value(key, value)
    return value unless key == JOB_SUBMISSION_TIME

    Time.parse(value.to_s).strftime("%Y-%m-%d %H:%M:%S")
  rescue ArgumentError
    value
  end

  # --- DB helpers ---

  def get_history_db(conf, cluster_name)
    db = conf["history_db"]
    return db unless db.is_a?(Hash)

    cluster_db = db[cluster_name]
    halt 500, "#{cluster_name} is invalid." unless cluster_db

    cluster_db
  end

  def get_legacy_history_db(conf, cluster_name)
    if conf.key?("clusters")
      halt 500, "#{cluster_name} is invalid." unless cluster_name
      return File.join(conf["data_dir"], "#{cluster_name}.db")
    end

    File.join(conf["data_dir"], "#{conf["scheduler"]}.db")
  end

  # Open or create the SQLite history DB and ensure the schema is current.
  def open_history_db(conf, cluster_name)
    sqlite_path = get_history_db(conf, cluster_name)
    legacy_path = get_legacy_history_db(conf, cluster_name)
    migrate_pstore_to_sqlite(sqlite_path, legacy_path, conf) if !File.exist?(sqlite_path) && File.exist?(legacy_path)

    db = SQLite3::Database.new(sqlite_path)
    db.results_as_hash = true
    setup_history_db(db)
    db
  end

  # Create the jobs table (V3 slim schema) and run any pending migrations.
  # On a brand-new DB this creates the 7-column V3 table directly.
  # On an existing V1/V2 DB it runs the appropriate migrations.
  def setup_history_db(db)
    existing_cols = db.table_info("jobs").map { |c| c["name"] }

    if existing_cols.empty?
      # New database — create V3 schema directly, no migrations needed.
      db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS jobs (
          _job_id          TEXT PRIMARY KEY,
          _app_name        TEXT,
          _app_dir_name    TEXT,
          _script_location TEXT,
          _script_name     TEXT,
          _submission_time TEXT,
          _script_content  TEXT
        );
      SQL
    else
      # Existing database — run pending migrations in order.
      migrate_history_db_to_v2(db)
      migrate_history_db_to_v3(db)
    end

    db.execute_batch(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_jobs_submission_time ON jobs(_submission_time);
    SQL
  end

  # Migrate from the old schema (with payload_json) to the new flat schema.
  # Runs once per DB; subsequent calls are no-ops.
  def migrate_history_db_to_v2(db)
    cols = db.table_info("jobs").map { |c| c["name"] }
    return if cols.include?("_deleted")       # already V2 or being migrated to V3
    return if cols.include?("_script_content") # already V3 (fresh DB or post-migration)

    # Rename legacy column names if needed (very old databases)
    migrate_history_db_internal_columns(db)

    db.transaction do
      db.execute_batch(<<~SQL)
        CREATE TABLE jobs_v2 (
          _job_id          TEXT PRIMARY KEY,
          _app_name        TEXT,
          _app_dir_name    TEXT,
          _script_location TEXT,
          _script_name     TEXT,
          _submission_time TEXT,
          _status          TEXT,
          _job_name        TEXT,
          _start_time      TEXT,
          _end_time        TEXT,
          _script_content  TEXT,
          _deleted         INTEGER NOT NULL DEFAULT 0
        );
      SQL

      db.execute("SELECT * FROM jobs").each do |row|
        payload = begin
          JSON.parse(row["payload_json"] || "{}")
        rescue StandardError
          {}
        end

        script_content = payload[OC_SCRIPT_CONTENT] || payload["_script_content"] || row["_script_content"]
        job_name       = row["_job_name"].to_s.empty? ? payload[JOB_NAME] : row["_job_name"]

        db.execute(
          "INSERT OR IGNORE INTO jobs_v2 (_job_id, _app_name, _app_dir_name, _script_location, _script_name, _submission_time, _status, _job_name, _script_content, _deleted) VALUES (?,?,?,?,?,?,?,?,?,0)",
          [row["_job_id"], row["_app_name"], row["_app_dir_name"],
           row["_script_location"], row["_script_name"],
           row["_submission_time"], row["_status"],
           job_name.to_s.empty? ? nil : job_name,
           script_content]
        )
      end

      # Bring in deleted_generic_jobs as tombstone entries so they stay hidden
      begin
        db.execute("SELECT _job_id FROM deleted_generic_jobs").each do |row|
          db.execute(
            "INSERT OR IGNORE INTO jobs_v2 (_job_id, _deleted) VALUES (?, 1)",
            [row["_job_id"]]
          )
        end
      rescue SQLite3::Exception
        # deleted_generic_jobs may not exist — that's fine
      end

      db.execute("DROP TABLE jobs")
      db.execute("ALTER TABLE jobs_v2 RENAME TO jobs")
    end
  end

  # Migrate from the V2 schema (which has _status, _job_name, _start_time, _end_time, _deleted)
  # to the V3 slim schema (7 columns only). Runs once per DB; subsequent calls are no-ops.
  # V3 detection: absence of "_status" column in jobs table.
  def migrate_history_db_to_v3(db)
    cols = db.table_info("jobs").map { |c| c["name"] }
    return unless cols.include?("_status") || cols.include?("_deleted")

    db.transaction do
      # Step 1: copy deleted job IDs to deleted_db (handled by caller via open_deleted_db).
      # We store them in a temporary table within the same DB so the caller can pick them up.
      db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS _v3_deleted_export (
          _job_id TEXT PRIMARY KEY,
          _deleted_at TEXT
        );
      SQL

      if cols.include?("_deleted")
        db.execute("SELECT _job_id FROM jobs WHERE _deleted = 1").each do |row|
          db.execute(
            "INSERT OR IGNORE INTO _v3_deleted_export (_job_id, _deleted_at) VALUES (?, ?)",
            [row["_job_id"], Time.now.iso8601]
          )
        end
      end

      # Step 2: recreate jobs table with only 7 columns.
      db.execute_batch(<<~SQL)
        CREATE TABLE jobs_v3 (
          _job_id          TEXT PRIMARY KEY,
          _app_name        TEXT,
          _app_dir_name    TEXT,
          _script_location TEXT,
          _script_name     TEXT,
          _submission_time TEXT,
          _script_content  TEXT
        );
      SQL

      db.execute("SELECT * FROM jobs WHERE _deleted = 0 OR _deleted IS NULL").each do |row|
        next if row["_job_id"].to_s.match?(/\A\d+_\[/) # drop old [range] rows — no OC metadata
        db.execute(
          "INSERT OR IGNORE INTO jobs_v3 (_job_id, _app_name, _app_dir_name, _script_location, _script_name, _submission_time, _script_content) VALUES (?,?,?,?,?,?,?)",
          [row["_job_id"], row["_app_name"], row["_app_dir_name"],
           row["_script_location"], row["_script_name"],
           row["_submission_time"], row["_script_content"]]
        )
      end

      db.execute("DROP TABLE jobs")
      db.execute("ALTER TABLE jobs_v3 RENAME TO jobs")
    end
  end

  # Return the path for the deleted-jobs DB corresponding to a history DB path.
  def get_deleted_db_path(conf, cluster_name)
    base = get_history_db(conf, cluster_name)
    base.sub(/\.sqlite3\z/, "_deleted.sqlite3")
  end

  # Create the deleted_jobs table in the given DB connection.
  def setup_deleted_db(db)
    db.execute_batch(<<~SQL)
      CREATE TABLE IF NOT EXISTS deleted_jobs (
        _job_id     TEXT PRIMARY KEY,
        _deleted_at TEXT
      );
    SQL
  end

  # Open (or create) the deleted-jobs DB, applying any pending V3 migration exports.
  # Pass main_db: to reuse an already-open connection to the history DB instead of
  # opening a second one (the caller must not close that connection itself).
  def open_deleted_db(conf, cluster_name, main_db: nil)
    deleted_path = get_deleted_db_path(conf, cluster_name)
    FileUtils.mkdir_p(File.dirname(deleted_path))
    db = SQLite3::Database.new(deleted_path)
    db.results_as_hash = true
    setup_deleted_db(db)

    # If the main history DB has a _v3_deleted_export table (written during V3 migration),
    # drain it into the deleted DB now and drop it from the main DB.
    own_connection = main_db.nil?
    if own_connection
      main_path = get_history_db(conf, cluster_name)
      main_db   = SQLite3::Database.new(main_path) if File.exist?(main_path.to_s)
      main_db&.results_as_hash = true
    end

    if main_db
      begin
        rows = main_db.execute("SELECT _job_id, _deleted_at FROM _v3_deleted_export")
        unless rows.empty?
          db.transaction do
            rows.each do |row|
              db.execute(
                "INSERT OR IGNORE INTO deleted_jobs (_job_id, _deleted_at) VALUES (?, ?)",
                [row["_job_id"], row["_deleted_at"]]
              )
            end
          end
          main_db.execute("DROP TABLE _v3_deleted_export")
        end
      rescue SQLite3::Exception
        # _v3_deleted_export doesn't exist — that's fine, migration already done
      ensure
        main_db.close if own_connection
      end
    end

    db
  end

  # Rename legacy (non-prefixed) column names to the _-prefixed convention.
  def migrate_history_db_internal_columns(db)
    columns = db.table_info("jobs").map { |c| c["name"] }
    legacy_to_internal = {
      "job_id"         => "_job_id",
      "app_name"       => "_app_name",
      "app_dir_name"   => "_app_dir_name",
      "script_location"=> "_script_location",
      "script_name"    => "_script_name",
      "job_name"       => "_job_name",
      "partition"      => "_partition",
      "submission_time"=> "_submission_time",
      "updated_time"   => "_updated_time",
      "status"         => "_status"
    }

    legacy_to_internal.each do |legacy, internal|
      next unless columns.include?(legacy)
      next if columns.include?(internal)

      db.execute("ALTER TABLE jobs RENAME COLUMN #{legacy} TO #{internal}")
      columns[columns.index(legacy)] = internal
    end
  end

  # Return one job record by ID.
  def find_job(db, job_id)
    db.get_first_row("SELECT * FROM jobs WHERE _job_id = ?", [job_id])
  end

  # Insert or overwrite a job record (7-column V3 schema).
  def upsert_job(db, record)
    params = [
      record["_job_id"],
      record["_app_name"],
      record["_app_dir_name"],
      record["_script_location"],
      record["_script_name"],
      record["_submission_time"],
      record["_script_content"]
    ]
    db.execute(<<~SQL, params)
      INSERT INTO jobs (_job_id, _app_name, _app_dir_name, _script_location, _script_name,
                        _submission_time, _script_content)
      VALUES (?,?,?,?,?,?,?)
      ON CONFLICT(_job_id) DO UPDATE SET
        _app_name        = excluded._app_name,
        _app_dir_name    = excluded._app_dir_name,
        _script_location = excluded._script_location,
        _script_name     = excluded._script_name,
        _submission_time = excluded._submission_time,
        _script_content  = excluded._script_content
    SQL
  end

  # Delete all given job IDs from DB1 and record them in DB2.
  def delete_all_jobs(db, deleted_db, job_ids)
    return if job_ids.nil? || job_ids.empty?

    now = Time.now.iso8601
    deleted_db.transaction do
      job_ids.each do |job_id|
        deleted_db.execute(
          "INSERT OR IGNORE INTO deleted_jobs (_job_id, _deleted_at) VALUES (?, ?)",
          [job_id, now]
        )
      end
    end
    db.transaction do
      job_ids.each do |job_id|
        db.execute("DELETE FROM jobs WHERE _job_id = ?", [job_id])
      end
    end
  end

  # Delete a single job from DB1 and record it in DB2.
  def delete_job(db, deleted_db, job_id)
    now = Time.now.iso8601
    deleted_db.execute(
      "INSERT OR IGNORE INTO deleted_jobs (_job_id, _deleted_at) VALUES (?, ?)",
      [job_id, now]
    )
    db.execute("DELETE FROM jobs WHERE _job_id = ?", [job_id])
  end

  # Convert a DB row to a hash keyed by the legacy/public constants.
  def job_record_to_legacy_hash(record)
    return nil unless record

    {
      JOB_ID                 => record["_job_id"],
      JOB_APP_NAME           => record["_app_name"],
      JOB_DIR_NAME           => record["_app_dir_name"],
      HEADER_SCRIPT_LOCATION => record["_script_location"],
      HEADER_SCRIPT_NAME     => record["_script_name"],
      JOB_SUBMISSION_TIME    => record["_submission_time"],
      OC_SCRIPT_CONTENT      => record["_script_content"]
    }
  end

  # Return true if a job ID has a valid format for this scheduler.
  # Dispatches to the scheduler's own valid_job_id? method when available.
  def valid_oc_job_id?(job_id, scheduler = nil)
    return scheduler.valid_job_id?(job_id) if scheduler.respond_to?(:valid_job_id?)
    job_id.to_s.match?(/\A\d+\z/) || job_id.to_s.match?(/\A\d+_\d+\z/) || job_id.to_s.match?(/\A\d+_\[/)
  end

  # Map a raw scheduler state string to an OpenComposer status constant.
  # Dispatches to the scheduler's own state_to_oc_status method when available.
  def sacct_state_to_oc_status(state, scheduler = nil)
    return scheduler.state_to_oc_status(state) if scheduler.respond_to?(:state_to_oc_status)

    s = state.to_s
    return JOB_STATUS["cancelled"] if s.start_with?("CANCELLED")

    case s
    when "COMPLETED"
      JOB_STATUS["completed"]
    when "CONFIGURING", "REQUEUED", "RESIZING", "PENDING", "PREEMPTED", "SUSPENDED"
      JOB_STATUS["queued"]
    when "COMPLETING", "RUNNING"
      JOB_STATUS["running"]
    when "STOPPED"
      JOB_STATUS["cancelled"]
    when "BOOT_FAIL", "DEADLINE", "FAILED", "NODE_FAIL", "OUT_OF_MEMORY",
         "REVOKED", "SPECIAL_EXIT", "TIMEOUT"
      JOB_STATUS["failed"]
    else
      JOB_STATUS["unknown"]
    end
  end

  # Normalize a time string into ISO 8601 using the local timezone.
  def normalize_time_for_db(value)
    return nil if value.nil?

    string = value.to_s.strip
    return nil if string.empty?

    Time.parse(string).iso8601
  rescue ArgumentError
    nil
  end

  # Migrate a legacy PStore DB to SQLite (runs only when the SQLite file is absent).
  def migrate_pstore_to_sqlite(sqlite_path, legacy_path, conf)
    FileUtils.mkdir_p(File.dirname(sqlite_path))

    db = SQLite3::Database.new(sqlite_path)
    db.results_as_hash = true
    setup_history_db(db)

    begin
      db.transaction
      store = PStore.new(legacy_path)
      store.transaction(true) do
        store.roots.each do |job_id|
          data = store[job_id]
          next unless data

          upsert_job(db, convert_pstore_record_to_sqlite(job_id.to_s, data))
        end
      end
      db.commit
    rescue StandardError
      db.rollback
      db.close if db
      File.delete(sqlite_path) if File.exist?(sqlite_path)
      raise
    end

    db.close
  end

  # Convert a legacy PStore record into a new-schema job record (7 columns).
  def convert_pstore_record_to_sqlite(job_id, data)
    legacy = (data || {}).transform_keys(&:to_s)

    {
      "_job_id"          => job_id,
      "_app_name"        => legacy[JOB_APP_NAME.to_s],
      "_app_dir_name"    => legacy[JOB_DIR_NAME.to_s],
      "_script_location" => legacy[HEADER_SCRIPT_LOCATION.to_s],
      "_script_name"     => legacy[HEADER_SCRIPT_NAME.to_s],
      "_submission_time" => normalize_time_for_db(legacy[JOB_SUBMISSION_TIME.to_s]),
      "_script_content"  => legacy[OC_SCRIPT_CONTENT.to_s]
    }
  end
end
