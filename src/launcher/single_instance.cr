# Single-instance guard: an exclusive flock on `<config_dir>/lock`,
# held for the process lifetime. A second launcher instance (the classic
# source of stale-writer config wipes: an old window still open while a
# new one runs) refuses to start instead of racing it.
#
# The kernel releases the lock automatically when the process dies —
# SIGKILL included — so no stale-lock recovery is ever needed.

module Launcher
  module SingleInstance
    class AlreadyRunning < Exception
    end

    @@lock_file : File?

    # Try to grab the single-instance lock. Non-blocking: raises
    # AlreadyRunning when another launcher holds it. NOTE:
    # `flock_exclusive` returns Nil on success and raises IO::Error
    # when the lock is held — there is no false to branch on.
    def self.acquire! : Nil
      path = File.join(Paths.config_dir, "lock")
      file = File.open(path, "a+")
      begin
        file.flock_exclusive(blocking: false)
        @@lock_file = file # keep the fd open for the process lifetime
      rescue IO::Error # lock held by another instance
        file.close
        raise AlreadyRunning.new
      end
    end

    def self.release : Nil
      @@lock_file.try &.close
      @@lock_file = nil
    end
  end
end
