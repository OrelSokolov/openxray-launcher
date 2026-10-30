# Cross-platform per-user locations for the launcher's own state.

module Launcher
  module Paths
    MARKER_NAME = ".installed_ok"

    # Directory holding launcher.json. XDG on Linux/BSD, %APPDATA% on
    # Windows, Application Support on macOS.
    def self.config_dir : String
      dir = {% if flag?(:win32) %}
        File.join(ENV["APPDATA"]? || File.join(home, "AppData", "Roaming"), "xr-launcher")
      {% elsif flag?(:darwin) %}
        File.join(home, "Library", "Application Support", "xr-launcher")
      {% else %}
        File.join(ENV["XDG_CONFIG_HOME"]? || File.join(home, ".config"), "xr-launcher")
      {% end %}
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      dir
    end

    def self.store_path : String
      File.join(config_dir, "launcher.json")
    end

    def self.home : String
      ENV["HOME"]? || "."
    end

    # Default parent for new installs: ~/Games/OpenXRay
    def self.default_installs_root : String
      File.join(home, "Games", "OpenXRay")
    end
  end
end
