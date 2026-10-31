require "./spec_helper"

def install_soc(dir : String) : Launcher::Store::Install
  engine = fake_engine(File.join(dir, "engine"))
  source = fake_soc_source(dir)
  target = File.join(dir, "out", "soc")
  Dir.mkdir(File.dirname(target))
  store = Launcher::Store.new
  log_lines = [] of String
  install = Launcher::Installer.install(
    Launcher::Catalog["soc"], source, engine, target, store) { |l| log_lines << l }
  {install, store, log_lines}
end

describe Launcher::Installer do
  it "assembles the SoC layout" do
    with_tmp do |dir|
      engine = fake_engine(File.join(dir, "engine"))
      source = fake_soc_source(dir)
      target = File.join(dir, "out", "soc")
      Dir.mkdir(File.dirname(target))

      store = Launcher::Store.new
      install = Launcher::Installer.install(Launcher::Catalog["soc"], source, engine, target, store) { |_| }

      # engine binaries linked per-file, source binaries never touched
      bin = File.join(target, "bin")
      File.symlink?(File.join(bin, "xr_3da")).should be_true
      File.readlink(File.join(bin, "xr_3da")).should eq(File.join(engine, "bin", "x86_64", "Release", "xr_3da"))
      Dir.children(bin).should_not contain("notes.txt")
      File.exists?(File.join(bin, "xr_3da.exe")).should be_false

      # archives symlinked, not copied
      link = File.join(target, "gamedata.db0")
      File.symlink?(link).should be_true
      File.readlink(link).should eq(File.join(source, "gamedata.db0"))
      source_still_there = File.join(source, "gamedata.db0")
      File.exists?(source_still_there).should be_true

      # fsgame + openxray.ltx (SoC: config\)
      File.read(File.join(target, "fsgame.ltx")).should contain("config\\")
      ltx = File.read(File.join(target, "gamedata", "config", "openxray.ltx"))
      ltx.should contain("game_mode = shoc")

      # GL shaders linked from the engine overlay
      File.symlink?(File.join(target, "gamedata", "shaders", "gl")).should be_true

      # appdata skeleton
      {"savedgames", "logs", "screenshots"}.each do |sub|
        Dir.exists?(File.join(target, "_appdata_", sub)).should be_true
      end

      # store registered + recents updated
      store.installs.size.should eq(1)
      store.recent_sources["soc"].should eq(source)
      install.path.should eq(target)
    end
  end

  it "assembles the CoP layout: configs linked, engine scripts overlay" do
    with_tmp do |dir|
      engine = fake_engine(File.join(dir, "engine"))
      source = fake_cop_source(dir)
      target = File.join(dir, "cop-dist")
      store = Launcher::Store.new

      Launcher::Installer.install(Launcher::Catalog["cop"], source, engine, target, store) { |_| }

      # unpacked asset dirs linked
      {"levels", "resources", "localization", "mp", "patches"}.each do |d|
        File.symlink?(File.join(target, d)).should be_true
      end

      # configs: children linked, openxray.ltx real, game_mode = cop
      configs = File.join(target, "gamedata", "configs")
      File.symlink?(File.join(configs, "system.ltx")).should be_true
      ltx = File.read(File.join(configs, "openxray.ltx"))
      ltx.should contain("game_mode = cop")

      # scripts: shipped ones copied, engine overlay wins, dotfiles skipped
      scripts = File.join(target, "gamedata", "scripts")
      File.read(File.join(scripts, "sound_theme.script")).should eq("original")
      File.read(File.join(scripts, "ui_main_menu.script")).should eq("engine version")
      Dir.children(scripts).should_not contain(".gitattributes")
    end
  end

  it "refuses bad inputs and rolls back on failure" do
    with_tmp do |dir|
      engine = fake_engine(File.join(dir, "engine"))
      source = fake_soc_source(dir)
      store = Launcher::Store.new

      # bad source
      empty = File.join(dir, "empty"); Dir.mkdir(empty)
      expect_raises(Launcher::InstallError) do
        Launcher::Installer.install(Launcher::Catalog["soc"], empty, engine,
          File.join(dir, "a"), store) { |_| }
      end
      Dir.exists?(File.join(dir, "a")).should be_false

      # bad engine
      expect_raises(Launcher::InstallError) do
        Launcher::Installer.install(Launcher::Catalog["soc"], source, empty,
          File.join(dir, "b"), store) { |_| }
      end
      Dir.exists?(File.join(dir, "b")).should be_false

      # non-empty target
      busy = File.join(dir, "busy"); Dir.mkdir(busy)
      File.write(File.join(busy, "x"), "y")
      expect_raises(Launcher::InstallError) do
        Launcher::Installer.install(Launcher::Catalog["soc"], source, engine,
          busy, store) { |_| }
      end

      store.installs.should be_empty
      # the original copy is untouched by failures
      File.exists?(File.join(source, "gamedata.db0")).should be_true
    end
  end
end

describe Launcher::Uninstaller do
  it "removes the install but never the symlink targets" do
    with_tmp do |dir|
      engine = fake_engine(File.join(dir, "engine"))
      source = fake_soc_source(dir)
      target = File.join(dir, "out", "soc")
      Dir.mkdir(File.dirname(target))
      store = Launcher::Store.new
      Launcher::Installer.install(Launcher::Catalog["soc"], source, engine, target, store) { |_| }

      Launcher::Uninstaller.remove(target, store) { |_| }

      Dir.exists?(target).should be_false
      store.installs.should be_empty
      # the original game copy and the engine survived
      File.exists?(File.join(source, "gamedata.db0")).should be_true
      File.exists?(File.join(source, "fsgame.ltx")).should be_true
      File.exists?(File.join(engine, "bin", "x86_64", "Release", "xr_3da")).should be_true
    end
  end

  it "refuses to delete folders not registered in the config" do
    with_tmp do |dir|
      innocent = File.join(dir, "some-folder"); Dir.mkdir(innocent)
      File.write(File.join(innocent, "file"), "x")
      expect_raises(Launcher::Uninstaller::UnsafeDeleteError) do
        Launcher::Uninstaller.remove(innocent, Launcher::Store.new) { |_| }
      end
      Dir.exists?(innocent).should be_true
    end
  end

  it "follows no symlinks while deleting" do
    with_tmp do |dir|
      precious = File.join(dir, "precious"); Dir.mkdir(precious)
      File.write(File.join(precious, "data"), "x")
      install_dir = File.join(dir, "my-install"); Dir.mkdir(install_dir)
      File.symlink(precious, File.join(install_dir, "link"))
      store = Launcher::Store.new
      store.add_install(Launcher::Store::Install.new(
        id: "soc-1", game: "soc", path: install_dir, engine: "e", source: "s", created_at: "t"))

      Launcher::Uninstaller.remove(install_dir, store) { |_| }
      Dir.exists?(install_dir).should be_false
      store.installs.should be_empty
      File.exists?(File.join(precious, "data")).should be_true
    end
  end
end
