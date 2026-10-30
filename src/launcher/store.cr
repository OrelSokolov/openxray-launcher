# The launcher's JSON state: registered installs (one entry per created
# distribution) plus recently used engine/source paths for the wizard.
#
# The in-install `.installed_ok` marker (written by the installer) is the
# on-disk truth; the store is the index. On load, entries whose marker is
# gone are dropped (the user deleted the folder manually).

require "json"

module Launcher
  class Store
    struct Install
      include JSON::Serializable

      getter id : String        # "<game>-<epoch>" unique per install
      getter game : String      # Catalog game id
      getter path : String      # install root (contains fsgame.ltx, bin/, ...)
      getter engine : String    # engine root passed at install time
      getter source : String    # original game copy passed at install time
      getter created_at : String

      def initialize(@id, @game, @path, @engine, @source, @created_at)
      end
    end

    property installs : Array(Install)
    property recent_engine : String?
    property recent_sources : Hash(String, String) # game id => last source dir
    property locale : String?                      # UI language, e.g. "ru"

    def initialize
      @installs = [] of Install
      @recent_sources = {} of String => String
    end

    def self.load(path : String = Paths.store_path) : self
      return new unless File.exists?(path)
      from_json(File.read(path))
    rescue ex : JSON::Error | IO::Error
      # A corrupt store must not brick the launcher — start empty (loud in
      # the log, silent in the UI is fine here: the data is recreatable by
      # re-installing; nothing game-owned is lost).
      STDERR.puts "warning: could not read #{path} (#{ex.message}); starting empty"
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
        json.field "recent_sources" do
          json.object do
            recent_sources.each { |k, v| json.field k, v }
          end
        end
      end
    end

    def save(path : String = Paths.store_path) : Nil
      File.write(path, to_pretty_json)
    end

    def add_install(install : Install) : Nil
      installs.reject! { |i| i.path == install.path }
      installs << install
    end

    def remove_install(path : String) : Nil
      installs.reject! { |i| i.path == path }
    end

    def for_game(game_id : String) : Array(Install)
      installs.select { |i| i.game == game_id }
    end

    def find_by_path(path : String) : Install?
      installs.find { |i| i.path == path }
    end

    # Drop entries whose install dir no longer carries the marker file.
    def prune! : Array(Install)
      gone = installs.select { |i| !File.exists?(File.join(i.path, Paths::MARKER_NAME)) }
      installs.reject! { |i| gone.includes?(i) }
      gone
    end

    def self.next_id(game_id : String) : String
      "#{game_id}-#{Time.local.to_unix}"
    end
  end
end
