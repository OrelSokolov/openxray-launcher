# Cross-platform per-user locations for the launcher's own state.

module Launcher
  module Paths
    @@override : String? = nil # spec seam — never set in production code

    # Directory holding launcher.json. XDG on Linux/BSD, %APPDATA% on
    # Windows, Application Support on macOS.
    def self.config_dir : String
      dir = @@override || {% if flag?(:win32) %}
        File.join(ENV["APPDATA"]? || File.join(home, "AppData", "Roaming"), "xr-launcher")
      {% elsif flag?(:darwin) %}
        File.join(home, "Library", "Application Support", "xr-launcher")
      {% else %}
        File.join(ENV["XDG_CONFIG_HOME"]? || File.join(home, ".config"), "xr-launcher")
      {% end %}
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      dir
    end

    # Redirect config_dir for the duration of a block (specs must not
    # touch the real user config).
    def self.stub_config_dir(dir : String, &)
      previous = @@override
      @@override = dir
      yield
    ensure
      @@override = previous
    end

    # Permanent redirect for the whole process: spec_helper sets it so
    # no spec can ever write the real user config — Installer and
    # Uninstaller persist through `Store#save`'s default path
    # (`Paths.store_path`), which the block-scoped stub cannot cover.
    def self.config_dir=(dir : String?) : Nil
      @@override = dir
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
