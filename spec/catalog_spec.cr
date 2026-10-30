require "./spec_helper"

describe Launcher::Catalog do
  it "exposes soc, cs, cop" do
    Launcher::Catalog.all.map(&.id).should eq(["soc", "cs", "cop"])
  end

  it "maps every game to a mode flag and game_mode" do
    soc = Launcher::Catalog["soc"]
    soc.mode_flag.should eq("-shoc")
    soc.game_mode.should eq("shoc")
    Launcher::Catalog["cs"].mode_flag.should eq("-cs")
    Launcher::Catalog["cop"].mode_flag.should eq("-cop")
  end

  it "writes soc fsgame with config\\ (not configs\\) and root-scan $arch_dir$" do
    ltx = Launcher::Catalog["soc"].fsgame_ltx
    ltx.should contain("$game_config$\t\t= true|\t\tfalse|\t$game_data$|\t\tconfig\\")
    ltx.lines.first.should start_with("$app_data_root$")
  end

  it "writes cop fsgame with arch_dir_levels/resources and configs\\" do
    ltx = Launcher::Catalog["cop"].fsgame_ltx
    ltx.should contain("configs\\")
    ltx.should contain("levels\\")
    ltx.should contain("resources\\")
    ltx.should contain("_appdata_\\")
  end

  it "validates sources" do
    with_tmp do |dir|
      soc = Launcher::Catalog["soc"]
      cop = Launcher::Catalog["cop"]

      Launcher::Catalog.validate_source(soc, File.join(dir, "missing")).should_not be_nil
      Launcher::Catalog.validate_source(soc, dir).should_not be_nil

      File.write(File.join(dir, "gamedata.db0"), "x")
      Launcher::Catalog.validate_source(soc, dir).should be_nil
      # db archives are not a CoP layout by themselves
      Launcher::Catalog.validate_source(cop, dir).should be_nil

      empty = File.join(dir, "empty"); Dir.mkdir(empty)
      Launcher::Catalog.validate_source(cop, empty).should_not be_nil
      Dir.mkdir(File.join(empty, "levels"))
      Launcher::Catalog.validate_source(cop, empty).should be_nil
    end
  end
end
