require "./spec_helper"

describe Launcher::Engine do
  it "resolves a xray-16 checkout" do
    with_tmp do |dir|
      root = fake_engine(dir)
      loc = Launcher::Engine.resolve(root)
      loc.should_not be_nil
      loc.not_nil!.kind.should eq(:repo)
      loc.not_nil!.bin_dir.should eq(File.join(root, "bin", "x86_64", "Release"))
      loc.not_nil!.res_gamedata.should eq(File.join(root, "res", "gamedata"))
    end
  end

  it "resolves the bin dir itself and finds res/ upwards" do
    with_tmp do |dir|
      root = fake_engine(dir)
      loc = Launcher::Engine.resolve(File.join(root, "bin", "x86_64", "Release"))
      loc.should_not be_nil
      loc.not_nil!.kind.should eq(:bindir)
      loc.not_nil!.res_gamedata.should eq(File.join(root, "res", "gamedata"))
    end
  end

  it "resolves an installed prefix" do
    with_tmp do |dir|
      prefix = File.join(dir, "prefix")
      libdir = File.join(prefix, "lib", "openxray")
      Dir.mkdir_p(libdir)
      File.write(File.join(libdir, "xr_3da"), "exe")
      gl = File.join(prefix, "share", "openxray", "gamedata", "shaders", "gl")
      Dir.mkdir_p(gl)
      File.write(File.join(gl, "x.ps"), "s")

      loc = Launcher::Engine.resolve(prefix).not_nil!
      loc.kind.should eq(:prefix)
      loc.bin_dir.should eq(libdir)
    end
  end

  it "rejects unrelated folders" do
    with_tmp do |dir|
      Launcher::Engine.resolve(dir).should be_nil
      Launcher::Engine.resolve(File.join(dir, "nope")).should be_nil
    end
  end

  it "lists only the engine binary and modules for linking" do
    with_tmp do |dir|
      root = fake_engine(dir)
      names = Launcher::Engine.bin_files(File.join(root, "bin", "x86_64", "Release"))
      names.should contain("xr_3da")
      names.should contain("xrEngine.so")
      names.should_not contain("notes.txt")
    end
  end
end
