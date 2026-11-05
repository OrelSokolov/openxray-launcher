# The launcher's JSON state: registered installs (one entry per created
# distribution) plus recently used engine/source paths for the wizard.
#
# The single source of truth for installed distributions: save() is
# atomic (tmp + rename) and a corrupt file is backed up, never silently
# overwritten with an empty list.

require "json"

module Launcher
  class Store
    struct Install
      include JSON::Serializable

      getter id : String        # "<game>-<epoch>" unique per install
      getter game : String      # Catalog game id (for a custom install: the chosen compatibility mode)
      getter path : String      # install root (contains fsgame.ltx, bin/, ...)
      getter engine : String    # engine root passed at install time
      getter source : String    # original game copy passed at install time
      getter created_at : String
      # true: a modified game install (compat mode picked in the wizard);
      # absent in configs written before the feature — defaults to false
      getter? custom : Bool = false
      # Play-button mode for THIS install: "play" — start to the main
      # menu; "lastsave" — also pass -lastsave so the engine loads the
      # last save straight away. Absent in configs written before the
      # feature — defaults to "play".
      property launch_mode : String = "play"

      def initialize(@id, @game, @path, @engine, @source, @created_at, @custom = false)
      end
    end

    property installs : Array(Install)
    property recent_engine : String?
    property recent_sources : Hash(String, String) # game id => last source dir
    property locale : String?                      # UI language, e.g. "ru"
    property last_played_section : String?         # sidebar section open at exit (game id or "mod")

    # Valid play-button modes (per install, see Install#launch_mode).
    DEFAULT_LAUNCH_MODE = "play"
    LAUNCH_MODES        = %w[play lastsave]

    def initialize
      @installs = [] of Install
      @recent_sources = {} of String => String
    end

    def self.load(path : String = Paths.store_path) : self
      return new unless File.exists?(path)
      from_json(File.read(path))
    rescue ex : JSON::Error | IO::Error
      # A corrupt store must not brick the launcher — but it must not
      # be silently wiped either: back it up (a truncated write, a kill
      # mid-save), say so LOUDLY, and start empty IN MEMORY only. No
      # save happens until the user changes something, and the backup
      # keeps the old installs recoverable by hand.
      backup = "#{path}.corrupt"
      File.rename(path, backup) rescue nil
      STDERR.puts "warning: could not read #{path} (#{ex.message}); " \
        "backed up to #{backup}, starting empty"
      new
    end

    def self.from_json(json : String) : self
      data = JSON.parse(json)
      store = new
      installs = data["installs"]?.try(&.as_a?) || [] of JSON::Any
      installs.each do |entry|
        store.installs << Install.from_json(entry.to_json)
      end
      store.recent_engine = data["recent_engine"]?.try &.as_s?
      store.locale = data["locale"]?.try &.as_s?
      store.last_played_section = data["last_played_section"]?.try &.as_s?
      sources = data["recent_sources"]?.try(&.as_h?) || {} of String => JSON::Any
      sources.each do |game, dir|
        store.recent_sources[game] = dir.as_s
      end
      store
    end

    def to_json(json : JSON::Builder)
      json.object do
        json.field "version", 1
        json.field "installs" do
          json.array do
            installs.each &.to_json(json)
          end
        end
        json.field "recent_engine", recent_engine
        json.field "locale", locale
        json.field "last_played_section", last_played_section
        json.field "recent_sources" do
          json.object do
            recent_sources.each { |k, v| json.field k, v }
          end
        end
      end
    end

    # Atomic + non-clobbering write:
    #   * the temp file is per-PID — two processes saving at once never
    #     write into the same tmp (a shared tmp name let interleaved
    #     writes get renamed in as a corrupt config);
    #   * the previous config is kept as `launcher.json.bak` — even a
    #     buggy or stale writer leaves the last good list recoverable;
    #   * rename is atomic — a crash leaves either the old or the new
    #     file, never a truncated mix.
    def save(path : String = Paths.store_path) : Nil
      tmp = "#{path}.tmp.#{Process.pid}"
      File.write(tmp, to_pretty_json)
      File.copy(path, "#{path}.bak") if File.exists?(path)
      File.rename(tmp, path)
    end

    def add_install(install : Install) : Nil
      installs.reject! { |i| i.path == install.path }
      installs << install
    end

    # Install is a value struct: an edited copy must be written back
    # (by id) or the change silently dies with the copy.
    def update_install(install : Install) : Nil
      installs.each_with_index do |i, idx|
        installs[idx] = install if i.id == install.id
      end
    end

    def remove_install(path : String) : Nil
      installs.reject! { |i| i.path == path }
    end

    def for_game(game_id : String) : Array(Install)
      installs.select { |i| i.game == game_id }
    end

    # Modified-game installs (any compatibility mode) — the "Modified
    # game" sidebar entry lists these instead of the per-game pages.
    def custom_installs : Array(Install)
      installs.select(&.custom?)
    end

    def find_by_path(path : String) : Install?
      installs.find { |i| i.path == path }
    end

    def self.next_id(game_id : String) : String
      "#{game_id}-#{Time.local.to_unix}"
    end
  end
end
