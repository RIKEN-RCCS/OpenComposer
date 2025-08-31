# The Miyabi Supercomputer at the University of Tokyo uses PBS Pro. Because it uses
# special options for qstat, only the query() function is overridden from the PBS Pro class.

require 'open3'
require './lib/schedulers/pbspro'

class Miyabi < Pbspro
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

    # Try to get info for running jobs 
    command = [ssh_wrapper, qstat, "-f -t", jobs.join(" ")].compact.join(" ")
    stdout1, stderr1, status1 = Open3.capture3(command)
    return nil, [stdout1, stderr1].join(" ") unless status1.success?

    info = {}
    parse_qstat_output(stdout1, info)
    remaining_jobs = jobs.reject { |id| info.key?(id) }
    return info, nil if remaining_jobs.empty?

    # Try to get info for completed jobs ("-H" and "--hday" are Miyabi-specific options.)
    command = [ssh_wrapper, qstat, "-f -t -H --hday 7", remaining_jobs.join(" ")].compact.join(" ")
    stdout2, stderr2, status2 = Open3.capture3(command)
    return nil, [stdout2, stderr2].join(" ") unless status2.success?
  
    parse_qstat_output(stdout2, info)
    return info, nil
  rescue Exception => e
    return nil, e.message
  end
end
