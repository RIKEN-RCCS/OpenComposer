require 'open3'

class Pbspro < Scheduler
  # Submit a job to PBS using the 'qsub' command.
  def submit(script_path, job_name = nil, added_options = nil, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil, copy_environment = nil)
    qsub = get_command_path("qsub", bin, bin_overrides)
    job_name_option = "-N #{job_name}" if job_name && !job_name.empty?
    command = [ssh_wrapper, qsub, job_name_option, added_options, script_path].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout, stderr].join(" ") unless status.success?

    # For a normal job, the output will be "123.opbs".
    if (job_id_match = stdout.match(/^(\d+)\..+$/))
      return job_id_match[1], nil
    end

    # For an array job, the output will be "123[].opbs".
    if (job_id_match = stdout.match(/^(\d+)\[\]\..+$/))
      qstat = get_command_path("qstat", bin, bin_overrides)
      command = [ssh_wrapper, qstat, "-t", "#{job_id_match[1]}[]"].compact.join(" ") # "-t" option also shows array jobs.
      stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
      return nil, [stdout, stderr].join(" ") unless status.success?

      job_ids = stdout.lines.map do |line|
        first_column = line.split(/\s+/).first
        first_column if first_column&.match?(/^\d+\[\d+\]$/)
      end.compact

      return job_ids, nil
    else
      return nil, "Job ID not found in output."
    end
  rescue Exception => e
    return nil, e.message
  end

  # Cancel one or more jobs in PBS using the 'qdel' command.
  def cancel(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    qdel = get_command_path("qdel", bin, bin_overrides)
    command = [ssh_wrapper, qdel, jobs.join(' ')].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return status.success? ? nil : [stdout, stderr].join(" ")
  rescue Exception => e
    return e.message
  end

  # Save the results of qstat to the info hash array
  def parse_qstat_output(output, info)
    cur_id = nil
    output.each_line do |line|
      case line
      when /Job Id:\s*(\d+)(\[\d+\])?\..+$/
        base_id = $1
        index = $2 || ""
        cur_id = "#{base_id}#{index}"
        info[cur_id] ||= {}
      when /^\s*([^=\s]+)\s*=\s*(.+)$/
        key, value = $1.strip, $2.strip

        case key
        when "Job_Name"
          info[cur_id][JOB_NAME] = value
        when "queue"
          info[cur_id][JOB_PARTITION] = value
        when "job_state"
          info[cur_id][JOB_STATUS_ID] = case value
                                        when "E", "X", "F"                     then JOB_STATUS["completed"]
                                        when "H", "M", "Q", "S", "T", "U", "W" then JOB_STATUS["queued"]
                                        when "B", "R"                          then JOB_STATUS["running"]
                                        # then JOB_STATUS["failed"] # Job status does not indicate whether it has failed or not
                                        else nil
                                        end
        else
          info[cur_id][key] = value
        end
      end
    end

    # Post-processing phase:
    # If a job has a non-zero Exit_status and is marked as "completed",
    # we treat it as a failed job and update its status accordingly.
    # This is necessary because PBS's "F" (finished) state does not
    # distinguish success from failure.
    info.each do |job_id, data|
      exit_status = data["Exit_status"]
      status      = data[JOB_STATUS_ID]

      if exit_status && exit_status != "0" && status == JOB_STATUS["completed"]
        data[JOB_STATUS_ID] = JOB_STATUS["failed"]
      end
    end
  end

  def valid_job_id?(id)
    id.to_s.match?(/\A\d+\z/) || id.to_s.match?(/\A\d+\[\d+\]\z/)
  end

  def state_to_oc_status(state)
    case state.to_s
    when "B", "R"                           then JOB_STATUS["running"]
    when "H", "M", "Q", "S", "T", "U", "W" then JOB_STATUS["queued"]
    when "E", "X", "F"                      then JOB_STATUS["completed"]
    when "F_FAILED"                         then JOB_STATUS["failed"]
    else                                         JOB_STATUS["unknown"]
    end
  end

  # Fetch all jobs from qstat and return them in the sacct_all_jobs format.
  # PBS has no date-range filtering, so all available jobs are returned.
  def sacct_all_jobs(date_from, date_to, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    qstat   = get_command_path("qstat", bin, bin_overrides)
    command = [ssh_wrapper, qstat, "-f -t -x"].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    jobs    = []
    cur_id  = nil
    cur_job = {}

    stdout.each_line do |line|
      case line
      when /Job Id:\s*(\d+)(\[\d+\])?\..+$/
        jobs << cur_job.merge("JobID" => cur_id) if cur_id
        cur_id  = "#{$1}#{$2 || ""}"
        cur_job = {}
      when /^\s*([^=\s]+)\s*=\s*(.+)$/
        key, value = $1.strip, $2.strip
        case key
        when "Job_Name"    then cur_job["JobName"]   = value
        when "queue"       then cur_job["Partition"]  = value
        when "job_state"   then cur_job["State"]      = value
        when "ctime"       then cur_job["Submit"]     = value
        when "start_time"  then cur_job["Start"]      = value
        when "comp_time"   then cur_job["End"]        = value
        when "Exit_status" then cur_job["ExitCode"]   = value
        # Output_Path and Error_Path use "host:path" format; strip the host prefix
        when "Output_Path" then cur_job["StdOut"] = value.sub(/\A[^:]+:/, '')
        when "Error_Path"  then cur_job["StdErr"] = value.sub(/\A[^:]+:/, '')
        end
      end
    end
    jobs << cur_job.merge("JobID" => cur_id) if cur_id

    # Mark jobs with non-zero exit status as failed
    jobs.each do |j|
      if j["State"] == "F" && j["ExitCode"] && j["ExitCode"] != "0"
        j["State"] = "F_FAILED"
      end
    end

    [jobs.reject { |j| j["JobID"].nil? }, nil, command]
  rescue Exception => e
    return nil, e.message, nil
  end

  # Fetch node information from pbsnodes -av and return it in the sinfo_nodes format.
  def sinfo_nodes(bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    pbsnodes = get_command_path("pbsnodes", bin, bin_overrides)
    command  = [ssh_wrapper, pbsnodes, "-av"].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    nodes     = []
    cur_name  = nil
    cur_attrs = {}

    stdout.each_line do |line|
      line = line.chomp
      if line =~ /\A\S/
        nodes << build_pbs_node_row(cur_name, cur_attrs) if cur_name
        cur_name  = line.strip
        cur_attrs = {}
      elsif line =~ /\A\s+(\S+)\s*=\s*(.+)\z/
        cur_attrs[$1.strip] = $2.strip
      end
    end
    nodes << build_pbs_node_row(cur_name, cur_attrs) if cur_name

    [nodes.compact, nil, command]
  rescue Exception => e
    return nil, e.message, nil
  end

  # Query the status of one or more jobs in PBS using 'qstat'.
  # It retrieves job details such as submission time, partition, and status.
  def query(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    # http://nusc.nsu.ru/wiki/lib/exe/fetch.php/doc/pbs/pbsprorefguide13.0.pdf
    # B : Job arrays only: job array is begun
    # E : Job is exiting after having run
    # F : Job is finished. Job has completed execution, job failed during execution, or job was canceled.
    # H : Job is held. A job is put into a held state by the server or by a user or administrator. A job stays in a held state
    #     until it is released by a user or administrator.
    # M : Job was moved to another server
    # Q : Job is queued, eligible to run or be routed
    # R : Job is running
    # S : Job is suspended by server. A job is put into the suspended state when a higher priority job needs the resources.
    # T : Job is in transition (being moved to a new location)
    # U : Job is suspended due to workstation becoming busy
    # W : Job is waiting for its requested execution time to be reached or job specified a stagein request which failed for some reason.
    # X : Subjobs only; subjob is finished (expired.)

    qstat = get_command_path("qstat", bin, bin_overrides)

    info = {}
    # Try to get info for both running and completed jobs
    # command = [ssh_wrapper, qstat, "-f -t -x", jobs.join(" ")].compact.join(" ")
    command = [ssh_wrapper, qstat, "-f -t -x"].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout, stderr].join(" ") unless status.success?

    parse_qstat_output(stdout, info)
    return info, nil
  rescue Exception => e
    return nil, e.message
  end

  private

  def build_pbs_node_row(name, attrs)
    return nil if name.nil?
    state     = attrs["state"] || "unknown"
    total_cpu = (attrs["resources_available.ncpus"] || attrs["pcpus"] || "0").to_i
    used_cpu  = (attrs["resources_assigned.ncpus"]  || "0").to_i
    idle_cpu  = [total_cpu - used_cpu, 0].max
    cpus_str  = "#{used_cpu}/#{idle_cpu}/0/#{total_cpu}"
    total_mem_mb = pbs_mem_to_mb(attrs["resources_available.mem"] || "0")
    used_mem_mb  = pbs_mem_to_mb(attrs["resources_assigned.mem"]  || "0")
    free_mem_mb  = [total_mem_mb - used_mem_mb, 0].max
    gpu_total = (attrs["resources_available.ngpus"] || "0").to_i
    gpu_used  = (attrs["resources_assigned.ngpus"]  || "0").to_i
    gres      = gpu_total > 0 ? "gpu:#{gpu_total}" : ""
    gres_used = gpu_used  > 0 ? "gpu:#{gpu_used}"  : ""
    [name, state, cpus_str, total_mem_mb.to_s, free_mem_mb.to_s, gres, gres_used]
  end

  def pbs_mem_to_mb(mem_str)
    return 0 if mem_str.nil? || mem_str.empty?
    m = mem_str.match(/\A([\d.]+)\s*([tTgGmMkK]?)[bB]?\z/)
    return 0 unless m
    val  = m[1].to_f
    unit = m[2].downcase
    case unit
    when 't' then (val * 1_048_576).to_i
    when 'g' then (val * 1_024).to_i
    when 'm' then val.to_i
    when 'k' then (val / 1_024).to_i
    else          val.to_i
    end
  end
end
