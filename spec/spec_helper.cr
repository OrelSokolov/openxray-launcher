require "spec"
require "file_utils"
require "../src/launcher"

# Redirect the config dir for the WHOLE spec process, before any
# example runs: Installer/Uninstaller auto-persist their store through
# `Store#save`'s default path (`Paths.store_path`), so without this
# every spec run overwrites the developer's real launcher.json.
spec_config = File.join(Dir.tempdir, "xr-launcher-spec-cfg-#{Random.new.hex(8)}")
Dir.mkdir(spec_config)
Launcher::Paths.config_dir = spec_config
Spec.after_suite { FileUtils.rm_rf(spec_config) }

def with_tmp(& : String -> Nil) : Nil
  dir = File.join(Dir.tempdir, "xr-launcher-spec-#{Random.new.hex(8)}")
  Dir.mkdir(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

# Minimal fake of a xray-16 checkout: bin/x86_64/Release/xr_3da + .so
# files and res/gamedata/{shaders/gl, scripts}.
def fake_engine(root : String) : String
  bin = File.join(root, "bin", "x86_64", "Release")
  Dir.mkdir_p(bin)
  File.write(File.join(bin, "xr_3da"), "#!/bin/sh\n")
  File.write(File.join(bin, "xrEngine.so"), "so")
  File.write(File.join(bin, "xrGame.so"), "so")
  File.write(File.join(bin, "notes.txt"), "ignored")

  gl = File.join(root, "res", "gamedata", "shaders", "gl")
  Dir.mkdir_p(gl)
  File.write(File.join(gl, "base.ps"), "shader")
  scripts = File.join(root, "res", "gamedata", "scripts")
  Dir.mkdir_p(scripts)
  File.write(File.join(scripts, "ui_main_menu.script"), "engine version")
  File.write(File.join(scripts, ".gitattributes"), "* text=auto")
  root
end

def fake_soc_source(root : String) : String
  dir = File.join(root, "soc-src")
  Dir.mkdir(dir)
  %w[0 1 2 3 4 5 6 7 8 9 a b c d].each { |i| File.write(File.join(dir, "gamedata.db#{i}"), "db") }
  Dir.mkdir(File.join(dir, "bin")) # original binaries — must never be linked
  File.write(File.join(dir, "bin", "xr_3da.exe"), "windows")
  File.write(File.join(dir, "fsgame.ltx"), "original")
  dir
end

def fake_cop_source(root : String) : String
  dir = File.join(root, "cop-src")
  Dir.mkdir(dir)
  {"levels", "resources", "localization", "mp", "patches"}.each { |d| Dir.mkdir(File.join(dir, d)) }
  configs = File.join(dir, "gamedata", "configs")
  Dir.mkdir_p(configs)
  File.write(File.join(configs, "system.ltx"), "orig")
  scripts = File.join(dir, "gamedata", "scripts")
  Dir.mkdir_p(scripts)
  File.write(File.join(scripts, "sound_theme.script"), "original")
  File.write(File.join(scripts, "ui_main_menu.script"), "shipped")
  dir
end
