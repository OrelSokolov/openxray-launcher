require "./spec_helper"

def fake_install_with_logs(root : String) : Launcher::Store::Install
  logs = File.join(root, "cop", "_appdata_", "logs")
  Dir.mkdir_p(logs)

  # Current engine log: one crash, two texture misses (one repeated),
  # a script error, a stray warning — plus clean noise lines.
  File.write(File.join(logs, "xr_3da_player.log"), String.build do |s|
    s << "* Initializing Engine...\r\n"
    s << "* Load CFG:\r\n"
    s << "! Can't find texture 'act\\act_arm_1'\r\n"
    s << "! Can't find texture 'act\\act_arm_1'\r\n"
    s << "! Can't find texture 'ui\\ui_icon_total'\r\n"
    s << "! Time limit is out. Nothin' to compute.\r\n"
    s << "\r\n"
    s << "FATAL ERROR\r\n"
    s << "\r\n"
    s << "[error] Expression    : 0\r\n"
    s << "[error] Function      : CRender::init\r\n"
    s << "stack trace:\r\n"
    s << "SCRIPT ERROR (while running file)\r\n"
  end)

  # Previous run (engine .bkp backup): one more crash.
  File.write(File.join(logs, "xr_3da_player.bkp"),
    "FATAL ERROR\r\n[error] Expression    : !vertex->is_locked()\r\n")

  # Launcher's own log: never counts as engine problems.
  File.write(File.join(logs, "launcher.log"),
    "2026-10-30T10:00:00Z launching from #{root}\n")

  # Non-log files must be skipped entirely.
  File.write(File.join(logs, "notes.txt"), "FATAL ERROR")

  Launcher::Store::Install.new(
    "cop-#{Time.local.to_unix}", "cop", File.join(root, "cop"),
    "/engine", "/source", Time.local.to_rfc3339)
end

describe Launcher::LogAnalyzer do
  it "counts crashes, textures, scripts and warnings across log files" do
    with_tmp do |root|
      install = fake_install_with_logs(root)
      report = Launcher::LogAnalyzer.scan(install)

      report.files.should eq(["launcher.log", "xr_3da_player.bkp", "xr_3da_player.log"])
      report.files.should_not contain("notes.txt")

      report.crashes.count.should eq(2)
      report.crashes.samples.should contain("0")
      report.crashes.samples.should contain("!vertex->is_locked()")

      report.textures.count.should eq(3)
      report.textures.samples.should eq(["act\\act_arm_1", "ui\\ui_icon_total"])

      report.scripts.count.should eq(1)
      report.warnings.count.should eq(1)
      report.problems?.should be_true
    end
  end

  it "reports clean logs and missing log dirs" do
    with_tmp do |root|
      clean = File.join(root, "clean", "_appdata_", "logs")
      Dir.mkdir_p(clean)
      File.write(File.join(clean, "xr_3da_player.log"), "* all good\r\n")
      report = Launcher::LogAnalyzer.scan_dir(clean)
      report.problems?.should be_false
      report.warnings.count.should eq(0)

      empty = Launcher::LogAnalyzer.scan_dir(File.join(root, "nowhere"))
      empty.files.should be_empty
    end
  end

  it "clears log files so the next report starts fresh" do
    with_tmp do |root|
      install = fake_install_with_logs(root)

      Launcher::LogAnalyzer.clear(install).should eq(3) # .log/.bkp only
      Launcher::LogAnalyzer.scan(install).tap do |report|
        report.files.should be_empty
        report.lines.should eq(0)
        report.problems?.should be_false
      end
      # notes.txt is not a log — it must survive the clear.
      Dir.children(File.join(root, "cop", "_appdata_", "logs")).should eq(["notes.txt"])

      # Clearing an empty (or missing) dir is a no-op, not an error.
      Launcher::LogAnalyzer.clear_dir(File.join(root, "nowhere")).should eq(0)
    end
  end
end
