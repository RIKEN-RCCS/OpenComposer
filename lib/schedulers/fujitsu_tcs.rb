require 'open3'
require 'csv'

class Fujitsu_tcs < Scheduler
  # Submit a job to the Fujitsu TCS scheduler using the 'pjsub' command.
  # If the submission is successful, it checks for job details using the 'pjstat' command.
  def submit(script_path, job_name = nil, added_options = nil, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil, copy_environment = nil)
    pjsub = get_command_path("pjsub", bin, bin_overrides)
    job_name_option = "-N #{job_name}" if job_name && !job_name.empty?
    command = [ssh_wrapper, pjsub, job_name_option, added_options, script_path].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout, stderr].join(" ") unless status.success?
    return nil, "Job ID not found in output." unless stdout.match?(/Job (\d+) submitted/)

    job_id = stdout.match(/Job (\d+) submitted/)[1]
    pjstat = get_command_path("pjstat", bin, bin_overrides)
    command = [ssh_wrapper, pjstat, "-E --data --choose=jid,jmdl", job_id].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout, stderr].join(" ") unless status.success?

    # Example 1 : stdout of single job
    # ---
    # H,JOB_ID,MD
    # ,34704010,NM

    # Example 2 : stdout of array job
    # ---
    # H,JOB_ID,MD
    # ,34703955,BU
    # ,34703955[1],BU
    # ,34703955[2],BU
    # ,34703955[3],BU
    # ,34703955[4],BU

    # Parse the pjstat output to determine whether it's a single job or an array job
    rows = CSV.parse(stdout)
    if rows.last[2] == "BU" # Array Job
      return rows[1..-1].map { |row| row[1] }, nil
    else
      return rows[1][1], nil # Single Job
    end
  rescue Exception => e
    return nil, e.message
  end

  # Cancel one or more jobs in the Fujitsu TCS scheduler using the 'pjdel' command.
  def cancel(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    pjdel = get_command_path("pjdel", bin, bin_overrides)
    command = [ssh_wrapper, pjdel, jobs.join(" ")].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return status.success? ? nil : stderr
  rescue Exception => e
    return e.message
  end

  def valid_job_id?(id)
    id.to_s.match?(/\A\d+\z/) || id.to_s.match?(/\A\d+\[\d+\]\z/)
  end

  def state_to_oc_status(state)
    case state.to_s
    when "RNP", "RUN", "RNE", "RNO"             then JOB_STATUS["running"]
    when "ACC", "QUE", "RNA", "SPP", "SPD",
         "RSM", "HLD"                            then JOB_STATUS["queued"]
    when "EXT"                                   then JOB_STATUS["completed"]
    when "CCL"                                   then JOB_STATUS["cancelled"]
    when "RJT", "ERR"                            then JOB_STATUS["failed"]
    else                                              JOB_STATUS["unknown"]
    end
  end

  # Fetch all jobs from pjstat (active + historical) in the sacct_all_jobs format.
  # Historical window is the maximum pjstat supports: 365 days.
  def sacct_all_jobs(date_from, date_to, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    pjstat   = get_command_path("pjstat", bin, bin_overrides)
    choose   = "--choose=jid,jnam,rscg,st,adt,std,stde"
    command1 = [ssh_wrapper, pjstat, "-s -E --data", choose].compact.join(" ")
    stdout1, stderr1, status1 = capture_scheduler_command(scheduler_env, command1)
    return nil, [stdout1, stderr1].join(" ").strip, command1 unless status1.success?

    command2 = command1 + " -H day=365"
    stdout2, stderr2, status2 = capture_scheduler_command(scheduler_env, command2)
    return nil, [stdout2, stderr2].join(" ").strip, command2 unless status2.success?

    jobs = {}
    [stdout1, stdout2].each do |stdout|
      CSV.new(stdout, headers: true).to_a.map(&:fields).each do |f|
        job_id = f[1]
        next if job_id.nil? || jobs.key?(job_id)
        jobs[job_id] = {
          "JobID"     => job_id,
          "JobName"   => f[2],
          "Partition" => f[3],
          "State"     => f[4],
          "Submit"    => f[5],
          "StdOut"    => f[6].to_s.strip,
          "StdErr"    => f[7].to_s.strip
        }
      end
    end

    [jobs.values, nil, command1]
  rescue Exception => e
    return nil, e.message, nil
  end

  # Fetch resource-group availability from pjstat -A --data and return it in the sinfo_nodes format.
  # Fujitsu TCS manages resources at the group level; each resource group appears as a "node".
  def sinfo_nodes(bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    pjstat  = get_command_path("pjstat", bin, bin_overrides)
    command = [ssh_wrapper, pjstat, "-A --data"].compact.join(" ")
    stdout, stderr, status = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout, stderr].join(" ").strip, command unless status.success?

    rows = []
    CSV.new(stdout, headers: true).each do |row|
      fields = row.fields
      next if fields.compact.empty?
      # Column order from pjstat -A --data (site-dependent; adjust indices if needed):
      # H, RSC_GRP, AVST, MND_TOT, MND_USE, MND_FRE, CPU_TOT, CPU_USE, CPU_FRE, MEM_TOT, MEM_USE, MEM_FRE
      rscg     = fields[1].to_s.strip
      avst     = fields[2].to_s.strip.downcase  # "up" / "down" / etc.
      cpu_tot  = fields[6].to_i
      cpu_use  = fields[7].to_i
      cpu_fre  = fields[8].to_i
      mem_tot  = (fields[9].to_f  * 1_024).to_i  # GB → MB
      mem_use  = (fields[10].to_f * 1_024).to_i
      mem_fre  = (fields[11].to_f * 1_024).to_i

      next if rscg.empty?
      state    = avst == "up" ? (cpu_use >= cpu_tot ? "allocated" : (cpu_use > 0 ? "mixed" : "idle")) : avst
      cpus_str = "#{cpu_use}/#{[cpu_fre, 0].max}/0/#{cpu_tot}"
      rows << [rscg, state, cpus_str, mem_tot.to_s, mem_fre.to_s, "", ""]
    end

    [rows, nil, command]
  rescue Exception => e
    return nil, e.message, nil
  end

  # Query the status of one or more jobs in the Fujitsu TCS system using 'pjstat'.
  # It retrieves job details and combines information for both active and completed jobs.
  def query(jobs, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    # j2ul-2549-01z0.pdf
    # -s: Display additional items (e.g. edt)
    # -E: Display subjob
    # --data: Display in CSV format
    # --choose: Display only the specified items
    fields = {
      jid:     "Job ID/sub-Job ID",
      jnam:    "Job name",
      jtyp:    "Job type",
      jmdl:    "Job model",
      rnum:    "Retry count",
      snum:    "Number of sub jobs",
      usr:     "Name of user executing job",
      grp:     "Name of group executing job",
      rscu:    "Resource unit",
      rscg:    "Resource group",
      pri:     "Job priority",
      sh:      "Shell path name",
      cmt:     "Comment",
      lst:     "Previous processing state of job",
      st:      "Current processing state of job",
      prmdt:   "PRM data collection time (YYYY/MM/DD hh:mm:ss)",
      ec:      "End code of shell script",
      sn:      "Signal number",
      pc:      "PJM code",
      ermsg:   "Error message",
      mail:    "E-mail send flag",
      adr:     "E-mail send destination address",
      sde:     "Step job dependency relational expression",
      mask:    "umask value of user submitting job",
      std:     "Path name of the standard output file",
      stde:    "Path name of the standard error output file",
      infop:   "Statistical information file path",
      adt:     "Job submission time (MM/DD hh:mm:ss)",
      qdt:     "Last queuing time",
      exc:     "EXIT/CANCEL state transition time",
      lhusr:   "Last hold user name",
      holnm:   "Hold count",
      thldtm:  "Accumulated hold time",
      sdt:     "Job execution start time",
      edt:     "Job execution end time",
      nnumr:   "Node shapes and count at job submission (N : X x Y x Z or N : X x Y or N)",
      cnumr:   "Requested number of CPUs",
      elpl:    "Elapsed time limit or maximum value of elapsed time limit (hhhh:mm:ss)",
      mszl:    "Physical memory amount limit by node",
      pcl:     "CPU usage time limit (sec) by process",
      pcfl:    "Core file limit by process",
      pcpl:    "Max user process count limit by process",
      pdl:     "Data segment limit by process",
      prml:    "Lock memory size limit by process",
      pmql:    "POSIX message queue size limit by process",
      pofl:    "File descriptor limit by process",
      ppsl:    "Signal count limit by process",
      ppl:     "File size limit by process",
      psl:     "Stack segment limit by process",
      pvml:    "Virtual memory size limit by process",
      nnuma:   "Allocated node shape and count (N:XxYxZ or N)",
      msza:    "Physical memory amount allocated to a node",
      cnumat:  "Total number of CPUs allocated",
      elp:     "Execution elapsed t ime (hhhh:mm:ss)",
      nnumv:   "Number of unavailable nodes within the allocated node range",
      nnumu:   "Number of nodes used",
      nidlu:   "Node ID list of the nodes used (hexadecimals delimited by single-byte space)",
      tofulu:  "Tofu coordinate list ((X,Y,Z)) of the nodes used",
      mmszu:   "Total max physical memory usage",
      cnumut:  "Total number of CPUs used",
      uctmut:  "Total user CPU time (ms)",
      sctmut:  "Total system CPU time (ms)",
      usctmut: "Total user CPU time and total of system CPU time (ms)",
      vmszu:   "Maximal amount of virtual memory used"
    }

    pjstat = get_command_path("pjstat", bin, bin_overrides)
    command = [ssh_wrapper, pjstat, "-s -E --data --choose=#{fields.keys.join(",")}", jobs.join(" ")].compact.join(" ")
    stdout1, stderr1, status1 = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout1, stderr1].join(" ") unless status1.success?
    # Example of stdout1 (pjstat -s -E --data --choose=jid,rscg,st 34716159 34716160 34716168 34716168[1] 34716168[2])
    # H,JOB_ID,ACCEPT,RSC_GRP,ST
    # ,34716160,10/11 10:21:35,small,QUE
    # ,34716168,10/11 10:23:03,small,QUE
    # ,34716168[1],10/11 10:23:03,small,QUE
    # ,34716168[2],10/11 10:23:03,small,QUE
    # ---
    # Note that Job 34716159 is not displayed because the job has been completed.

    # Retrieve completed jobs using the same command with '-H' flag
    # Outputs a list of jobs that were completed within the past 365 days, which is the maximum value.
    # If a job was completed before 366 days, it will be displayed as "Queued."
    stdout2, stderr2, status2 = capture_scheduler_command(scheduler_env, command + " -H day=365")
    return nil, [stdout2, stderr2].join(" ") unless status2.success?
    # -H: Display only information about jobs that have completed
    # ---
    # Example of stdout2
    # H,JOB_ID,ACCEPT,RSC_GRP,ST
    # ,34716159,10/11 10:21:31,small,EXT

    info = {}
    csv1 = CSV.new(stdout1, headers: true)
    csv2 = CSV.new(stdout2, headers: true)
    stdout = csv1.to_a.map(&:fields) + csv2.to_a.map(&:fields) # Combine both stdout except headers
    stdout.each do |line|
      # ACC: Job submission has been accepted
      # RJT: Submission has not been accepted
      # QUE: Waiting for job execution
      # RNA: Resources required for job execution are being acquired
      # RNP: Prologue is being executed
      # RUN: Job is being executed
      # RNE: Epilogue is being executed
      # RNO: Waiting for job termination processing to complete
      # SPP: Suspending processing in progress
      # SPD: Already suspended
      # RSM: Resume processing in progress
      # EXT: Job termination processing completed
      # CCL: Ended due to job execution being canceled
      # HLD: Fixed state by user
      # ERR: Fixed state due to error

      job_id = line[fields.keys.index(:jid)+1]
      # Add necessary fields
      info[job_id] = {
        JOB_NAME      => line[fields.keys.index(:jnam)+1],
        JOB_PARTITION => line[fields.keys.index(:rscg)+1],
        JOB_STATUS_ID => case line[fields.keys.index(:st)+1]
                         when "EXT", "CCL"
                           JOB_STATUS["completed"]
                         when "ACC", "QUE", "RNA", "SPP", "SPD", "RSM", "HLD"
                           JOB_STATUS["queued"]
                         when "RNP", "RUN", "RNE", "RNO"
                           JOB_STATUS["running"]
                         when "RJT", "ERR"
                           JOB_STATUS["failed"]
                         else
                           nil
                         end
      }

      # Add other fields
      fields.each_with_index do |(key, value), idx|
        info[job_id][value] = line[idx+1]

        # Post-processing phase:
        # If a job has a non-zero End code and is marked as "completed",
        # we treat it as a failed job and update its status accordingly.
        if key == :ec && line[idx+1] != "0" && info[job_id][JOB_STATUS_ID] == JOB_STATUS["completed"]
          # In the case of a bulk job, the END CODE of the parent job ID will be "-".
          if line[idx+1] != "-"
            info[job_id][JOB_STATUS_ID] = JOB_STATUS["failed"]
          end
        end
      end
    end

    return info, nil
  rescue Exception => e
    return nil, e.message
  end
end
