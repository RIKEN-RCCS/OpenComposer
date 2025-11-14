require 'open3'

class Pbspro < Scheduler
  # Submit a job to PBS using the 'qsub' command.
  def submit(script_path, job_name = nil, added_options = nil, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    qsub = get_command_path("qsub", bin, bin_overrides)
    job_name_option = "-N #{job_name}" if job_name && !job_name.empty?
    command = [ssh_wrapper, qsub, job_name_option, added_options, script_path].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ") unless status.success?

    # For a normal job, the output will be "123.opbs".
    if (job_id_match = stdout.match(/^(\d+)\..+$/))
      return job_id_match[1], nil
    end

    # For an array job, the output will be "123[].opbs".
    if (job_id_match = stdout.match(/^(\d+)\[\]\..+$/))
      qstat = get_command_path("qstat", bin, bin_overrides)
      command = [ssh_wrapper, qstat, "-t", "#{job_id_match[1]}[]"].compact.join(" ") # "-t" option also shows array jobs.
      stdout, stderr, status = Open3.capture3(command)
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
  def cancel(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
    qdel = get_command_path("qdel", bin, bin_overrides)
    command = [ssh_wrapper, qdel, jobs.join(' ')].compact.join(" ")
    stdout, stderr, status = Open3.capture3(command)
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
  
  # Query the status of one or more jobs in PBS using 'qstat'.
  # It retrieves job details such as submission time, partition, and status.
  def query(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil)
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
    stdout, stderr, status = Open3.capture3(command)
    return nil, [stdout, stderr].join(" ") unless status.success?
  
    parse_qstat_output(stdout, info)
    return info, nil
  rescue Exception => e
    return nil, e.message
  end
end
