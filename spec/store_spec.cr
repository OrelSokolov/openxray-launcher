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

  it "indexes installs per game and prunes dead ones" do
    with_tmp do |dir|
      store = Launcher::Store.new
      live = File.join(dir, "live"); Dir.mkdir(live)
      File.write(File.join(live, Launcher::Paths::MARKER_NAME), "{}")
      store.add_install(Launcher::Store::Install.new(
        id: "soc-1", game: "soc", path: live, engine: "e", source: "s", created_at: "t"))
      store.add_install(Launcher::Store::Install.new(
        id: "cop-1", game: "cop", path: File.join(dir, "gone"), engine: "e", source: "s", created_at: "t"))

      store.for_game("soc").size.should eq(1)
      store.for_game("cop").size.should eq(1)
      store.prune!.map(&.id).should eq(["cop-1"])
      store.for_game("cop").should be_empty
      store.for_game("soc").size.should eq(1)
    end
  end
end
