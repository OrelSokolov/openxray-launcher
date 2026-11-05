# Launch a distribution: start bin/xr_3da with the install root as the
# working directory (portable mode — the engine finds fsgame.ltx in the
# cwd) and the per-game mode flag. The engine process is fully detached:
# closing the launcher does not close the game.
#
# The last launched pid is parked in _appdata_/launcher.pid so the GUI
# can tell whether the game is still running — also across launcher
# restarts and CLI launches (both go through .run).

require "./catalog"
require "./i18n"
require "./store"
require "./engine"

module Launcher
  module Runner
    PID_FILE = "launcher.pid"

    # Play-button "last save" mode: the engine skips the main menu and
    # loads the most recent save right away (see plans/LASTSAVE_LOAD.md
    # in the engine tree; the check is a substring, so -lastsave works).
    LASTSAVE_FLAG = "-lastsave"

    def self.run(install : Store::Install,
                 extra_args : Array(String) = [] of String) : Process
      game = Catalog[install.game]
      exe = File.join(install.path, "bin", Engine.executable_name)
      raise InstallError.new(L.t("errors.exe_missing", exe: exe)) unless File.exists?(exe)

      Dir.mkdir_p(File.join(install.path, "_appdata_", "logs"))
      log_path = File.join(install.path, "_appdata_", "logs", "launcher.log")
      log = File.open(log_path, "a")
      log.puts("#{Time.local.to_rfc3339} launching #{game.title} (#{game.mode_flag}) from #{install.path}")
      log.flush

      process = Process.new(
        exe,
        [game.mode_flag] + extra_args,
        chdir: install.path,
        input: Process::Redirect::Close,
        output: log,
        error: log
      )
      log.close # the child owns its dup of the fd; ours would leak
      write_pid(install, process.pid)
      process
    end

    # The pid parked by the last launch, or nil when nothing ran (yet)
    # or the file is unreadable. Deliberately no exe matching: a reused
    # pid is rare and the worst case is one wrong button label.
    def self.running_pid(install : Store::Install) : Int64?
      path = pid_path(install)
      return nil unless File.file?(path)
      pid = File.read(path).strip.to_i64?
      pid if pid && pid > 0
    rescue File::Error
      nil
    end

    def self.running?(install : Store::Install) : Bool
      pid = running_pid(install)
      return false unless pid
      return false unless pid_alive?(pid)
      true
    end

    def self.write_pid(install : Store::Install, pid : Int64) : Nil
      path = pid_path(install)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, pid)
    end

    # Drop the parked pid (e.g. the game exited while we watched).
    def self.clear_pid(install : Store::Install) : Nil
      File.delete?(pid_path(install))
    end

    private def self.pid_path(install : Store::Install) : String
      File.join(install.path, "_appdata_", PID_FILE)
    end

    # Zero-signal probe: checks existence without touching the process.
    private def self.pid_alive?(pid : Int64) : Bool
      {% if flag?(:win32) %}
        # No kill(pid, 0) on Windows: tasklist's PID filter is the
        # cheap equivalent (no output rows when the pid is gone).
        output = Process.run("tasklist", ["/FI", "PID eq #{pid}", "/FO", "CSV", "/NH"],
          output: :pipe) do |proc|
          proc.output.gets_to_end
        end
        output.includes?(",\"#{pid}\",")
      {% else %}
        LibC.kill(pid, 0) == 0
      {% end %}
    end
  end
end
