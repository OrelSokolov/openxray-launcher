require "./spec_helper"

def fake_install(dir : String) : Launcher::Store::Install
  bin = File.join(dir, "bin")
  Dir.mkdir_p(bin)
  File.write(File.join(bin, Launcher::Engine.executable_name), "#!/bin/sh\nexec sleep 0.3\n")
  File.chmod(File.join(bin, Launcher::Engine.executable_name), 0o755)
  Launcher::Store::Install.new(
    id: "soc-1", game: "soc", path: dir,
    engine: dir, source: dir, created_at: "2026-01-01T00:00:00")
end

describe Launcher::Runner do
  it "parks the launched pid and reports running while it lives" do
    with_tmp do |dir|
      install = fake_install(dir)
      process = Launcher::Runner.run(install)

      Launcher::Runner.running_pid(install).should eq(process.pid)
      Launcher::Runner.running?(install).should be_true

      process.wait
      Launcher::Runner.running?(install).should be_false
    end
  end

  it "treats a missing, garbage or dead pid as not running" do
    with_tmp do |dir|
      install = fake_install(dir)

      Launcher::Runner.running?(install).should be_false # no pid file yet

      # A reaped pid: dead for sure (kernel pids are not reused this fast).
      dead = Process.new("sleep", ["0.1"])
      dead.terminate
      dead.wait
      Launcher::Runner.write_pid(install, dead.pid)
      Launcher::Runner.running?(install).should be_false

      Launcher::Runner.write_pid(install, 999_999)
      Launcher::Runner.running?(install).should be_false

      File.write(File.join(dir, "_appdata_", Launcher::Runner::PID_FILE), "garbage")
      Launcher::Runner.running_pid(install).should be_nil
    end
  end

  it "passes extra args (the -lastsave play mode) to the engine" do
    with_tmp do |dir|
      install = fake_install(dir)
      exe = File.join(dir, "bin", Launcher::Engine.executable_name)
      File.write(exe, %(#!/bin/sh\nprintf '%s\\n' "$@" > "#{dir}/args"\n))
      File.chmod(exe, 0o755)

      process = Launcher::Runner.run(install, [Launcher::Runner::LASTSAVE_FLAG])
      process.wait
      args = File.read(File.join(dir, "args"))
      args.should contain("-shoc") # the per-game mode flag stays first
      args.should contain(Launcher::Runner::LASTSAVE_FLAG)
    end
  end

  it "clear_pid removes the pid file" do
    with_tmp do |dir|
      install = fake_install(dir)
      Launcher::Runner.write_pid(install, 42)
      Launcher::Runner.clear_pid(install)
      Launcher::Runner.running_pid(install).should be_nil
    end
  end
end
