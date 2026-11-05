require "./spec_helper"

describe Launcher::Store do
  it "round-trips through JSON" do
    with_tmp do |dir|
      path = File.join(dir, "store.json")
      store = Launcher::Store.new
      install = Launcher::Store::Install.new(
        id: "soc-123", game: "soc", path: "/games/soc",
        engine: "/xray-16", source: "/gog/soc", created_at: "2026-10-30T00:00:00+03:00")
      store.add_install(install)
      store.recent_engine = "/xray-16"
      store.recent_sources["soc"] = "/gog/soc"
      store.save(path)

      loaded = Launcher::Store.load(path)
      loaded.installs.size.should eq(1)
      loaded.installs.first.path.should eq("/games/soc")
      loaded.recent_engine.should eq("/xray-16")
      loaded.recent_sources["soc"].should eq("/gog/soc")
    end
  end

  it "starts empty on a missing or corrupt file" do
    with_tmp do |dir|
      Launcher::Store.load(File.join(dir, "missing.json")).installs.should be_empty
      bad = File.join(dir, "bad.json")
      File.write(bad, "{ not json")
      Launcher::Store.load(bad).installs.should be_empty
    end
  end

  it "indexes installs per game" do
    with_tmp do |dir|
      store = Launcher::Store.new
      store.add_install(Launcher::Store::Install.new(
        id: "soc-1", game: "soc", path: File.join(dir, "a"), engine: "e", source: "s", created_at: "t"))
      store.add_install(Launcher::Store::Install.new(
        id: "cop-1", game: "cop", path: File.join(dir, "b"), engine: "e", source: "s", created_at: "t"))

      store.for_game("soc").size.should eq(1)
      store.for_game("cop").size.should eq(1)
      store.find_by_path(File.join(dir, "b")).try(&.id).should eq("cop-1")

      store.remove_install(File.join(dir, "a"))
      store.for_game("soc").should be_empty
      store.for_game("cop").size.should eq(1)
    end
  end

  it "marks and round-trips modified-game installs" do
    with_tmp do |dir|
      path = File.join(dir, "store.json")
      store = Launcher::Store.new
      store.add_install(Launcher::Store::Install.new(
        id: "soc-1", game: "soc", path: File.join(dir, "a"), engine: "e", source: "s",
        created_at: "t"))
      store.add_install(Launcher::Store::Install.new(
        id: "soc-2", game: "soc", path: File.join(dir, "b"), engine: "e", source: "s",
        created_at: "t", custom: true))
      store.save(path)

      # entries created before the flag exist deserialize with custom=false
      loaded = Launcher::Store.load(path)
      loaded.installs.size.should eq(2)
      loaded.custom_installs.size.should eq(1)
      loaded.custom_installs.first.path.should eq(File.join(dir, "b"))
      # the custom entry is still a runnable soc install (compat mode)
      loaded.for_game("soc").size.should eq(2)
      # a config written before the feature existed loads with no flag
      legacy = %({"version":1,"installs":[{"id":"x","game":"cop","path":"/x","engine":"e","source":"s","created_at":"t"}]})
      File.write(path, legacy)
      Launcher::Store.load(path).installs.first.custom?.should be_false
    end
  end

  it "round-trips a per-install play-button launch mode" do
    with_tmp do |dir|
      path = File.join(dir, "store.json")
      store = Launcher::Store.new
      store.add_install(Launcher::Store::Install.new(
        id: "soc-1", game: "soc", path: "/x", engine: "e", source: "s", created_at: "t"))
      install = store.installs.first
      install.launch_mode = "lastsave"
      store.update_install(install)
      store.save(path)
      Launcher::Store.load(path).installs.first.launch_mode.should eq("lastsave")

      # a config written before the feature existed starts in "play"
      legacy = %({"version":1,"installs":[{"id":"x","game":"cop","path":"/x","engine":"e","source":"s","created_at":"t"}]})
      File.write(path, legacy)
      Launcher::Store.load(path).installs.first.launch_mode.should eq("play")
    end
  end

  it "round-trips the last open sidebar section" do
    with_tmp do |dir|
      path = File.join(dir, "store.json")
      store = Launcher::Store.new
      store.last_played_section = "soc"
      store.save(path)
      Launcher::Store.load(path).last_played_section.should eq("soc")

      # a config written before the feature existed has no section
      legacy = %({"version":1,"installs":[]})
      File.write(path, legacy)
      Launcher::Store.load(path).last_played_section.should be_nil
    end
  end

  it "replaces an install at the same path on add" do
    with_tmp do |dir|
      store = Launcher::Store.new
      store.add_install(Launcher::Store::Install.new(
        id: "soc-1", game: "soc", path: "/x", engine: "e", source: "s", created_at: "t"))
      store.add_install(Launcher::Store::Install.new(
        id: "soc-2", game: "soc", path: "/x", engine: "e2", source: "s2", created_at: "t2"))
      store.installs.size.should eq(1)
      store.installs.first.id.should eq("soc-2")
    end
  end

  it "backs up a corrupt config instead of wiping it" do
    with_tmp do |dir|
      path = File.join(dir, "store.json")
      File.write(path, "{ not json")

      loaded = Launcher::Store.load(path)
      loaded.installs.should be_empty

      # the corrupt original survives as a backup — recoverable by hand
      File.exists?("#{path}.corrupt").should be_true
      # and an empty in-memory store does not clobber the backup
      loaded.save(path)
      File.exists?("#{path}.corrupt").should be_true
    end
  end

  it "saves atomically and keeps the previous config as .bak" do
    with_tmp do |dir|
      path = File.join(dir, "store.json")
      store = Launcher::Store.new
      store.recent_engine = "/first"
      store.save(path)

      store.recent_engine = "/second"
      store.save(path)

      File.exists?(path).should be_true
      File.exists?("#{path}.tmp.#{Process.pid}").should be_false
      # the previous good content survives in the backup
      Launcher::Store.load("#{path}.bak").recent_engine.should eq("/first")
      Launcher::Store.load(path).recent_engine.should eq("/second")
    end
  end

  it "allows only one single-instance lock holder" do
    with_tmp do |dir|
      Dir.mkdir(File.join(dir, "cfg"))
      Launcher::Paths.stub_config_dir(File.join(dir, "cfg")) do
        Launcher::SingleInstance.acquire!
        expect_raises(Launcher::SingleInstance::AlreadyRunning) do
          Launcher::SingleInstance.acquire!
        end
        Launcher::SingleInstance.release
        Launcher::SingleInstance.acquire! # re-acquirable after release
        Launcher::SingleInstance.release
      end
    end
  end
end
