require 'open3'

# This program was based on the following specifications:
# https://2022.help.altair.com/2022.1.0/AltairGridEngine/AdminsGuideGE.pdf
class Sge < Scheduler
  # Submit a job to Grid Engine using the 'qsub' command.
  def submit(script_path, job_name = nil, added_options = nil, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil, copy_environment = nil)
    qsub = get_command_path("qsub", bin, bin_overrides)
    job_name_option = "-N #{job_name}" if job_name && !job_name.empty?
    command = [ssh_wrapper, qsub, job_name_option, added_options, script_path].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout, stderr].join(" ") unless status.success?

    # For a single job, the output will be "Your job 123 ("a.sh") has been submitted".
    # This returns a string "123".
    if (job_id_match = stdout.match(/^Your job (\d+)/))
      return job_id_match[1], nil
    end

    # For an array job, the output will be "Your job-array 123.1-6:2 ("a.sh") has been submitted".
    # This returns a string list ["123.1", "123.3", "123.5"].
    if (job_id_match = stdout.match(/^Your job-array (\d+)\.(\d+)-(\d+):(\d+)/))
      job_id, start_num, end_num, step_num = job_id_match[1, 4]
      job_ids = (start_num.to_i..end_num.to_i).step(step_num.to_i).map { |num| "#{job_id}.#{num}" }
      return job_ids, nil
    end
    return nil, "Job ID not found in output."
  rescue Exception => e
    return nil, e.message
  end

  # Cancel one or more jobs in Grid Engine using the 'qdel' command.
  def cancel(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    qdel = get_command_path("qdel", bin, bin_overrides)
    transformed_jobs = jobs.map do |job_id|
      job_id.include?(".") ? job_id.gsub(".", " -t ") : job_id # "123.4" -> "123 -t 4"
    end

    command = [ssh_wrapper, qdel, transformed_jobs.join(' ')].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return status.success? ? nil : [stdout, stderr].join(" ")
  rescue Exception => e
    return e.message
  end

  def valid_job_id?(id)
    id.to_s.match?(/\A\d+\z/) || id.to_s.match?(/\A\d+\.\d+\z/)
  end

  def state_to_oc_status(state)
    case state.to_s
    when "r", "t", "Rr"                     then JOB_STATUS["running"]
    when "qw", "h", "d", "s", "S", "T", "Rq" then JOB_STATUS["queued"]
    when "E"                                 then JOB_STATUS["failed"]
    when "completed"                         then JOB_STATUS["completed"]
    when "failed_exit"                       then JOB_STATUS["failed"]
    else                                          JOB_STATUS["unknown"]
    end
  end

  # Fetch all jobs from qstat (active) and qacct (historical) in the sacct_all_jobs format.
  # SGE has no date-range filtering — all available history is returned.
  def sacct_all_jobs(date_from, date_to, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    qstat    = get_command_path("qstat", bin, bin_overrides)
    command1 = [ssh_wrapper, qstat].compact.join(" ")
    stdout1, stderr1, status1 = capture_scheduler_command(scheduler_env, command1)
    return nil, [stdout1, stderr1].join(" ").strip, command1 unless status1.success?

    jobs = {}

    unless stdout1.empty?
      stdout1.lines[2..].each do |line|
        cols = line.gsub(/\s+/, ' ').strip.split(' ')
        next if cols.size < 5

        base_id    = cols[0]
        state      = cols[4]
        name       = cols[2]
        submit     = "#{cols[5]} #{cols[6]}"
        is_running = (state == "r" || state == "t")

        # Running array tasks have an individual task ID in the last column
        if is_running && cols.size >= 10 && cols.last.match?(/\A\d+\z/)
          job_id    = "#{base_id}.#{cols.last}"
          partition = cols[7] || ""
        else
          job_id    = base_id
          partition = is_running ? (cols[7] || "") : ""
        end

        jobs[job_id] ||= {
          "JobID"     => job_id,
          "JobName"   => name,
          "State"     => state,
          "Partition" => partition,
          "Submit"    => submit
        }
      end
    end

    # Append completed jobs from qacct (no day limit — fetch all history)
    qacct    = get_command_path("qacct", bin, bin_overrides)
    command2 = [ssh_wrapper, qacct, "-j"].compact.join(" ")
    stdout2, _stderr2, status2 = capture_scheduler_command(scheduler_env, command2)

    if status2.success?
      stdout2.split(/={10,}/).each do |block|
        parsed = {}
        block.lines.each do |line|
          key, value = line.strip.split(' ', 2)
          next unless key && value
          parsed[key] = value.strip
        end
        base_id = parsed["jobnumber"]
        next unless base_id
        task_id = parsed["taskid"]
        job_id  = (task_id && task_id != "undefined") ? "#{base_id}.#{task_id}" : base_id
        next if jobs.key?(job_id)
        raw_state = (parsed["exit_status"] && parsed["exit_status"] != "0") ? "failed_exit" : "completed"
        # stdout/stderr paths use "host:path" format; strip the host prefix
        jobs[job_id] = {
          "JobID"     => job_id,
          "JobName"   => parsed["jobname"] || "",
          "State"     => raw_state,
          "Partition" => parsed["qname"] || "",
          "Submit"    => parsed["qsub_time"] || "",
          "StdOut"    => parsed["stdout_path_list"].to_s.sub(/\A[^:]+:/, ''),
          "StdErr"    => parsed["stderr_path_list"].to_s.sub(/\A[^:]+:/, '')
        }
      end
    end

    [jobs.values, nil, command1]
  rescue Exception => e
    return nil, e.message, nil
  end

  # Fetch node information from qhost and return it in the sinfo_nodes format.
  def sinfo_nodes(bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    qhost   = get_command_path("qhost", bin, bin_overrides)
    command = [ssh_wrapper, qhost].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    nodes = []
    stdout.each_line do |line|
      line = line.chomp
      next if line =~ /\AHOSTNAME/i || line =~ /\A-{5}/ || line =~ /\Aglobal\s/i
      parts = line.split
      next if parts.size < 9
      hostname = parts[0]
      ncpu_s   = parts[2]
      load_s   = parts[6]
      memtot_s = parts[7]
      memuse_s = parts[8]

      if load_s == "-" || ncpu_s == "-"
        state    = "down"
        used_cpu = 0
        idle_cpu = 0
        total_cpu = ncpu_s == "-" ? 0 : ncpu_s.to_i
      else
        total_cpu = ncpu_s.to_i
        load      = load_s.to_f
        used_cpu  = [load.ceil, total_cpu].min
        idle_cpu  = [total_cpu - used_cpu, 0].max
        state     = used_cpu >= total_cpu ? "allocated" : (used_cpu > 0 ? "mixed" : "idle")
      end

      cpus_str     = "#{used_cpu}/#{idle_cpu}/0/#{total_cpu}"
      total_mem_mb = sge_mem_to_mb(memtot_s)
      used_mem_mb  = sge_mem_to_mb(memuse_s)
      free_mem_mb  = [total_mem_mb - used_mem_mb, 0].max

      nodes << [hostname, state, cpus_str, total_mem_mb.to_s, free_mem_mb.to_s, "", ""]
    end

    [nodes, nil, command]
  rescue Exception => e
    return nil, e.message, nil
  end

  # Return Job Name, Job Partition, Job Status ID.
  def get_job_info(columns)
    job_name = columns[2]
    job_status_key = if columns[4] == "E"
                       "failed"
                     elsif columns[4] == "r" || columns[4] == "t"
                       "running"
                     else
                       "queued"
                     end
    job_status_id = JOB_STATUS[job_status_key]
    job_partition = job_status_id == JOB_STATUS["running"] ? columns[7] : "" # At the time of queued, the partition is undecided.
    [job_name, job_partition, job_status_id]
  end

  # Parses a block of job information extracted from the qacct output.
  def parse_block(block)
    key_map = { "jobname" => JOB_NAME, "qname" => JOB_PARTITION }
    block.lines.each_with_object({}) do |line, info|
      key, value = line.strip.split(' ', 2)
      next unless key && value

      key = key_map[key] || key
      info[key] = value
    end
  end

  # Query the status of one or more jobs in Grid Engine using 'qstat'.
  # It retrieves job details such as submission time, partition, and status.
  def query(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    # r  : Running
    # qw : Waiting
    # h  : Holding
    # d  : Deleting
    # t  : Transferring: The job has been scheduled and is being transferred to the execution host.
    # s  : Suspended, Paused
    # S  : Suspended, Queue Suspended
    # T  : Suspended, Suspended Due to Exceeding Limit
    # E  : Error
    # Rq : Rescheduled and Waiting Job
    # Rr : Rescheduled and Running Job

    #
    # Example of output of qstat
    #
    # Queued of Array Job
    # job-ID  prior   name user    state submit/start at    queue  jclass  slots ja-task-ID
    # -------------------------------------------------------------------------------------
    # 3111179 0.00000 a.sh uy04992    qw 02/08/2025 13:54:33                        4 1-5:2

    # Running of Array Job 1
    # job-ID  prior   name user    state submit/start at    queue  jclass  slots ja-task-ID
    # -------------------------------------------------------------------------------------
    # 3111179 0.55207 a.sh uy04992     r 02/08/2025 13:54:36 all.q@r20n2                4 1
    # 3111179 0.55207 a.sh uy04992     r 02/08/2025 13:54:36 all.q@r21n4                4 3
    # 3111179 0.55207 a.sh uy04992     r 02/08/2025 13:54:36 all.q@r17n10               4 5

    # Running of Array Job 2
    # job-ID  prior   name user    state submit/start at    queue  jclass  slots ja-task-ID
    # -------------------------------------------------------------------------------------
    # 3114550 0.55207 a.sh uy04992     t 02/08/2025 15:26:23 prior@r13n9               80 1
    # 3114550 0.55207 a.sh uy04992     t 02/08/2025 15:26:23 prior@r13n9               80 2
    # 3114550 0.00000 a.sh uy04992    qw 02/08/2025 15:26:21                      80 3-10:1

    # Queued of Single Job
    # job-ID  prior   name user    state submit/start at    queue  jclass  slots ja-task-ID
    # -------------------------------------------------------------------------------------
    # 3111614 0.00000 a.sh uy04992    qw 02/08/2025 13:59:58                            4

    # Running of Single Job
    # job-ID  prior   name user    state submit/start at    queue  jclass  slots ja-task-ID
    # -------------------------------------------------------------------------------------
    # 3111614 0.55207 a.sh uy04992     r 02/08/2025 14:00:02 all.q@r20n2                4

    qstat = get_command_path("qstat", bin, bin_overrides)
    command = [ssh_wrapper, qstat].compact.join(" ")
    stdout1, stderr1, status1 = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout1, stderr1].join(" ") unless status1.success?

    info = {}
    if !stdout1.empty?
      formatted_stdout1 = stdout1.lines[2..].map { |line| line.gsub(/\s+/, ' ').strip }.join("\n")
      #
      # 3151406 0.55207 job.sh uy04992 r 02/09/2025 16:58:13 all.q@r23n3 4
      #

      jobs.each do |job_id|
        # Determine if the job is an array job or a single job
        base_id, task_id = job_id.include?(".") ? job_id.split('.') : [job_id, nil]

        # Process each line of the qstat output
        formatted_stdout1.each_line do |line|
          columns = line.split(/\s+/)
          next unless columns[0] == base_id

          # Get job information
          job_name, job_partition, job_status_id = get_job_info(columns)

          # Handle array job task matching or single job processing
          if task_id # array job
            if (job_status_id == JOB_STATUS["running"] && columns[-1] == task_id) || job_status_id == JOB_STATUS["queued"]
              info[job_id] = {
                JOB_NAME => job_name,
                JOB_PARTITION => job_partition,
                JOB_STATUS_ID => job_status_id
              }
            end
          else # single job
            info[job_id] = {
              JOB_NAME => job_name,
              JOB_PARTITION => job_partition,
              JOB_STATUS_ID => job_status_id
            }
          end
        end
      end
    end

    remaining_jobs = jobs.reject { |id| info.key?(id) }
    return info, nil if remaining_jobs.empty?

    # Retrieve completed jobs using to Grid Engine using the 'qacct' command.
    # Updates the information of specified jobs that were completed within the past week from today.
    # If the job was completed more than a week ago, only the status is set to JOB_STATUS["completed"].
    qacct = get_command_path("qacct", bin, bin_overrides)
    command = [ssh_wrapper, qacct, "-j -d 7"].compact.join(" ")
    stdout2, stderr2, status2 = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout2, stderr2].join(" ") unless status2.success?

    # To deal with the case where stdout2 is too large, temporarily save it to a tmpfile.
    Tempfile.create("qacct_output") do |tmpfile|
      tmpfile.write(stdout2)
      tmpfile.rewind
      job_blocks = tmpfile.read.split("==============================================================")

      remaining_jobs.each do |job_id|
        # For now, set the status to "Unknown".
        info[job_id] = { JOB_STATUS_ID => nil }

        # Determine if the job is an array job or a single job
        base_id, task_id = job_id.include?(".") ? job_id.split('.') : [job_id, nil]
        job_blocks.each do |block|
          # Check if the block contains the jobnumber
          if task_id # array job
            if block.match?(/jobnumber\s+#{base_id}/) && block.match?(/taskid\s+#{task_id}/)
              info[job_id] = { JOB_STATUS_ID => JOB_STATUS["completed"] }.merge(parse_block(block))
            end
          else # single job
            if block.match?(/jobnumber\s+#{base_id}/)
              info[job_id] = { JOB_STATUS_ID => JOB_STATUS["completed"] }.merge(parse_block(block))
            end
          end
        end
      end

      remaining_jobs.each do |job_id|
        exit_status = info[job_id]["exit_status"]
        status = info[job_id][JOB_STATUS_ID]

        # Post-processing phase:
        # If a job has a non-zero exit_status and is marked as "completed",
        # we treat it as a failed job and update its status accordingly.
        if exit_status && exit_status != "0" && status == JOB_STATUS["completed"]
          info[job_id][JOB_STATUS_ID] = JOB_STATUS["failed"]
        end
      end

    end
    return info, nil
  rescue Exception => e
    return nil, e.message
  end

  private

  def sge_mem_to_mb(mem_str)
    return 0 if mem_str.nil? || mem_str == "-"
    m = mem_str.match(/\A([\d.]+)\s*([TGMK]?)\z/i)
    return 0 unless m
    val  = m[1].to_f
    unit = m[2].upcase
    case unit
    when 'T' then (val * 1_048_576).to_i
    when 'G' then (val * 1_024).to_i
    when 'M' then val.to_i
    when 'K' then (val / 1_024).to_i
    else          val.to_i
    end
  end
end
