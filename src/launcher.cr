# xr-launcher — universal OpenXRay game launcher/installer.
#
# Library entry point (also the headless CLI). The GUI lives in
# launcher_gui.cr and is the only file that pulls in egui-cr, so specs
# and the CLI compile without the native UI backend.

require "option_parser"
require "./launcher/catalog"
require "./launcher/i18n"
require "./launcher/single_instance"
require "./launcher/paths"
require "./launcher/store"
require "./launcher/engine"
require "./launcher/installer"
require "./launcher/uninstaller"
require "./launcher/runner"
require "./launcher/log_analyzer"

module Launcher
  VERSION = "1.0.0"

  def self.printer(stream : IO = STDOUT) : String -> Nil
    ->(line : String) { stream.puts(line); stream.flush }
  end

  # Writer commands must not race a running GUI instance (last writer
  # wins on the config) — grab the single-instance lock first.
  private def self.guard_single_instance : Nil
    SingleInstance.acquire!
  rescue SingleInstance::AlreadyRunning
    abort(L.t("errors.already_running"))
  end

  def self.cli(args : Array(String)) : Int32
    Locale.init(Store.load.locale)
    log = printer
    command = args[0]? || "gui"

    case command
    when "list"
      store = Store.load
      if store.installs.empty?
        puts L.t("cli.no_installs")
      else
        store.installs.each do |i|
          game = Catalog[i.game]
          puts "#{game.id}\t#{i.path}\t#{i.created_at}\t#{game.title}"
        end
      end
      0
    when "install"
      guard_single_instance
      game_id = args[1]? || abort("usage: xr-launcher install <soc|cs|cop> --engine DIR --source DIR --dir DIR")
      game = Catalog[game_id]? || abort(L.t("errors.unknown_game", game: game_id))
      engine = source = target = ""
      OptionParser.parse(args[2..]) do |parser|
        parser.on("--engine DIR", "OpenXRay folder (checkout or prefix)") { |v| engine = v }
        parser.on("--source DIR", "original game install folder") { |v| source = v }
        parser.on("--dir DIR", "target folder for the new distribution") { |v| target = v }
        parser.invalid_option { |opt| abort("unknown option #{opt}") }
      end
      abort("missing --engine") if engine.empty?
      abort("missing --source") if source.empty?
      abort("missing --dir") if target.empty?
      begin
        Installer.install(game, source, engine, target, Store.load, &log)
      rescue ex : InstallError
        abort(ex.message)
      end
      0
    when "run"
      path = args[1]? || abort("usage: xr-launcher run <install-dir|game-id>")
      store = Store.load
      install = store.find_by_path(File.expand_path(path)) ||
                store.for_game(path).first? ||
                abort("no install matching #{path}")
      # the install's stored play-button mode applies to CLI launches too
      args = install.launch_mode == "lastsave" ? [Runner::LASTSAVE_FLAG] : [] of String
      Runner.run(install, args)
      puts L.t("cli.launched", path: install.path)
      0
    when "remove"
      guard_single_instance
      path = args[1]? || abort("usage: xr-launcher remove <install-dir>")
      Uninstaller.remove(File.expand_path(path), Store.load, &log)
      0
    when "help", "--help", "-h"
      puts USAGE
      0
    else
      STDERR.puts USAGE
      2
    end
  end

  USAGE = <<-TEXT
    xr-launcher — assemble and run S.T.A.L.K.E.R. distributions on OpenXRay

    usage:
      xr-launcher                start the GUI (same as `gui`)
      xr-launcher list           list registered installs
      xr-launcher install <soc|cs|cop> --engine DIR --source DIR --dir DIR
      xr-launcher run <install-dir|game-id>
      xr-launcher remove <install-dir>

    The install never copies or modifies the original game: game data is
    symlinked in place, only fsgame.ltx / openxray.ltx / small script
    overlays are written into the new folder.
    TEXT
end
