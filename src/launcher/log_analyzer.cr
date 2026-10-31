# Scan an install's engine logs (_appdata_/logs) for problems the
# engine already reports line by line: fatal crashes, missing textures,
# script (Lua) errors and other warnings.
#
# X-Ray log conventions (xray-16 src/xrCore/log.cpp, xrDebug.cpp):
#   * a fatal error writes a "FATAL ERROR" line followed by a
#     "[error] Expression    : ..." block and a stack trace;
#   * engine warnings are lines prefixed with "! ";
#   * a texture miss logs "! Can't find texture 'name'";
#   * script failures log "SCRIPT ERROR ..." / "LUA error".

module Launcher
  module LogAnalyzer
    MAX_SAMPLES = 10 # unique samples kept per category

    # One problem category: total occurrences plus a few unique samples.
    # A class (not struct): findings are accumulated in place.
    class Finding
      getter count : Int32
      getter samples : Array(String)

      def initialize
        @count = 0
        @samples = [] of String
      end

      def bump(sample : String? = nil) : Nil
        @count += 1
        note(sample) if sample
      end

      def note(sample : String) : Nil
        @samples << sample unless @samples.includes?(sample) || @samples.size >= MAX_SAMPLES
      end

      def any? : Bool
        @count > 0
      end
    end

    class Report
      getter files : Array(String) # scanned log file names
      property lines : Int32
      getter crashes : Finding
      getter textures : Finding
      getter scripts : Finding
      getter warnings : Finding # "! " lines outside the categories above

      def initialize
        @files = [] of String
        @lines = 0
        @crashes = Finding.new
        @textures = Finding.new
        @scripts = Finding.new
        @warnings = Finding.new
      end

      def problems? : Bool
        crashes.any? || textures.any? || scripts.any?
      end
    end

    def self.scan(install : Store::Install) : Report
      scan_dir(File.join(install.path, "_appdata_", "logs"))
    end

    def self.scan_dir(log_dir : String) : Report
      report = Report.new
      return report unless Dir.exists?(log_dir)

      log_files(log_dir).sort!.each do |name|
        report.files << name
        scan_file(File.join(log_dir, name), report)
      end
      report
    end

    # Delete every scanned log file (*.log / *.bkp) so the next run —
    # and the report built from it — starts fresh instead of mixing in
    # problems from old runs. Returns the number of files removed.
    def self.clear(install : Store::Install) : Int32
      clear_dir(File.join(install.path, "_appdata_", "logs"))
    end

    def self.clear_dir(log_dir : String) : Int32
      return 0 unless Dir.exists?(log_dir)
      names = log_files(log_dir)
      names.each { |name| File.delete(File.join(log_dir, name)) }
      names.size
    end

    private def self.log_files(log_dir : String) : Array(String)
      Dir.children(log_dir).select { |name|
        File.file?(File.join(log_dir, name)) &&
          (name.downcase.ends_with?(".log") || name.downcase.ends_with?(".bkp"))
      }
    end

    private def self.scan_file(path : String, report : Report) : Nil
      # \r\n is stripped by chomp; invalid bytes must not fail the scan.
      pending_expression = false # FATAL ERROR seen, waiting for its Expression line
      File.each_line(path, invalid: :skip) do |raw|
        line = raw.chomp
        report.lines += 1

        if line.includes?("FATAL ERROR")
          report.crashes.bump
          pending_expression = true
        elsif pending_expression
          if line.starts_with?("[error] Expression")
            report.crashes.note(line.sub(/^\[error\]\s*Expression\s*:\s*/, ""))
            pending_expression = false
          elsif !line.blank? && !line.starts_with?("[error]")
            pending_expression = false
          end
        elsif texture = line.match(/^!\s*[Cc]an't (?:find|open) texture '([^']+)'/)
          report.textures.bump(texture[1])
        elsif line.includes?("SCRIPT ERROR") || line.includes?("LUA error")
          report.scripts.bump(line)
        elsif line.starts_with?("! ")
          report.warnings.bump(line)
        end
      end
    end
  end
end
