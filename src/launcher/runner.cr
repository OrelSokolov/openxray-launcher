# Launch a distribution: start bin/xr_3da with the install root as the
# working directory (portable mode — the engine finds fsgame.ltx in the
# cwd) and the per-game mode flag. The engine process is fully detached:
# closing the launcher does not close the game.

require "./catalog"
require "./i18n"
require "./store"
require "./engine"

module Launcher
  module Runner
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

      Process.new(
        exe,
        [game.mode_flag] + extra_args,
        chdir: install.path,
        input: Process::Redirect::Close,
        output: log,
        error: log
      )
    end
  end
end
