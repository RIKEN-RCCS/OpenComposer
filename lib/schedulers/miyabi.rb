# The Miyabi Supercomputer at the University of Tokyo uses PBS Pro. Because it uses
# special options for qstat, the query() and sacct_all_jobs() functions are overridden
# from the PBS Pro class; every other method is inherited unchanged.

require 'open3'
require './lib/schedulers/pbspro'

class Miyabi < Pbspro
  # Miyabi uses qstat -H --hday for history instead of the generic PBS -x flag.
  def sacct_all_jobs(date_from, date_to, bin = nil, bin_overrides = nil, ssh_wrapper = nil, scheduler_env = nil)
    qstat    = get_command_path("qstat", bin, bin_overrides)
    command1 = [ssh_wrapper, qstat, "-f -t"].compact.join(" ")
    stdout1, stderr1, status1 = capture_scheduler_command(scheduler_env, command1)
    return nil, [stdout1, stderr1].join(" ").strip, command1 unless status1.success?

    command2 = [ssh_wrapper, qstat, "-f -t -H --hday 7"].compact.join(" ")
    stdout2, stderr2, status2 = capture_scheduler_command(scheduler_env, command2)
    return nil, [stdout2, stderr2].join(" ").strip, command2 unless status2.success?

    jobs    = []
    cur_id  = nil
    cur_job = {}

    [stdout1, stdout2].each do |stdout|
      stdout.each_line do |line|
        case line
        when /Job Id:\s*(\d+)(\[\d+\])?\..+$/
          jobs << cur_job.merge("JobID" => cur_id) if cur_id
          cur_id  = "#{$1}#{$2 || ""}"
          cur_job = {}
        when /^\s*([^=\s]+)\s*=\s*(.+)$/
          key, value = $1.strip, $2.strip
          case key
          when "Job_Name"    then cur_job["JobName"]  = value
          when "queue"       then cur_job["Partition"] = value
          when "job_state"   then cur_job["State"]     = value
          when "ctime"       then cur_job["Submit"]    = value
          when "start_time"  then cur_job["Start"]     = value
          when "comp_time"   then cur_job["End"]       = value
          when "Exit_status" then cur_job["ExitCode"]  = value
          when "Output_Path" then cur_job["StdOut"] = value.sub(/\A[^:]+:/, '')
          when "Error_Path"  then cur_job["StdErr"] = value.sub(/\A[^:]+:/, '')
          end
        end
      end
    end
    jobs << cur_job.merge("JobID" => cur_id) if cur_id

    jobs.each do |j|
      j["State"] = "F_FAILED" if j["State"] == "F" && j["ExitCode"] && j["ExitCode"] != "0"
    end

    seen = {}
    unique_jobs = jobs.reject { |j| j["JobID"].nil? || seen.key?(j["JobID"]).tap { seen[j["JobID"]] = true } }
    [unique_jobs, nil, command1]
  rescue Exception => e
    return nil, e.message, nil
  end

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

    # Try to get info for running jobs
    command = [ssh_wrapper, qstat, "-f -t", jobs.join(" ")].compact.join(" ")
    stdout1, stderr1, status1 = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout1, stderr1].join(" ") unless status1.success?

    info = {}
    parse_qstat_output(stdout1, info)
    remaining_jobs = jobs.reject { |id| info.key?(id) }
    return info, nil if remaining_jobs.empty?

    # Try to get info for completed jobs ("-H" and "--hday" are Miyabi-specific options.)
    command = [ssh_wrapper, qstat, "-f -t -H --hday 7", remaining_jobs.join(" ")].compact.join(" ")
    stdout2, stderr2, status2 = capture_scheduler_command(scheduler_env, command)
    return nil, [stdout2, stderr2].join(" ") unless status2.success?

    parse_qstat_output(stdout2, info)
    return info, nil
  rescue Exception => e
    return nil, e.message
  end
end
