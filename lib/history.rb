

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

        # Generate icon HTML based on whether it's a Bootstrap/Font Awesome icon or an image
        icon_html = if is_bi_or_fa_icon
                      "<i class=\"#{icon} fs-5\"></i>"
                    else
                      "<img width=20 title=\"#{name}\" alt=\"#{name}\" src=\"#{icon_path}\">"
                    end
      end

      # Return the full HTML string for the link
      "<a style=\"color: black; text-decoration: none;\" target=\"_blank\" href=\"#{href}\">\n  #{icon_html}\n</a>\n"
    end
  end

  # Output a modal for a specific action (e.g., CancelJob or DeleteInfo).
  def output_action_modal(action)
    id = "_history#{action}"
    form_action = history_path_with_query

    <<~HTML
    <div class="modal" id="#{id}" aria-hidden="true" tabindex="-1">
      <div class="modal-dialog modal-dialog-scrollable">
        <div class="modal-content">
          <div class="modal-body" id="#{id}Body">
            (Something wrong)
          </div>
          <div class="modal-footer">
            <form action="#{form_action}" method="post" id="#{id}Form">
              <input type="hidden" name="action" value="#{action}">
              <input type="hidden" name="JobIds" id="#{id}Input">
              <button type="button" class="btn btn-secondary" data-bs-dismiss="modal" tabindex="-1">Cancel</button>
              <button type="submit" class="btn btn-primary" tabindex="-1">OK</button>
            </form>
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
    <button id="_history#{action}Badge" data-bs-toggle="modal" data-bs-target="#_history#{action}" class="btn btn-sm btn-danger disabled" disabled>
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

  # Output a modal for displaying details of a specific job.
  def output_job_id_modal(job, filter)
    return if job[JOB_KEYS].nil? # If a job has just been submitted, it may not have been registered yet.

    modal_id = "_historyJobId#{job[JOB_ID]}"
    html = <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1">
      <div class="modal-dialog modal-dialog-scrollable modal-lg">
        <div class="modal-content" style="resize: horizontal; padding-right: 16px;">
          <div class="modal-header">
            <h5>Job Details</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body">
            <table class="table table-striped table-sm text-break">
    HTML

    filtered_keys = job[JOB_KEYS] - [JOB_NAME, JOB_PARTITION, JOB_STATUS_ID]
    filtered_keys.each do |key|
      html += "<tr><td>#{output_text(key, filter)}</td><td>#{output_text(job[key], filter)}</td></tr>\n"
    end

    html += <<~HTML
            </table>
          </div>
        </div>
      </div>
    </div>
    HTML
  end

  # Output a modal displaying a job script and a link to load parameters for a specific job.
  def output_job_script_modal(job, filter)
    modal_id = "_historyJobScript#{job[JOB_ID]}"
    job_link = "#{File.join(@script_name.to_s, job[JOB_DIR_NAME].to_s)}?jobId=#{URI.encode_www_form_component(job[JOB_ID].to_s)}"
    job_link += "&cluster=#{@cluster_name}" if @cluster_name

    <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1">
      <div class="modal-dialog modal-dialog-scrollable modal-lg">
        <div class="modal-content" style="resize: horizontal; padding-right: 16px;">
          <div class="modal-header">
            <h5>Job Script</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body">
            #{output_text(job[OC_SCRIPT_CONTENT], filter)}
          </div>
          <div class="modal-footer">
            <a href="#{job_link}" class="btn btn-primary text-white text-decoration-none">Load parameters</a>
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

  # Build a history page path while preserving the current filters.
  def history_valid_statuses
    %w[running queued completed failed]
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
      "statuses" => @statuses,
      "filter" => @filter,
      "filter_column" => @filter_column,
      "sort" => @sort,
      "order" => @order,
      "date_range" => @date_range,
      "filter_mode" => @filter_mode,
      "date_from" => @date_from,
      "date_to" => @date_to,
      "detail_open" => @detail_open,
      "rows" => @rows,
      "p" => @current_page,
      "cluster" => @cluster_name
    }

    overrides.each do |key, value|
      values[key.to_s] = value
    end

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

  # Split the filter text into search terms.
  def history_filter_terms(filter_text)
    filter_text.to_s.split(/\s+/).reject(&:empty?)
  end

  # Return the selected History sort key if valid.
  def parse_history_sort(raw_sort, conf)
    sort = raw_sort.to_s
    # History page defaults to Job ID order, so an empty sort parameter
    # is normalized to the internal Job ID key instead of "".
    return JOB_ID if sort.empty?

    valid_columns = history_sort_column_items(conf).map(&:first)
    valid_columns.include?(sort) ? sort : JOB_ID
  end

  # Return the selected History sort order if valid.
  def parse_history_order(raw_order)
    order = raw_order.to_s
    return "desc" if order.empty?

    %w[asc desc].include?(order) ? order : "desc"
  end

  # Return available date range presets for the History search UI.
  def history_date_range_items
    [
      ["all", "(ALL)"],
      ["today", "Today"],
      ["yesterday", "Yesterday and Today"],
      ["last7", "Last 7 days"],
      ["last30", "Last 30 days"],
      ["custom", "Custom"]
    ]
  end

  # Normalize the date range selection into UI state and actual date bounds.
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

  # Return whether the submission time is within the specified date range.
  def history_date_range_matches?(submission_time, date_from, date_to)
    return true if date_from.to_s.empty? && date_to.to_s.empty?

    normalized_time = normalize_time_for_db(submission_time)
    return false if normalized_time.nil?

    value = Time.parse(normalized_time)
    from_time = date_from.to_s.empty? ? nil : Time.parse(date_from.to_s)
    to_time = date_to.to_s.empty? ? nil : (Time.parse(date_to.to_s) + 86400)

    return false if from_time && value < from_time
    return false if to_time && value >= to_time

    true
  rescue ArgumentError
    true
  end

  # Return a natural sort key for scheduler-specific job IDs.
  # Supported formats:
  # - "12345"       : single job
  # - "12345_6"     : array/sub job with "_" separator (e.g. Slurm, Fujitsu TCS)
  # - "12345.6"     : array/sub job with "." separator (e.g. Grid Engine)
  # - "12345[6]"    : array/sub job with "[]" suffix (e.g. PBS/PBS Pro)
  # Unsupported formats fall back to string comparison after numeric IDs.
  def history_job_id_sort_key(job_id)
    value = job_id.to_s

    case value
    when /\A(\d+)\z/
      [$1.to_i, -1, value]
    when /\A(\d+)[_.](\d+)\z/
      [$1.to_i, $2.to_i, value]
    when /\A(\d+)\[(\d+)\]\z/
      [$1.to_i, $2.to_i, value]
    else
      [Float::INFINITY, Float::INFINITY, value]
    end
  end

  # Return a stable sort key for the selected History sort column.
  def history_generic_value_sort_key(value)
    normalized = format_history_table_value(nil, value).to_s.strip

    if normalized.match?(/\A-?\d+\z/)
      [0, normalized.to_i, normalized.downcase]
    elsif normalized.match?(/\A-?\d+\.\d+\z/)
      [1, normalized.to_f, normalized.downcase]
    else
      [2, normalized.downcase]
    end
  end

  def history_sort_key(job, sort)
    case sort
    when JOB_ID
      history_job_id_sort_key(job[JOB_ID])
    when JOB_APP_NAME
      [job[JOB_APP_NAME].to_s.downcase, *history_job_id_sort_key(job[JOB_ID])]
    when HEADER_SCRIPT_LOCATION
      [job[HEADER_SCRIPT_LOCATION].to_s.downcase, *history_job_id_sort_key(job[JOB_ID])]
    when HEADER_SCRIPT_NAME
      [job[HEADER_SCRIPT_NAME].to_s.downcase, *history_job_id_sort_key(job[JOB_ID])]
    when JOB_STATUS_ID
      status_order = {
        JOB_STATUS["queued"] => 0,
        JOB_STATUS["running"] => 1,
        JOB_STATUS["completed"] => 2,
        JOB_STATUS["failed"] => 3
      }
      [status_order.fetch(job[JOB_STATUS_ID], 99), *history_job_id_sort_key(job[JOB_ID])]
    when JOB_SUBMISSION_TIME
      [normalize_time_for_db(job[JOB_SUBMISSION_TIME]) || "", *history_job_id_sort_key(job[JOB_ID])]
    else
      [*history_generic_value_sort_key(job[sort]), *history_job_id_sort_key(job[JOB_ID])]
    end
  end

  # Return whether the selected sort column can be ordered directly in SQLite.
  def history_sql_sortable_column?(sort)
    [
      JOB_ID,
      JOB_APP_NAME,
      HEADER_SCRIPT_LOCATION,
      HEADER_SCRIPT_NAME,
      JOB_NAME,
      JOB_PARTITION,
      JOB_STATUS_ID,
      JOB_SUBMISSION_TIME
    ].include?(sort)
  end

  # Return whether the request can use the SQL fast path.
  # For now, only the no-search case with SQL-sortable columns is optimized.
  # Search-specific filtering and custom History columns still fall back to
  # the existing Ruby path so sorting remains correct.
  def history_use_sql_fast_path?(filter, sort)
    history_filter_terms(filter).empty? && history_sql_sortable_column?(sort)
  end

  # Build SQL WHERE clauses and bind params for filters that map cleanly to DB columns.
  def history_sql_where(statuses, date_from, date_to)
    clauses = []
    params = []

    selected_statuses = Array(statuses).map(&:to_s).filter_map { |status| JOB_STATUS[status] }
    if selected_statuses.empty?
      clauses << "1 = 0"
    else
      placeholders = (["?"] * selected_statuses.length).join(", ")
      clauses << "_status IN (#{placeholders})"
      params.concat(selected_statuses)
    end

    unless date_from.to_s.empty?
      clauses << "_submission_time >= ?"
      params << Time.parse(date_from.to_s).iso8601
    end

    unless date_to.to_s.empty?
      clauses << "_submission_time < ?"
      params << (Time.parse(date_to.to_s) + 86400).iso8601
    end

    [clauses, params]
  rescue ArgumentError
    [clauses, params]
  end

  # Return SQL ORDER BY for columns that can be sorted directly in SQLite.
  def history_sql_order(sort, order)
    direction = order == "asc" ? "ASC" : "DESC"

    case sort
    when JOB_ID
      # Approximate the existing natural job-id order inside SQLite.
      <<~SQL.gsub(/\s+/, " ").strip
        CAST(_job_id AS INTEGER) #{direction},
        CASE
          WHEN instr(_job_id, '_') > 0 THEN CAST(substr(_job_id, instr(_job_id, '_') + 1) AS INTEGER)
          WHEN instr(_job_id, '.') > 0 THEN CAST(substr(_job_id, instr(_job_id, '.') + 1) AS INTEGER)
          WHEN instr(_job_id, '[') > 0 AND instr(_job_id, ']') > instr(_job_id, '[')
            THEN CAST(substr(_job_id, instr(_job_id, '[') + 1, instr(_job_id, ']') - instr(_job_id, '[') - 1) AS INTEGER)
          ELSE -1
        END #{direction},
        _job_id #{direction}
      SQL
    when JOB_APP_NAME
      "_app_name #{direction}, _job_id #{direction}"
    when HEADER_SCRIPT_LOCATION
      "_script_location #{direction}, _job_id #{direction}"
    when HEADER_SCRIPT_NAME
      "_script_name #{direction}, _job_id #{direction}"
    when JOB_NAME
      "_job_name #{direction}, _job_id #{direction}"
    when JOB_PARTITION
      "_partition #{direction}, _job_id #{direction}"
    when JOB_STATUS_ID
      status_case = <<~SQL.gsub(/\s+/, " ").strip
        CASE _status
          WHEN '#{JOB_STATUS["queued"]}' THEN 0
          WHEN '#{JOB_STATUS["running"]}' THEN 1
          WHEN '#{JOB_STATUS["completed"]}' THEN 2
          WHEN '#{JOB_STATUS["failed"]}' THEN 3
          ELSE 99
        END
      SQL
      "#{status_case} #{direction}, _job_id #{direction}"
    when JOB_SUBMISSION_TIME
      "_submission_time #{direction}, _job_id #{direction}"
    else
      "_job_id #{direction}"
    end
  end

  # Return the total number of History rows matching SQL-friendly filters.
  def count_history_jobs(db, statuses, date_from, date_to)
    where_clauses, where_params = history_sql_where(statuses, date_from, date_to)
    where_sql = where_clauses.empty? ? "" : "WHERE #{where_clauses.join(' AND ')}"

    db.get_first_value("SELECT COUNT(*) FROM jobs #{where_sql}", where_params).to_i
  end

  # Return one page of History rows using SQL-friendly filters and sorting.
  def fetch_history_jobs_page(db, statuses, date_from, date_to, sort, order, limit, offset)
    where_clauses, where_params = history_sql_where(statuses, date_from, date_to)
    where_sql = where_clauses.empty? ? "" : "WHERE #{where_clauses.join(' AND ')}"
    order_sql = history_sql_order(sort, order)

    db.execute(
      "SELECT * FROM jobs #{where_sql} ORDER BY #{order_sql} LIMIT ? OFFSET ?",
      where_params + [limit, offset]
    )
  end

  # Return whether the filter terms match according to the selected mode.
  def history_filter_mode_matches?(search_text, filter_text, filter_mode)
    terms = history_filter_terms(filter_text)
    return true if terms.empty?

    if filter_mode == "or"
      terms.any? { |term| search_text.to_s.include?(term) }
    else
      terms.all? { |term| search_text.to_s.include?(term) }
    end
  end

  # Return whether any search term appears in the given text.
  def history_filter_hits_text?(text, filter)
    terms = history_filter_terms(filter)
    return false if terms.empty?

    normalized_text = text.to_s.downcase
    terms.any? { |term| normalized_text.include?(term.downcase) }
  end

  # Return history DB
  def get_history_db(conf, cluster_name)
    db = conf["history_db"]
    return db unless db.is_a?(Hash)

    cluster_db = db[cluster_name]
    halt 500, "#{cluster_name} is invalid." unless cluster_db

    return cluster_db
  end

  # Return a legacy PStore DB path from the current configuration.
  def get_legacy_history_db(conf, cluster_name)
    if conf.key?("clusters")
      halt 500, "#{cluster_name} is invalid." unless cluster_name
      return File.join(conf["data_dir"], "#{cluster_name}.db")
    end

    return File.join(conf["data_dir"], "#{conf["scheduler"]}.db")
  end

  # Open a SQLite history DB and ensure the required schema exists.
  def open_history_db(conf, cluster_name)
    sqlite_path = get_history_db(conf, cluster_name)
    legacy_path = get_legacy_history_db(conf, cluster_name)
    migrate_pstore_to_sqlite(sqlite_path, legacy_path, conf) if !File.exist?(sqlite_path) && File.exist?(legacy_path)

    db = SQLite3::Database.new(sqlite_path)
    db.results_as_hash = true
    setup_history_db(db)
    db
  end

  # Create the required tables and indexes if they do not exist yet.
  def setup_history_db(db)
    db.execute_batch(<<~SQL)
      CREATE TABLE IF NOT EXISTS jobs (
        _job_id TEXT PRIMARY KEY,
        _app_name TEXT,
        _app_dir_name TEXT,
        _script_location TEXT,
        _script_name TEXT,
        _job_name TEXT,
        _partition TEXT,
        _submission_time TEXT,
        _updated_time TEXT,
        _status TEXT,
        payload_json TEXT NOT NULL DEFAULT '{}'
      );
    SQL

    migrate_history_db_internal_columns(db)

    db.execute_batch(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(_status);
      CREATE INDEX IF NOT EXISTS idx_jobs_submission_time ON jobs(_submission_time);
      CREATE INDEX IF NOT EXISTS idx_jobs_updated_time ON jobs(_updated_time);
    SQL
  end

  # Rename legacy History DB columns to the internal-name convention.
  def migrate_history_db_internal_columns(db)
    columns = db.table_info("jobs").map { |column| column["name"] }
    legacy_to_internal = {
      "job_id" => "_job_id",
      "app_name" => "_app_name",
      "app_dir_name" => "_app_dir_name",
      "script_location" => "_script_location",
      "script_name" => "_script_name",
      "job_name" => "_job_name",
      "partition" => "_partition",
      "submission_time" => "_submission_time",
      "updated_time" => "_updated_time",
      "status" => "_status"
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

  # Insert or update a job record.
  def upsert_job(db, record)
    params = [
      record["_job_id"],
      record["_app_name"],
      record["_app_dir_name"],
      record["_script_location"],
      record["_script_name"],
      record["_job_name"],
      record["_partition"],
      record["_submission_time"],
      record["_updated_time"],
      record["_status"],
      record["payload_json"]
    ]

    db.execute(<<~SQL, params)
      INSERT INTO jobs (
        _job_id,
        _app_name,
        _app_dir_name,
        _script_location,
        _script_name,
        _job_name,
        _partition,
        _submission_time,
        _updated_time,
        _status,
        payload_json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(_job_id) DO UPDATE SET
        _app_name = excluded._app_name,
        _app_dir_name = excluded._app_dir_name,
        _script_location = excluded._script_location,
        _script_name = excluded._script_name,
        _job_name = excluded._job_name,
        _partition = excluded._partition,
        _submission_time = excluded._submission_time,
        _updated_time = excluded._updated_time,
        _status = excluded._status,
        payload_json = excluded.payload_json
    SQL
  end

  # Delete one job record.
  def delete_job(db, job_id)
    db.execute("DELETE FROM jobs WHERE _job_id = ?", [job_id])
  end

  # Yield each job record.
  def each_job(db, &block)
    db.execute("SELECT * FROM jobs", &block)
  end

  # Return all unfinished job IDs.
  def get_unfinished_job_ids(db)
    db.execute(<<~SQL, [JOB_STATUS["completed"], JOB_STATUS["failed"]]).map { |row| row["_job_id"] }
      SELECT _job_id
      FROM jobs
      WHERE _status IS NULL OR (_status != ? AND _status != ?)
      ORDER BY _submission_time DESC, _job_id DESC
    SQL
  end

  # Merge incoming data into existing data while preserving existing values for nil/empty updates.
  def merge_job_data(existing, incoming)
    merged = (existing || {}).dup
    (incoming || {}).each do |key, value|
      next if value.nil?
      next if value.is_a?(String) && value.empty?

      merged[key] = value
    end
    merged
  end

  # Return the keys that are stored as dedicated columns instead of payload_json.
  def job_record_column_keys
    %w[
      _job_id
      _app_name
      _app_dir_name
      _script_location
      _script_name
      _job_name
      _partition
      _submission_time
      _updated_time
      _status
    ]
  end

  # Return legacy/external keys whose values duplicate dedicated DB columns.
  # These keys are candidates for removal from payload_json because the values
  # can be reconstructed from the dedicated columns.
  def payload_duplicate_legacy_keys
    [
      JOB_APP_NAME,
      JOB_DIR_NAME,
      HEADER_SCRIPT_LOCATION,
      HEADER_SCRIPT_NAME,
      HEADER_JOB_NAME,
      JOB_NAME,
      JOB_PARTITION,
      JOB_SUBMISSION_TIME,
      JOB_STATUS_ID
    ]
  end

  # Return all keys that should be excluded from payload_json because they are
  # stored in dedicated DB columns or can be reconstructed from those columns.
  def payload_excluded_keys
    (job_record_column_keys + payload_duplicate_legacy_keys).map(&:to_s).uniq
  end

  # Build payload data by excluding dedicated column keys.
  def build_payload_hash(record_hash)
    excluded_keys = payload_excluded_keys
    (record_hash || {}).each_with_object({}) do |(key, value), payload|
      next if excluded_keys.include?(key.to_s)
      payload[key.to_s] = value
    end
  end

  # Flatten nested values into an array of searchable scalar values.
  def history_search_values(value)
    case value
    when nil
      []
    when Array
      value.flat_map { |item| history_search_values(item) }
    when Hash
      value.values.flat_map { |item| history_search_values(item) }
    else
      [value]
    end
  end

  # Return dedicated columns that should be included in all-column search text.
  def search_column_keys
    job_record_column_keys - %w[_status]
  end

  # Return configured history fields as [key, label] pairs.
  def history_config_items(conf)
    history_items = conf["history"] || HISTORY_KEY_MAP.keys

    entries =
      if history_items.is_a?(Hash)
        history_items.to_a
      else
        Array(history_items)
      end

    entries.each_with_object([]) do |item, items|
      if item.is_a?(Hash)
        item.each do |key, opt|
          normalized_key = key.to_s
          label = (opt.is_a?(Hash) && (opt["label"] || opt[:label])) || HISTORY_KEY_MAP.fetch(normalized_key, normalized_key)
          items << [normalized_key, label]
        end
      elsif item.is_a?(Array) && item.size == 2
        key, opt = item
        normalized_key = key.to_s
        label = (opt.is_a?(Hash) && (opt["label"] || opt[:label])) || HISTORY_KEY_MAP.fetch(normalized_key, normalized_key)
        items << [normalized_key, label]
      else
        normalized_key = item.to_s
        items << [normalized_key, HISTORY_KEY_MAP.fetch(normalized_key, normalized_key)]
      end
    end
  end

  # Return searchable History table columns in display order.
  def history_filter_column_items(conf)
    items = [
      ["all", "(ALL)"],
      [JOB_ID, "Job ID / Job Details"],
      [JOB_APP_NAME, "Application"],
      [HEADER_SCRIPT_LOCATION, "Script Location"],
      [HEADER_SCRIPT_NAME, "Script Name / Job Script"]
    ]

    history_config_items(conf).each do |key, label|
      items << [HISTORY_KEY_MAP.fetch(key, key), label]
    end

    items
  end

  # Return sortable History table columns in display order.
  def history_sort_column_items(conf)
    items = [
      [JOB_ID, "Job ID"],
      [JOB_APP_NAME, "Application"],
      [HEADER_SCRIPT_LOCATION, "Script Location"],
      [HEADER_SCRIPT_NAME, "Script Name"],
      [JOB_STATUS_ID, "Status"]
    ]

    history_config_items(conf).each do |key, label|
      items << [HISTORY_KEY_MAP.fetch(key, key), label]
    end

    items
  end

  # Return the selected history filter column if valid.
  def parse_history_filter_column(raw_filter_column, conf)
    valid_columns = history_filter_column_items(conf).map(&:first)
    selected_column = raw_filter_column.to_s
    return "all" if selected_column.empty?
    return selected_column if valid_columns.include?(selected_column)

    "all"
  end

  # Return search text for the selected History table column.
  def history_filter_target_text(row, filter_column)
    return build_search_text_from_row(row) if filter_column == "all"

    job = { JOB_ID => row["_job_id"] }.merge(job_record_to_legacy_hash(row))
    if filter_column == JOB_ID
      detail_values = Array(job[JOB_KEYS]).flat_map do |key|
        [key, job[key]]
      end
      return ([job[JOB_ID]] + detail_values).compact.join(" ").downcase
    end

    if filter_column == HEADER_SCRIPT_NAME
      return [job[HEADER_SCRIPT_NAME], job[OC_SCRIPT_CONTENT]].compact.join(" ").downcase
    end

    value = job[filter_column]
    value.nil? ? "" : value.to_s.downcase
  end

  # Return the filter text only when the selected column should be highlighted.
  def history_highlight_filter(filter, filter_column, column_key)
    return filter if filter_column.to_s == "all" || filter_column.to_s == column_key.to_s

    nil
  end

  # Build all-column search text from stored job values and payload_json content.
  def build_search_text(record, payload_hash)
    payload_hash ||= {}
    values = search_column_keys.flat_map do |key|
      history_search_values(record[key] || record[key.to_sym])
    end
    values.concat(history_search_values(payload_hash))

    values
      .compact
      .map(&:to_s)
      .map { |value| value.gsub(/\s+/, " ").strip }
      .reject(&:empty?)
      .join(" ")
      .downcase
  end

  # Build all-column search text directly from one DB row.
  # This keeps the search-text construction logic reusable even after the
  # persisted jobs.search_text cache is removed.
  def build_search_text_from_row(row)
    payload_hash = JSON.parse(row["payload_json"] || "{}")
    build_search_text(row, payload_hash)
  end

  # Build a SQLite job record from existing, submit, and scheduler data.
  def build_job_record(existing:, submit_data:, scheduler_data:)
    merged = merge_job_data({}, existing)
    merged = merge_job_data(merged, submit_data)
    merged = merge_job_data(merged, scheduler_data)

    record = {
      "_job_id" => merged["_job_id"],
      "_app_name" => merged["_app_name"],
      "_app_dir_name" => merged["_app_dir_name"],
      "_script_location" => merged["_script_location"],
      "_script_name" => merged["_script_name"],
      "_job_name" => merged["_job_name"] || "",
      "_partition" => merged["_partition"] || "",
      "_submission_time" => merged["_submission_time"],
      "_updated_time" => merged["_updated_time"],
      "_status" => merged["_status"]
    }

    payload_hash = build_payload_hash(merged)
    record["payload_json"] = JSON.generate(payload_hash)
    record
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

  # Migrate one legacy PStore DB into a SQLite DB.
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

  # Convert a legacy PStore record into a SQLite job record.
  def convert_pstore_record_to_sqlite(job_id, data)
    legacy = (data || {}).transform_keys(&:to_s)

    submission_time = normalize_time_for_db(legacy[JOB_SUBMISSION_TIME.to_s])
    merged = legacy.merge(
      "_job_id" => job_id,
      "_app_name" => legacy[JOB_APP_NAME.to_s],
      "_app_dir_name" => legacy[JOB_DIR_NAME.to_s],
      "_script_location" => legacy[HEADER_SCRIPT_LOCATION.to_s],
      "_script_name" => legacy[HEADER_SCRIPT_NAME.to_s],
      "_job_name" => legacy[JOB_NAME.to_s] || legacy[HEADER_JOB_NAME.to_s] || "",
      "_partition" => legacy[JOB_PARTITION.to_s] || legacy["partition"] || "",
      "_submission_time" => submission_time,
      "_updated_time" => submission_time,
      "_status" => legacy[JOB_STATUS_ID.to_s]
    )

    build_job_record(existing: nil, submit_data: merged, scheduler_data: nil)
  end

  # Parse payload_json and merge it back with dedicated columns using legacy key names.
  def job_record_to_legacy_hash(record)
    return nil unless record

    payload_hash = JSON.parse(record["payload_json"] || "{}")
    payload_hash.merge(
      JOB_APP_NAME => record["_app_name"],
      JOB_DIR_NAME => record["_app_dir_name"],
      HEADER_SCRIPT_LOCATION => record["_script_location"],
      HEADER_SCRIPT_NAME => record["_script_name"],
      # Keep this legacy fallback because some jobs may not have a resolved
      # scheduler-side job name yet when the record is first created.
      JOB_NAME => record["_job_name"].to_s.empty? ? payload_hash[HEADER_JOB_NAME] : record["_job_name"],
      JOB_PARTITION => record["_partition"],
      JOB_SUBMISSION_TIME => record["_submission_time"],
      JOB_STATUS_ID => record["_status"]
    )
  end

  # Parse payload_json and merge it back with dedicated columns using internal key names.
  def job_record_to_internal_hash(record)
    return nil unless record

    payload_hash = JSON.parse(record["payload_json"] || "{}")
    payload_hash.merge(
      "_job_id" => record["_job_id"],
      "_app_name" => record["_app_name"],
      "_app_dir_name" => record["_app_dir_name"],
      "_script_location" => record["_script_location"],
      "_script_name" => record["_script_name"],
      "_job_name" => record["_job_name"],
      "_partition" => record["_partition"],
      "_submission_time" => record["_submission_time"],
      "_updated_time" => record["_updated_time"],
      "_status" => record["_status"]
    )
  end

  # Mark jobs canceled from the History page as completed in the local history.
  def mark_jobs_as_canceled(db, job_ids)
    Array(job_ids).each do |job_id|
      record = find_job(db, job_id)
      next unless record

      existing = job_record_to_internal_hash(record)
      scheduler_data = {
        "_status" => JOB_STATUS["completed"],
        "_updated_time" => Time.now.iso8601
      }

      upsert_job(
        db,
        build_job_record(
          existing: existing,
          submit_data: nil,
          scheduler_data: scheduler_data
        )
      )
    end
  end

  # Update the status of all jobs that are not completed
  def update_status(conf, scheduler, bin, bin_overrides, ssh_wrapper, cluster_name)
    db = open_history_db(conf, cluster_name)
    queried_ids = get_unfinished_job_ids(db)
    return nil if queried_ids.empty?

    scheduler     = cluster_name ? scheduler[cluster_name]     : scheduler
    ssh_wrapper   = cluster_name ? ssh_wrapper[cluster_name]   : ssh_wrapper
    bin           = cluster_name ? bin[cluster_name]           : bin
    bin_overrides = cluster_name ? bin_overrides[cluster_name] : bin_overrides
    ENV['SGE_ROOT'] ||= cluster_name ? conf["sge_root"][cluster_name] : conf["sge_root"]

    status, error_msg = scheduler.query(queried_ids, bin, bin_overrides, ssh_wrapper)
    return error_msg if error_msg

    db.transaction do
      status.each do |id, info|
        record = find_job(db, id)
        next unless record

        existing = job_record_to_internal_hash(record)
        scheduler_data = (info || {}).transform_keys(&:to_s)
        scheduler_data["_status"] = scheduler_data[JOB_STATUS_ID.to_s]
        scheduler_data["_script_location"] = scheduler_data[HEADER_SCRIPT_LOCATION.to_s]
        scheduler_data["_script_name"] = scheduler_data[HEADER_SCRIPT_NAME.to_s]
        scheduler_data["_job_name"] = scheduler_data[JOB_NAME.to_s]
        scheduler_data["_partition"] = scheduler_data[JOB_PARTITION.to_s]
        scheduler_data["_updated_time"] = Time.now.iso8601
        scheduler_data[JOB_KEYS.to_s] = info.keys

        upsert_job(
          db,
          build_job_record(
            existing: existing,
            submit_data: nil,
            scheduler_data: scheduler_data
          )
        )
      end
    end

    return nil
  end

  # Return all jobs that match the specified statuses and filter.
  def get_all_jobs(conf, cluster_name, statuses, filter, filter_column, date_from, date_to, filter_mode, sort = "", order = "")
    jobs = []
    db = open_history_db(conf, cluster_name)

    selected_statuses = Array(statuses).map(&:to_s)
    filter_text = CGI.unescapeHTML(filter.to_s).downcase
    each_job(db) do |row|
      next if selected_statuses.empty?
      next unless selected_statuses.any? { |status| row["_status"] == JOB_STATUS[status] }
      next unless history_date_range_matches?(row["_submission_time"], date_from, date_to)
      next unless history_filter_mode_matches?(history_filter_target_text(row, filter_column), filter_text, filter_mode)

      info = { JOB_ID => row["_job_id"] }.merge(job_record_to_legacy_hash(row))
      jobs << info
    end

    jobs.sort_by! { |job| history_sort_key(job, sort) }
    jobs.reverse! if order == "desc"

    return jobs
  end

  # Return one page of jobs and the matching row count.
  def get_jobs_page(conf, cluster_name, statuses, filter, filter_column, date_from, date_to, filter_mode, sort, order, limit, offset)
    db = open_history_db(conf, cluster_name)

    if history_use_sql_fast_path?(filter, sort)
      total_count = count_history_jobs(db, statuses, date_from, date_to)
      rows = total_count.zero? ? [] : fetch_history_jobs_page(db, statuses, date_from, date_to, sort, order, limit, offset)
      jobs = rows.map { |row| { JOB_ID => row["_job_id"] }.merge(job_record_to_legacy_hash(row)) }
      return [jobs, total_count]
    end

    all_jobs = get_all_jobs(conf, cluster_name, statuses, filter, filter_column, date_from, date_to, filter_mode, sort, order)
    jobs = offset >= all_jobs.size ? [] : all_jobs[offset, limit] || []
    [jobs, all_jobs.size]
  end

  # Output a styled status badge for a job based on its current status.
  def output_status(job_status)
    badge_class, status_text = case job_status
                               when JOB_STATUS["queued"]
                                 ["bg-warning text-dark", "Queued"]
                               when JOB_STATUS["running"]
                                 ["bg-primary", "Running"]
                               when JOB_STATUS["completed"]
                                 ["bg-secondary", "Completed"]
                               when JOB_STATUS["failed"]
                                 ["bg-danger", "Failed"]
                               else
                                 ["bg-info", "Unknown"]
                               end

    "<span class=\"badge fs-6 #{badge_class}\">#{status_text}</span>\n"
  end

  # Return the value for the cell with the filter highlighted.
  def output_text(text, filter)
    terms = history_filter_terms(filter)

    text = if text.nil? || terms.empty?
             escape_html(text)
           else
             # If it is not replaced after escape, the replacement tag will be escaped.
             highlighted_text = escape_html(text)
             terms.uniq.sort_by { |term| -term.length }.each do |term|
               highlighted_text = highlighted_text.gsub(/(#{Regexp.escape(term)})/i, '<span class="bg-warning text-dark">\1</span>')
             end
             highlighted_text
           end

    return text.gsub("\n", "<br>")
  end

  # Format values for the History table without changing stored data.
  def format_history_table_value(key, value)
    return value unless key == JOB_SUBMISSION_TIME

    Time.parse(value.to_s).strftime("%Y-%m-%d %H:%M:%S")
  rescue ArgumentError
    value
  end

  # Return whether the Job Details modal contains a filter hit.
  def job_details_modal_matches_filter?(job, filter)
    return false if job[JOB_KEYS].nil?

    filtered_keys = job[JOB_KEYS] - [JOB_NAME, JOB_PARTITION, JOB_STATUS_ID]
    filtered_keys.any? do |key|
      history_filter_hits_text?(key, filter) || history_filter_hits_text?(job[key], filter)
    end
  end

  # Return whether the Job Script modal contains a filter hit.
  def job_script_modal_matches_filter?(job, filter)
    history_filter_hits_text?(job[OC_SCRIPT_CONTENT], filter)
  end
end
