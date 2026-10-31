# i18n plumbing: translations live in config/locales/*.yml and are
# EMBEDDED into the binary at compile time (I18n::Loader::YAML.embed —
# the .yml files are read by the compiler, never from disk at runtime),
# so a distributed xr-launcher is self-contained.
#
# The `L` module is the single lookup seam for the whole launcher: keys
# with English fallbacks live here, YAML overrides them per locale, and
# both the CLI and the GUI go through it (headless builds get the
# English fallbacks without initializing I18n).

require "i18n"

module Launcher
  module Locale
    # Display order of the language selector; keys are I18n locale codes.
    AVAILABLE = {"en" => "English", "ru" => "Русский"}

    @@initialized = false

    # Initialize I18n with the embedded catalogs and activate `preferred`
    # (when it is a known locale) or the system-detected one. Idempotent;
    # returns the activated locale code.
    def self.init(preferred : String? = nil) : String
      return I18n.locale if @@initialized && preferred.nil?

      locale = preferred || detect
      locale = "en" unless AVAILABLE.keys.includes?(locale)

      unless @@initialized
        I18n.config.loaders << I18n::Loader::YAML.embed("config/locales")
        I18n.config.default_locale = locale
        I18n.init
        @@initialized = true
      end
      I18n.activate(locale)
      I18n.locale
    end

    # LANG/LC_ALL based detection: "ru_RU.UTF-8" -> "ru", else "en".
    def self.detect : String
      lang = (ENV["LC_ALL"]? || ENV["LANG"]? || "en").split(/[._]/).first.downcase
      AVAILABLE.keys.includes?(lang) ? lang : "en"
    end

    def self.set(locale : String) : Nil
      init(locale)
    end

    def self.initialized? : Bool
      @@initialized
    end
  end

  module L
    # English fallbacks: what a key renders as before I18n is
    # initialized (headless specs/CLI without locale init) or when a
    # locale file misses the key.
    FALLBACK = {
      # errors (core)
      "errors.source_not_found"        => "directory does not exist",
      "errors.source_soc_none"         => "no gamedata.db* archives found (expected the GOG/Steam SoC root with gamedata.db0 … gamedata.dbd)",
      "errors.source_cs_none"          => "no levels/ or resources/ folders and no *.db archives found",
      "errors.source_cop_none"         => "no levels/ or resources/ folders and no gamedata.db* archives found (expected the GOG/Steam CoP root)",
      "errors.engine_prefix"           => "game source: %{message}",
      "errors.engine_no_binaries"      => "engine folder: no OpenXRay binaries found (expected a xray-16 checkout, its bin/x86_64/Release, or an installed prefix)",
      "errors.engine_no_res"           => "engine folder: no binaries to link in %{dir}",
      "errors.target_exists"           => "target %{path} already exists",
      "errors.target_not_empty"        => "target %{path} is not empty",
      "errors.target_root"             => "refusing to install into %{path}",
      "errors.parent_missing"          => "parent folder %{path} does not exist",
      "errors.no_game_data"            => "no game data found in %{source}",
      "errors.exe_missing"             => "%{exe} not found — reinstall the game",
      "errors.not_registered"          => "%{path} is not a registered launcher install — refusing to delete",
      "errors.refuse_root"             => "refusing to delete filesystem root",
      "errors.already_running"         => "another xr-launcher instance is already running — close it first",
      "errors.already_running"         => "another xr-launcher instance is already running — close it first",
      # install log lines
      "install.creating"               => "-> creating %{path}",
      "install.bin_linked"             => "   bin/: %{n} engine files",
      "install.assets_linked"          => "   game data: %{n} entries symlinked",
      "install.shaders_linked"         => "   gamedata/shaders/gl: linked to engine",
      "install.shaders_missing"        => "   WARNING: engine has no res/gamedata — GL shaders missing",
      "install.openxray_written"       => "   gamedata/%{dir}/openxray.ltx: game_mode = %{mode}",
      "install.fsgame_written"         => "   fsgame.ltx written",
      "install.appdata_created"        => "   _appdata_/{savedgames,logs,screenshots} created",
      "install.done"                   => "installed %{title} -> %{path}",
      "install.failed_rollback"        => "FAILED: %{message} — rolling back",
      "install.removing"               => "-> removing %{path}",
      "install.removed"                => "removed %{path}",
    } of String => String

    def self.t(key : String, **params) : String
      default = FALLBACK[key]? || key
      unless Locale.initialized?
        return default.gsub(/%\{(\w+)\}/) do
          params.fetch($1.to_s, $~[0]).to_s
        end
      end
      I18n.t(key, **params, default: default)
    end
  end
end
