helpers do
  # Generate HTML for icons linking to related applications.
  def output_related_app_icon(job_apps_path, apps)
    return [] if apps.nil?
    
    apps.map do |app|
      if app.is_a?(Hash)
        # Extract key and value from the hash
        key, value = app.first
        href = "#{@my_ood_url}/pun/sys/dashboard/apps/show/#{key}"
        is_bi_or_fa_icon, icon_path = get_icon_path(job_apps_path, value)
        
        # Generate icon HTML based on whether it's a Bootstrap/Font Awesome icon or an image
        icon_html = if is_bi_or_fa_icon
                      "<i class=\"#{value} fs-5\"></i>"
                    else
                      "<img width=20 title=\"#{key}\" alt=\"#{key}\" src=\"#{icon_path}\">"
                    end
      else
        # Handle cases where app is not a hash (direct app name)
        key = app
        href = "#{@my_ood_url}/pun/sys/dashboard/apps/show/#{key}"
        icon_html = "<img width=20 title=\"#{key}\" alt=\"#{key}\" src=\"#{@my_ood_url}/pun/sys/dashboard/apps/icon/#{key}/sys/sys\">"
      end
      
      # Return the full HTML string for the link
      "<a style=\"color: black; text-decoration: none;\" target=\"_blank\" href=\"#{href}\">\n  #{icon_html}\n</a>\n"
    end
  end

  # Output a modal for a specific action (e.g., CancelJob or DeleteInfo).
  def output_action_modal(action)
    id = "_history#{action}"
    form_action = "#{@script_name}/history"
    query_params = []
    query_params << "cluster=#{@cluster_name}" if @cluster_name
    query_params << "rows=#{@rows}" if @rows != HISTORY_ROWS
    query_params << "p=#{@current_page}" if @current_page != 1
    form_action += "?#{query_params.join('&')}" unless query_params.empty?

    <<~HTML
    <div class="modal" id="#{id}" aria-hidden="true" tabindex="-1">
      <div class="modal-dialog">
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

  # Output a modal for displaying details of a specific job.
  def output_job_id_modal(job, filter)
    return if job[JOB_KEYS].nil? # If a job has just been submitted, it may not have been registered yet.

    modal_id = "_historyJobId#{job[JOB_ID]}"
    html = <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1">
      <div class="modal-dialog">
        <div class="modal-content">
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
    job_link = "#{@script_name}#{job[JOB_APP_PATH]}?jobId=#{URI.encode_www_form_component(job[JOB_ID])}"
    job_link += "&cluster=#{@cluster_name}" if @cluster_name

    <<~HTML
    <div class="modal" aria-hidden="true" id="#{modal_id}" tabindex="-1">
      <div class="modal-dialog">
        <div class="modal-content">
          <div class="modal-header">
            <h5>Job Script</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body">
            #{output_text(job[SCRIPT_CONTENT], filter)}
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
      link = "./history?status=#{@status}&p=#{i}&rows=#{@rows}"
      link += "&cluster=#{@cluster_name}" if @cluster_name
      link += "&filter=#{@filter}" if @filter && !@filter.empty?
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
      previous_link = "./history?status=#{@status}&p=#{current_page-1}&rows=#{@rows}"
      previous_link += "&cluster=#{@cluster_name}" if @cluster_name
      previous_link += "&filter=#{@filter}" if @filter && !@filter.empty?
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
      next_link = "./history?status=#{@status}&p=#{current_page+1}&rows=#{@rows}"
      next_link += "&cluster=#{@cluster_name}" if @cluster_name
      next_link += "&filter=#{@filter}" if @filter && !@filter.empty?
      html += "   <li class=\"page-item\"><a href=\"#{next_link}\" class=\"page-link\">&raquo;</a></li>\n"
    end
    
    html += "  </ul>\n"
    html += "</nav>\n"
  end

  # Return history DB
  def get_history_db(conf, cluster_name)
    db = conf["history_db"]
    return db unless db.is_a?(Hash)

    cluster_db = db[cluster_name]
    halt 500, "#{cluster_name} is invalid." unless cluster_db
    
    return cluster_db
  end

  # Update the status of all jobs that are not completed
  def update_status(conf, scheduler, bin, bin_overrides, ssh_wrapper, cluster_name)
    queried_ids = []
    db = PStore.new(get_history_db(conf, cluster_name))
    db.transaction(true) do
      db.roots.each do |id|
        queried_ids << id if db[id][JOB_STATUS_ID] != JOB_STATUS["completed"]
      end
    end
    return nil if queried_ids.empty?

    scheduler     = cluster_name ? scheduler[cluster_name]     : scheduler
    bin           = cluster_name ? bin[cluster_name]           : bin
    bin_overrides = cluster_name ? bin_overrides[cluster_name] : bin_overrides
    ENV['SGE_ROOT'] ||= cluster_name ? conf["sge_root"][cluster_name] : conf["sge_root"]

    status, error_msg = scheduler.query(queried_ids, bin, bin_overrides, ssh_wrapper)
    return error_msg if error_msg

    db.transaction do
      status.each do |id, info|
        data = db[id]
        next unless data
        data[JOB_KEYS] = info.keys
        db[id] = data.merge(info)
      end
    end

    return nil
  end
  
  # Return all jobs that match the specified status and filter.
  def get_all_jobs(conf, cluster_name, status, filter)
    jobs = []
    db = PStore.new(get_history_db(conf, cluster_name))
    db.transaction(true) do
      db.roots.each do |id|
        data = db[id]
        next if status && status != "all" && data && data[JOB_STATUS_ID] != JOB_STATUS[status]

        info = { JOB_ID => id }.merge(data)
        if filter && !filter.empty?
          filtered_keys = info[JOB_KEYS] - [JOB_NAME, JOB_PARTITION, JOB_STATUS_ID]
          fields_to_search = [
            info[JOB_ID],
            filtered_keys,
            info[JOB_APP_NAME],
            info[HEADER_SCRIPT_LOCATION],
            info[HEADER_SCRIPT_NAME],
            info[SCRIPT_CONTENT],
            info[JOB_NAME],
            info[JOB_PARTITION],
            info[JOB_SUBMISSION_TIME]
          ]
          filtered_keys.each do |key|
            fields_to_search << info[key]
          end
          next unless fields_to_search.any? { |v| v.to_s.include?(CGI.unescapeHTML(filter)) }
        end

        jobs << info
      end
    end

    return jobs.reverse
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
                               else
                                 ["bg-danger", "Unknown"]
                               end
    
    "<span class=\"badge fs-6 #{badge_class}\">#{status_text}</span>\n"
  end

  # Return the value for the cell with the filter highlighted.
  def output_text(text, filter)
    text = if text.nil? || filter.nil? || filter.empty?
             escape_html(text)
           else
             # If it is not replaced after escape, the replacement tag will be escaped.
             escape_html(text).gsub(/(#{Regexp.escape(filter)})/i, '<span class="bg-warning text-dark">\1</span>')
           end
    
    return text.gsub("\n", "<br>")
  end
end
