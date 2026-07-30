# coding: utf-8
require 'open3'
require 'date'
require 'json'

class Slurm < Scheduler
  SLURM_ENV = "SLURM_TIME_FORMAT=standard"
  # Submit a job to the Slurm scheduler using the 'sbatch' command.
  # If the submission is successful, it checks for job details using the 'scontrol' command.
  def submit(script_path, job_name = nil, added_options = nil, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil, copy_environment = nil)
    sbatch = get_command_path("sbatch", bin, bin_overrides)
    job_name_option = "-J #{job_name}" if job_name && !job_name.empty?
    added_options = (copy_environment ? "--export=ALL" : "--export=NONE") if added_options.nil?
    command = [ssh_wrapper, sbatch, job_name_option, added_options, script_path].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    stdout = to_utf8(stdout)
    return nil, [stdout, stderr].join(" ") unless status.success?
    job_id_match = stdout.match(/Submitted batch job (\d+)/)
    return nil, "Job ID not found in output." unless job_id_match

    job_id = job_id_match[1]

    # Fetch job details
    scontrol = get_command_path("scontrol", bin, bin_overrides)
    command = [ssh_wrapper, scontrol, "show job", job_id].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    stdout = to_utf8(stdout)
    return nil, [stdout, stderr].join(" ") unless status.success?

    unless stdout.include?("ArrayTaskId") # Single Job
      return job_id, nil
    else
      # Extract and expand array job IDs.
      # ArrayTaskId can be "1-100", "1-1000:40", "1-1000:40%2" (% = concurrency limit), or "1,5,10".
      expanded_ids = stdout.scan(/ArrayTaskId=(\S+)/).flatten.flat_map do |spec|
        spec.split('%').first.split(',').flat_map do |part|
          if part.include?('-')
            range_part, step_part = part.split(':', 2)
            start_val, end_val = range_part.split('-', 2).map(&:to_i)
            step = step_part ? [step_part.to_i, 1].max : 1
            start_val.step(end_val, step).to_a
          else
            [part.to_i]
          end
        end
      end.sort
      return expanded_ids.map { |i| "#{job_id}_#{i}" }, nil # Array Job
    end
  rescue Exception => e
    return nil, e.message
  end

  # Cancel one or more jobs in the Slurm scheduler using the 'scancel' command.
  # Range IDs like "6801262_[1494-2000]" are passed directly to scancel, which
  # understands Slurm's native bracket notation.
  def cancel(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    scancel = get_command_path("scancel", bin, bin_overrides)
    errors  = []
    jobs.each do |id|
      id = id.gsub(/\[([^\]]+)\]/) { "[#{$1.gsub(/[:%]\d+/, '')}]" }
      command = [ssh_wrapper, scancel, id].compact.join(" ")
      stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
      stdout = to_utf8(stdout)
      errors << [stdout, stderr].join(" ").strip unless status.success?
    end
    errors.empty? ? nil : errors.join("; ")
  rescue Exception => e
    return e.message
  end

  # Query the status of one or more jobs in the Slurm system using 'sacct'.
  # It retrieves job details such as submission time, partition, and status.
  def query(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    # https://slurm.schedmd.com/sacct.html
    # BOOT_FAIL     : Job terminated due to launch failure, typically due to a hardware failure.
    # CANCELLED     : Job was explicitly cancelled by the user or system administrator. The job may or may not have been initiated.
    # COMPLETED     : Job has terminated all processes on all nodes with an exit code of zero.
    # DEADLINE      : Job terminated on deadline.
    # FAILED        : Job terminated with non-zero exit code or other failure condition.
    # NODE_FAIL     : Job terminated due to failure of one or more allocated nodes.
    # OUT_OF_MEMORY : Job experienced out of memory error.
    # PENDING       : Job is awaiting resource allocation.
    # PREEMPTED     : Job terminated due to preemption.
    # RUNNING       : Job currently has an allocation.
    # REQUEUED      : Job was requeued.
    # RESIZING      : Job is about to change size.
    # REVOKED       : Sibling was removed from cluster due to other cluster starting the job.
    # SUSPENDED     : Job has an allocation, but execution has been suspended and CPUs have been released for other jobs.
    # TIMEOUT       : Job terminated upon reaching its time limit.
    #
    # The categorization was determined based on the table above and the codes below.
    #  - https://github.com/OSC/ood_core/blob/master/lib/ood_core/job/adapters/slurm.rb

    # Get the list of all available fields from sacct
    sacct = get_command_path("sacct", bin, bin_overrides)
    command1 = [ssh_wrapper, SLURM_ENV, sacct, "--helpformat"].compact.join(" ")
    stdout1, stderr1, status1 = capture_scheduler_command(scheduler_env, command1)
    stdout1 = to_utf8(stdout1)
    return nil, [stdout1, stderr1].join(" ") unless status1.success?

    # Run sacct with all fields, using --parsable2 for clean pipe-separated output
    command2 = [ssh_wrapper, SLURM_ENV, sacct, "--format=#{stdout1.split.join(",")} --parsable2 -j", jobs.join(",")].compact.join(" ")
    stdout2, stderr2, status2 = capture_scheduler_command(scheduler_env, command2)
    stdout2 = to_utf8(stdout2)
    return nil, [stdout2, stderr2].join(" ") unless status2.success?

    lines = stdout2.lines.map(&:chomp)
    header = lines.shift.split('|')
    info = {}
    lines.each do |line|
      job_fields = line.split('|')
      id = job_fields[header.index("JobID")]
      next if id.end_with?(".batch", ".extern")

      # Add necessary fields
      if job_fields.size != stdout1.split.size
      # Some information may not be obtained when `sacct` command runs immediately after submitting a job.
        info[id] = {
          JOB_NAME      => nil,
          JOB_PARTITION => nil,
          JOB_STATUS_ID => nil
        }
      else
        job_state = job_fields[header.index("State")]
        info[id] = {
          JOB_NAME      => job_fields[header.index("JobName")],
          JOB_PARTITION => job_fields[header.index("Partition")],
          JOB_STATUS_ID =>
          # When a job is canceled, the output is "CANCELLED by 1025".
          if job_state.start_with?("CANCELLED")
            JOB_STATUS["cancelled"]
          else
            case job_state
            when "COMPLETED"
              JOB_STATUS["completed"]
            when "CONFIGURING", "REQUEUED", "RESIZING", "PENDING", "PREEMPTED", "SUSPENDED"
              JOB_STATUS["queued"]
            when "COMPLETING", "RUNNING"
              JOB_STATUS["running"]
            when "STOPPED"
              JOB_STATUS["cancelled"]
            when "BOOT_FAIL", "DEADLINE", "FAILED", "NODE_FAIL", "OUT_OF_MEMORY", "REVOKED", "SPECIAL_EXIT", "TIMEOUT"
              JOB_STATUS["failed"]
            else
              nil
            end
          end
        }
      end

      # Add other fields
      header.each_with_index do |field, idx|
        value = job_fields[idx]
        next if value.nil? || value.strip.empty?
        info[id][field] = value
      end
    end

    return info, nil
  rescue Exception => e
    return nil, e.message
  end

  # Run scontrol show job --json for one job ID.
  # Returns [hash, nil, command] on success, [nil, nil, nil] when the job is not found,
  # or [nil, error_message, command] on failure.
  def scontrol_job(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    scontrol = get_command_path("scontrol", bin, bin_overrides)
    command  = [ssh_wrapper, scontrol, "show job", job_id, "--json"].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    stdout = to_utf8(stdout)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    parsed = JSON.parse(stdout)
    job = parsed.dig("jobs", 0)
    return nil, nil, command if job.nil?

    # Flatten the JSON object into a display-ready string hash.
    # Scalars are used as-is; arrays are joined; nested hashes become k=v pairs.
    result = {}
    job.each do |k, v|
      result[k] = case v
                  when String, Integer, Float, TrueClass, FalseClass then v.to_s
                  when NilClass then ""
                  when Array    then v.map(&:to_s).join(", ")
                  when Hash     then v.map { |hk, hv| "#{hk}=#{hv}" }.join(", ")
                  else v.to_s
                  end
    end

    # Aliases expected by the consuming code in run.rb
    result["Command"] = result["command"]  if result.key?("command")
    result["WorkDir"] = result["work_dir"] if result.key?("work_dir")

    result.empty? ? [nil, nil, command] : [result, nil, command]
  rescue JSON::ParserError => e
    return nil, "scontrol JSON parse error: #{e.message}", command
  rescue Exception => e
    return nil, e.message, nil
  end

  # Fetch all available sacct fields for a single job (for the Job Details modal).
  # Uses -X so only the top-level allocation row is returned (no step sub-rows).
  # Key fields are placed first in the format string so they are always in the
  # earliest columns and unaffected if a later field's value contains a pipe character.
  # Returns [hash, nil, command] on success or [nil, error_message, command] on failure.
  def sacct_job(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    sacct = get_command_path("sacct", bin, bin_overrides)

    help_cmd = [ssh_wrapper, sacct, "--helpformat"].compact.join(" ")
    help_out, help_err, help_status = capture_scheduler_command(scheduler_env, help_cmd)
    help_out = to_utf8(help_out)
    return nil, "sacct --helpformat failed: #{[help_out, help_err].join(' ').strip}", nil unless help_status.success?

    available = help_out.split
    return nil, "sacct --helpformat returned no fields", nil if available.empty?

    # Preferred display order. Fields not available in this Slurm version are silently dropped.
    # Free-text fields that can embed pipe characters are intentionally excluded.
    ordered = %w[
      WorkDir JobID JobIDRaw JobName State Partition Account User NodeList
      AllocCPUS AllocTRES ReqMem Start End Submit Elapsed ExitCode
      AllocNodes AssocID AveCPU AveCPUFreq AveDiskRead AveDiskWrite AvePages AveRSS AveVMSize
      BlockID Cluster Constraints ConsumedEnergy ConsumedEnergyRaw CPUTime CPUTimeRAW
      DBIndex DerivedExitCode ElapsedRaw Eligible FailedNode Flags GID Group Layout Licenses
      MaxDiskRead MaxDiskReadNode MaxDiskReadTask MaxDiskWrite MaxDiskWriteNode MaxDiskWriteTask
      MaxPages MaxPagesNode MaxPagesTask MaxRSS MaxRSSNode MaxRSSTask
      MaxVMSize MaxVMSizeNode MaxVMSizeTask McsLabel MinCPU MinCPUNode MinCPUTask
      NCPUS NNodes NTasks Planned PlannedCPU PlannedCPURAW Priority QOS QOSRAW QOSREQ
      Reason ReqCPUFreq ReqCPUFreqGov ReqCPUFreqMax ReqCPUFreqMin ReqCPUS ReqNodes ReqTRES
      Reservation ReservationId ReqReservation Restarts SegmentSize SLUID
      StdErr StdIn StdOut Suspended SystemCPU Timelimit TimelimitRaw TotalCPU
      TRESUsageInAve TRESUsageInMax TRESUsageInMaxNode TRESUsageInMaxTask
      TRESUsageInMin TRESUsageInMinNode TRESUsageInMinTask TRESUsageInTot
      TRESUsageOutAve TRESUsageOutMax TRESUsageOutMaxNode TRESUsageOutMaxTask
      TRESUsageOutMin TRESUsageOutMinNode TRESUsageOutMinTask TRESUsageOutTot
      UID UserCPU WCKey WCKeyID
    ]
    fields = ordered.select { |f| available.any? { |a| a.casecmp?(f) } }

    command = [ssh_wrapper, SLURM_ENV, sacct, "-j", job_id, "-X",
               "--format=#{fields.join(',')}", "--parsable2"].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    stdout = to_utf8(stdout)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    lines = stdout.lines.map(&:chomp).reject(&:empty?)
    return nil, nil, command if lines.size < 2

    header   = lines[0].split('|')
    data_row = lines[1]
    return nil, nil, command unless data_row

    result = {}
    data_row.split('|').each_with_index do |value, idx|
      key = header[idx]
      next unless key
      result[key] = value
    end
    result.empty? ? [nil, nil, command] : [result, nil, command]
  rescue Exception => e
    return nil, e.message, nil
  end

  # Fetch all jobs for the current user within a date range via sacct.
  # Uses a fixed safe set of fields (no free-text fields that could contain pipe characters).
  # Defaults to the last 7 days when no dates are supplied.
  # Returns [jobs_array, nil, command] or [nil, error_message, command].
  def valid_job_id?(id)
    id.to_s.match?(/\A\d+\z/) || id.to_s.match?(/\A\d+_\d+\z/) || id.to_s.match?(/\A\d+_\[/)
  end

  def state_to_oc_status(state)
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

  def sacct_all_jobs(date_from, date_to, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    sacct = get_command_path("sacct", bin, bin_overrides)

    help_cmd = [ssh_wrapper, sacct, "--helpformat"].compact.join(" ")
    help_out, _help_err, help_status = capture_scheduler_command(scheduler_env, help_cmd)
    help_out = to_utf8(help_out)
    available = help_status.success? ? help_out.split : []

    wanted = %w[JobID JobName Partition State Submit Start End Elapsed
                WorkDir Account TotalCPU AllocCPUS ReqMem ExitCode NodeList Stdout Stderr SubmitLine]
    # Use case-insensitive match so Slurm variants (Stdout vs StdOut) are accepted.
    fields = available.empty? ? wanted : wanted.select { |f| available.any? { |a| a.casecmp?(f) } }

    effective_from = date_from.to_s.empty? ? (Date.today - 6).strftime("%Y-%m-%d") : date_from.to_s
    effective_to   = date_to.to_s.empty?   ? Date.today.strftime("%Y-%m-%d")       : date_to.to_s

    command = [ssh_wrapper, SLURM_ENV, sacct, "-X", "--parsable2",
               "--format=#{fields.join(',')}",
               "--starttime=#{effective_from}",
               "--endtime=#{effective_to}T23:59:59"].compact.join(" ")

    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    stdout = to_utf8(stdout)
    lines = stdout.lines.map(&:chomp).reject(&:empty?)
    return [], nil, command if lines.size < 2

    header = lines[0].split('|')
    jobs = []
    lines[1..].each do |line|
      row = {}
      line.split('|').each_with_index do |value, idx|
        key = header[idx]
        next unless key
        row[key] = value
      end
      jobs << row unless row.empty?
    end

    jobs.each do |row|
      # Normalize Slurm's Stdout/Stderr header variants to the keys used throughout the app.
      row["StdOut"] = row.delete("Stdout") if row.key?("Stdout") && !row.key?("StdOut")
      row["StdErr"] = row.delete("Stderr") if row.key?("Stderr") && !row.key?("StdErr")

      # Older Slurm (pre-22.11) doesn't expose StdOut/StdErr as sacct fields.
      # Recover them from the SubmitLine sbatch arguments — sacct always records this.
      if row["StdOut"].to_s.empty? && row["StdErr"].to_s.empty?
        submit_line = row["SubmitLine"].to_s
        out_match = submit_line.match(/(?:--output=|-o\s+)(\S+)/)
        err_match = submit_line.match(/(?:--error=|-e\s+)(\S+)/)
        row["StdOut"] = out_match[1] if out_match
        row["StdErr"] = err_match[1] if err_match
      end

      row["StdOut"] = resolve_slurm_filename_pattern(row["StdOut"], row)
      row["StdErr"] = resolve_slurm_filename_pattern(row["StdErr"], row)
    end

    [jobs, nil, command]
  rescue Exception => e
    return nil, e.message, nil
  end

  # Fetch estimated start times for a list of pending jobs via squeue --start.
  # Returns a hash of job_id => start_time_string for jobs that have an estimate.
  # N/A and blank values are excluded so callers can treat missing keys as unknown.
  def squeue_start_times(job_ids, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    return [{}, nil] if job_ids.empty?

    squeue  = get_command_path("squeue", bin, bin_overrides)
    command = [ssh_wrapper, SLURM_ENV, squeue, "--start", "--noheader", "--parsable2",
               "--Format=jobid,starttime", "-j", job_ids.join(",")].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    stdout = to_utf8(stdout)
    return [{}, [stdout, stderr].join(" ")] unless status.success?

    result = {}
    stdout.lines.each do |line|
      parts = line.chomp.split("|")
      next if parts.size < 2
      job_id     = parts[0].strip
      start_time = parts[1].strip
      next if start_time.empty? || start_time.upcase == "N/A"
      # Normalize to ISO 8601 if squeue didn't honour SLURM_TIME_FORMAT=standard
      # (e.g. some squeue builds return "Jun 01 15:15" by default)
      unless start_time =~ /\A\d{4}-\d{2}-\d{2}T/
        begin
          time_str = start_time =~ /\d{4}/ ? start_time : "#{Date.today.year} #{start_time}"
          start_time = DateTime.parse(time_str.gsub(/\s+/, ' ')).strftime("%Y-%m-%dT%H:%M:%S")
        rescue ArgumentError, TypeError, Date::Error
          # keep as-is if we cannot parse the string
        end
      end
      result[job_id] = start_time
    end
    [result, nil]
  rescue Exception => e
    [{}, e.message]
  end

  # Fetch all currently active (queued/running) jobs for the current user via squeue.
  # Returns entries with the same key names as sacct_all_jobs so they can be merged
  # directly into sacct_map for any job IDs sacct did not report (e.g. freshly queued jobs).
  def squeue_active_jobs(bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    user = ENV['USER'].to_s.strip
    return [[], nil] if user.empty?

    squeue  = get_command_path("squeue", bin, bin_overrides)
    # Use -o short format with @ as the field
    # separator. @ is not a shell metacharacter so it survives SSH wrapping
    # without any quoting, unlike | which gets interpreted as a pipe operator
    # by the remote shell. %i=JOBID %j=NAME %P=PARTITION %T=STATE %V=SUBMIT %S=START
    command = [ssh_wrapper, SLURM_ENV, squeue,
               "--user=#{user}", "--noheader",
               "-o", "%i@%j@%P@%T@%V@%S"].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    stdout = to_utf8(stdout)
    return [[], [stdout, stderr].join(" ").strip] unless status.success?

    jobs = []
    stdout.lines.each do |line|
      parts = line.chomp.split('@', 6)
      next if parts.size < 4
      jobs << {
        "JobID"     => parts[0].to_s.strip,
        "JobName"   => parts[1].to_s.strip,
        "Partition" => parts[2].to_s.strip,
        "State"     => parts[3].to_s.strip,
        "Submit"    => parts[4].to_s.strip,
        "Start"     => parts[5].to_s.strip,
        "End"       => "",
        "StdOut"    => "",
        "StdErr"    => ""
      }
    end
    [jobs, nil]
  rescue Exception => e
    [[], e.message]
  end

  # Fetch node info via sinfo -N with fixed-width columns.
  # Deduplicates by node name (a node appears once per partition in -N output).
  def sinfo_nodes(bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    sinfo   = get_command_path("sinfo", bin, bin_overrides)
    fmt     = "nodelist:10,StateLong:15,cpusState:20,Memory:15,FreeMem:15,Gres:30,GresUsed:30"
    command = [ssh_wrapper, sinfo, "-N", "--Format=#{fmt}"].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    stdout = to_utf8(stdout)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    lines  = stdout.lines.map { |l| l.chomp }
    return [], nil, command if lines.size < 2

    widths = [10, 15, 20, 15, 15, 30, 30]
    seen   = {}
    nodes  = []

    lines[1..].each do |line|
      next if line.strip.empty?
      pos  = 0
      cols = widths.map { |w| v = line[pos, w].to_s.strip; pos += w; v }
      node_name = cols[0]
      next if node_name.empty? || seen.key?(node_name)
      seen[node_name] = true
      nodes << cols
    end

    [nodes, nil, command]
  rescue => e
    return nil, e.message, nil
  end

  # Fetch the batch script for a job via sacct --batch-script (-B).
  # Returns [script_content, nil] or [nil, nil] when not available.
  def batch_script(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    sacct = get_command_path("sacct", bin, bin_overrides)
    command = [ssh_wrapper, SLURM_ENV, sacct, "-j", job_id, "-B"].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    stdout = to_utf8(stdout)
    return nil, nil unless status.success?

    lines = stdout.lines
    return nil, nil unless lines.size >= 2 && lines[0].start_with?("Batch Script for")

    content = lines.drop(2).join
    content.strip.empty? ? [nil, nil] : [content, nil]
  rescue Exception => e
    return nil, e.message
  end

  # Query the current status of specific job IDs via sacct (batched in groups of 100).
  # Returns [hash_of_job_id_to_row, error_or_nil].
  def sacct_status_update(job_ids, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    return {}, nil if job_ids.empty?

    sacct  = get_command_path("sacct", bin, bin_overrides)
    result = {}
    last_error = nil

    job_ids.each_slice(100) do |batch|
      command = [ssh_wrapper, SLURM_ENV, sacct, "-X", "--parsable2",
                 "--format=JobID,JobName,State,Start,End",
                 "-j", batch.join(",")].compact.join(" ")
      stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
      stdout = to_utf8(stdout)
      unless status.success?
        last_error = [stdout, stderr].join(" ").strip
        next
      end

      lines = stdout.lines.map(&:chomp).reject(&:empty?)
      next if lines.size < 2

      header = lines[0].split('|')
      lines[1..].each do |line|
        row = {}
        line.split('|').each_with_index { |v, i| row[header[i]] = v if header[i] }
        next if row.empty?
        jid = row["JobID"].to_s.strip
        next if jid.empty? || jid.end_with?(".batch", ".extern")
        result[jid] = row
      end
    end

    [result, last_error]
  rescue Exception => e
    [{}, e.message]
  end

  # Compute seff-style efficiency metrics using sacct --json.
  def efficiency(job_id, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil, gpu_memory = nil)
    sacct = get_command_path("sacct", bin, bin_overrides)
    cmd   = [ssh_wrapper, sacct, "--json -j", job_id].compact.join(" ")
    out, err, st = capture_scheduler_command(scheduler_env, cmd)
    out = to_utf8(out)
    return [nil, [out, err].join(" ")] unless st.success?

    data      = JSON.parse(out)
    jobs_list = data["jobs"] || []
    return [nil, "Job not found."] if jobs_list.empty?

    job   = jobs_list.first
    state = Array(job.dig("state", "current")).join(" ")
    ncpus = ex_tres_eff(job.dig("tres", "allocated") || [], "cpu", 0).to_i

    if state.include?("RUNNING") || ncpus == 0 || ncpus >= 0xfffffff
      return [{ "status" => "not_available", "state" => state }, nil]
    end

    ncores       = (ncpus + 1) / 2
    walltime     = job.dig("time", "elapsed").to_i
    timelimit    = job.dig("time", "limit", "number").to_i * 60
    reqmem_kb    = ex_tres_eff(job.dig("tres", "allocated") || [], "mem", 0).to_f * 1024

    tot_cpu_msec    = 0.0
    mem_kb          = 0.0
    best_step_total = []
    (job["steps"] || []).each do |step|
      total         = step.dig("tres", "requested", "total") || []
      tot_cpu_msec += ex_tres_eff(total, "cpu", 0).to_f
      lmem          = ex_tres_eff(total, "mem", 0).to_f / 1024
      if lmem > mem_kb
        mem_kb          = lmem
        best_step_total = total
      end
    end

    corewalltime = walltime * ncores
    cpu_eff  = corewalltime > 0 ? (tot_cpu_msec / 1000.0 / corewalltime * 100).round(1) : 0.0
    mem_eff  = reqmem_kb    > 0 ? (mem_kb / reqmem_kb * 100).round(1)                    : 0.0
    wall_eff = timelimit    > 0 ? (walltime.to_f / timelimit * 100).round(1)              : 0.0

    result = {
      "status"    => "available",
      "state"     => state,
      "command"   => cmd,
      "cluster"   => job["cluster"].to_s,
      "cores"     => ncores.to_s,
      "nodes"     => job["allocation_nodes"].to_s,
      "Wall Time" => format("%.1f%%  %s of %s",              wall_eff, time2str_eff(walltime),                       time2str_eff(timelimit)),
      "CPU"       => format("%.1f%%  %s of %s core-walltime", cpu_eff, time2str_eff((tot_cpu_msec / 1000).to_i), time2str_eff(corewalltime)),
      "Memory"    => format("%.1f%%  %s of %s",              mem_eff,  kbytes2str_eff(mem_kb),                      kbytes2str_eff(reqmem_kb)),
    }

    # GPU metrics come from the step with the highest memory usage, not the job-level TRES.
    gpu_util = ex_tres_eff(best_step_total, "gpuutil")
    gpu_mem  = ex_tres_eff(best_step_total, "gpumem") # bytes

    result["GPU Utilization"] = format("%.0f%%", gpu_util) if gpu_util

    if gpu_mem
      allocated = job.dig("tres", "allocated") || []
      alloc_gb  = gpu_memory_total_gb(gpu_memory, job["partition"], allocated)
      gpu_mem_kb = gpu_mem.to_f / 1024
      if alloc_gb > 0
        gpu_mem_eff = (gpu_mem.to_f / (alloc_gb * (1024.0**3)) * 100).round(1)
        result["GPU Memory"] = format("%.1f%%  %s of %d GB", gpu_mem_eff, kbytes2str_eff(gpu_mem_kb), alloc_gb)
      else
        result["GPU Memory"] = kbytes2str_eff(gpu_mem_kb)
      end
    end

    [result, nil]
  rescue JSON::ParserError => e
    [nil, "sacct --json not supported: #{e.message}"]
  rescue Exception => e
    [nil, e.message]
  end

  # Total GPU memory in GB allocated to a job, from the site's normalized
  # gpu_memory map (see normalize_gpu_memory in run.rb). For each configured
  # model, count how many the job holds as "gpu:<model>" and multiply by that
  # model's capacity, preferring a partition-specific entry over "default".
  #
  # Returns 0 when gpu_memory is unset or lists no model the job actually used,
  # which the caller reports as memory used with no percentage. This is
  # deliberate: a wrong denominator would give a confidently wrong percentage.
  def gpu_memory_total_gb(gpu_memory, partition, allocated)
    (gpu_memory || {}).sum do |model, caps|
      count = ex_tres_eff(allocated, "gpu:#{model}", 0).to_i
      next 0 if count.zero?
      count * (caps.is_a?(Hash) ? (caps[partition.to_s] || caps["default"] || 0) : caps).to_i
    end
  end

  def ex_tres_eff(tres_array, name, default = nil, field = "count")
    map = tres_array.each_with_object({}) do |m, h|
      key = m["type"] == "gres" ? m["name"] : m["type"]
      h[key] = m[field]
    end
    map.fetch(name, default)
  end

  def time2str_eff(seconds)
    seconds = seconds.to_i
    minutes, seconds = seconds.divmod(60)
    hours,   minutes = minutes.divmod(60)
    days,    hours   = hours.divmod(24)
    prefix = days > 0 ? "#{days}-" : ""
    prefix + format("%02d:%02d:%02d", hours, minutes, seconds)
  end

  def kbytes2str_eff(kbytes)
    kbytes = kbytes.to_f
    return "0.00 MB" if kbytes == 0
    units = %w[kB MB GB TB PB EB]
    exp   = [Math.log(kbytes.abs) / Math.log(1024), units.size - 1].min.to_i
    format("%.2f %s", kbytes / (1024.0**exp), units[exp])
  end

  private

  # Re-tag a string as binary then encode to UTF-8, dropping any invalid bytes.
  # Needed because Open3.capture3 returns strings tagged with the process's
  # external encoding (US-ASCII when LANG=C), and sacct output can contain
  # non-ASCII bytes in job names or paths.
  def to_utf8(str)
    str.to_s.b.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  end

  # Resolve Slurm filename pattern substitutions in a StdOut/StdErr path.
  # Handles the patterns defined in https://slurm.schedmd.com/sbatch.html#SECTION_FILENAME-PATTERN
  def resolve_slurm_filename_pattern(path, row)
    path = path.to_s.strip
    return path if path.empty? || path == "None"

    job_id = row["JobID"].to_s.strip
    # Array jobs: sacct returns "MASTER_INDEX" (e.g. "123_1")
    if job_id =~ /\A(\d+)_(\d+)\z/
      array_master = $1
      array_index  = $2
      plain_id     = array_master
    else
      plain_id     = job_id.split('.').first.to_s
      array_master = plain_id
      array_index  = "0"
    end

    username   = ENV['USER'] || ENV['LOGNAME'] || ""
    workdir    = row["WorkDir"].to_s.strip
    job_name   = row["JobName"].to_s.strip
    # NodeList may be comma-separated or use bracket notation (e.g. "node[001-003]")
    first_node = row["NodeList"].to_s.strip
                   .split(',').first.to_s
                   .sub(/\[(\d+)[^\]]*\]/) { $1 }
                   .strip

    resolved = path
      .gsub('%%', "\x00")    # protect literal %% before other substitutions
      .gsub('%A', array_master)
      .gsub('%a', array_index)
      .gsub('%J', job_id)
      .gsub('%j', plain_id)
      .gsub('%N', first_node)
      .gsub('%u', username)
      .gsub('%x', job_name)
      .gsub('%W', workdir)
      .gsub('%Z', workdir)
      .gsub("\x00", '%')     # restore literal %

    # Slurm stores relative paths as-is; resolve against WorkDir so the
    # full absolute path is available for file links and existence checks.
    resolved.start_with?('/') ? resolved : File.join(workdir, resolved)
  end

  # Expand a bracket-range job ID into individual task IDs.
  # "6801262_[1494-2000]"   → ["6801262_1494", ..., "6801262_2000"]
  # "6801262_[1494-2000:2]" → ["6801262_1494", "6801262_1496", ..., "6801262_2000"]
  # Any other string is returned unchanged inside a one-element array.
  def expand_array_range(job_id)
    m = job_id.to_s.match(/\A(\d+)_\[(\d+)-(\d+)(?::(\d+))?\]\z/)
    return [job_id] unless m
    parent = m[1]
    first  = m[2].to_i
    last   = m[3].to_i
    step   = m[4] ? [m[4].to_i, 1].max : 1
    first.step(last, step).map { |i| "#{parent}_#{i}" }
  end
end
