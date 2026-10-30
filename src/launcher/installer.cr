# Assemble a playable OpenXRay distribution for one game, mirroring the
# field-tested portable layout:
#
#   <dir>/                     install root; xr_3da is started with cwd here,
#     fsgame.ltx               per-game FS layout (portable mode: the engine
#                              picks fsgame.ltx from the working directory)
#     .installed_ok            JSON marker: install provenance + validity
#     bin/                     per-file symlinks to the engine build
#     gamedata/
#       shaders/gl -> engine   GL shader pack (mandatory on OpenGL builds)
#       config[s]/openxray.ltx
#                              [compatibility] game_mode = <mode>
#       configs/...            (CoP/CS) unpacked configs linked from the
#                              original copy, openxray.ltx added alongside
#       scripts/               (CoP/CS) original scripts copied, then the
#                              engine's updated res/gamedata/scripts on top
#     _appdata_/{savedgames,logs,screenshots}
#     gamedata.db* / levels/ / resources/ ...   game data symlinked in place
#
# Nothing owned is duplicated except small script files: archives and
# unpacked assets stay in the original copy and are referenced by symlink
# (Windows without symlink privileges falls back to copying).

require "json"
require "./catalog"
require "./i18n"
require "./engine"
require "./paths"
require "./store"

module Launcher
  class InstallError < Exception
  end

  module Installer
    VERSION = 1

    def self.install(game : Catalog::Game, source : String, engine_dir : String,
                     target : String, store : Store? = nil,
                     &log : String -> Nil) : Store::Install
      source = File.expand_path(source)
      engine_dir = File.expand_path(engine_dir)
      target = File.expand_path(target)

      if err = Catalog.validate_source(game, source)
        raise InstallError.new(L.t("errors.engine_prefix", message: L.t(err)))
      end
      engine = Engine.resolve(engine_dir) ||
        raise InstallError.new(L.t("errors.engine_no_binaries"))

      if File.exists?(target)
        raise InstallError.new(L.t("errors.target_exists", path: target)) unless Dir.exists?(target)
        raise InstallError.new(L.t("errors.target_not_empty", path: target)) unless Dir.empty?(target)
      end
      if target == "/" || target == File.dirname(target)
        raise InstallError.new(L.t("errors.target_root", path: target))
      end
      parent = File.dirname(target)
      raise InstallError.new(L.t("errors.parent_missing", path: parent)) unless Dir.exists?(parent)

      log.call(L.t("install.creating", path: target))
      Dir.mkdir(target)

      begin
        # 1. engine binaries
        Dir.mkdir(File.join(target, "bin"))
        linked = 0
        Engine.bin_files(engine.bin_dir).each do |name|
          link_or_copy(File.join(engine.bin_dir, name), File.join(target, "bin", name))
          linked += 1
        end
        raise InstallError.new(L.t("errors.engine_no_res", dir: engine.bin_dir)) if linked.zero?
        log.call(L.t("install.bin_linked", count: linked))

        # 2. game data at the install root (symlinks into the original copy)
        assets = 0
        case game.id
        when "soc"
          Dir.glob(File.join(source, "gamedata.db*")).sort.each do |archive|
            link_or_copy(archive, File.join(target, File.basename(archive)))
            assets += 1
          end
        else
          Catalog::ASSET_DIRS.each do |dir|
            next unless Dir.exists?(File.join(source, dir))
            link_or_copy(File.join(source, dir), File.join(target, dir))
            assets += 1
          end
          Dir.glob(File.join(source, "*.db*")).sort.each do |archive|
            next if File.basename(archive).starts_with?("unins")
            link_or_copy(archive, File.join(target, File.basename(archive)))
            assets += 1
          end
        end
        raise InstallError.new(L.t("errors.no_game_data", source: source)) if assets.zero?
        log.call(L.t("install.assets_linked", count: assets))

        # 3. gamedata overlay
        gamedata = File.join(target, "gamedata")
        Dir.mkdir(gamedata)

        # GL shaders from the engine overlay (mandatory for rendering)
        if !engine.res_gamedata.empty?
          Dir.mkdir(File.join(gamedata, "shaders"))
          link_or_copy(File.join(engine.res_gamedata, "shaders", "gl"),
            File.join(gamedata, "shaders", "gl"))
          log.call(L.t("install.shaders_linked"))
        else
          log.call(L.t("install.shaders_missing"))
        end

        # per-game config/scripts overlays
        case game.id
        when "soc"
          # configs and scripts live inside the .db archives; overlay only
          # our own openxray.ltx
          Dir.mkdir(File.join(gamedata, "config"))
        else
          src_scripts = File.join(source, "gamedata", "scripts")
          if Dir.exists?(src_scripts)
            copy_children(src_scripts, File.join(gamedata, "scripts"))
          end
          # engine's updated scripts win over the shipped ones
          engine_scripts = File.join(engine.res_gamedata, "scripts")
          if !engine.res_gamedata.empty? && Dir.exists?(engine_scripts)
            copy_children(engine_scripts, File.join(gamedata, "scripts"))
          end
          src_configs = File.join(source, "gamedata", "configs")
          Dir.mkdir(File.join(gamedata, "configs"))
          link_children(src_configs, File.join(gamedata, "configs")) if Dir.exists?(src_configs)
        end

        # openxray.ltx with the game mode (belt) + mode flag on launch (braces)
        File.write(File.join(gamedata, game.config_dir, "openxray.ltx"),
          openxray_ltx(game))
        log.call(L.t("install.openxray_written", dir: game.config_dir, mode: game.game_mode))

        # 4. per-game FS layout (portable mode)
        File.write(File.join(target, "fsgame.ltx"), game.fsgame_ltx)
        log.call(L.t("install.fsgame_written"))

        # 5. local app data
        appdata = File.join(target, "_appdata_")
        {"savedgames", "logs", "screenshots"}.each do |sub|
          Dir.mkdir_p(File.join(appdata, sub))
        end
        log.call(L.t("install.appdata_created"))

        # 6. marker + store registration
        install = Store::Install.new(
          id: Store.next_id(game.id),
          game: game.id,
          path: target,
          engine: engine_dir,
          source: source,
          created_at: Time.local.to_rfc3339
        )
        File.write(File.join(target, Paths::MARKER_NAME), marker_json(install))
        log.call(L.t("install.marker_written"))

        if store
          store.add_install(install)
          store.recent_engine = engine_dir
          store.recent_sources[game.id] = source
          store.save
        end
        log.call(L.t("install.done", title: game.title, path: target))
        install
      rescue ex
        # Don't leave a half-built install behind for the uninstaller to
        # trip over — roll back what we created (source files are never
        # touched: everything created here is a symlink or a copy).
        log.call(L.t("install.failed_rollback", message: ex.message))
        Uninstaller.remove_dir(target)
        raise ex
      end
    end

    def self.marker_json(install : Store::Install) : String
      JSON.build do |json|
        json.object do
          json.field "launcher_version", VERSION
          json.field "game", install.game
          json.field "engine", install.engine
          json.field "source", install.source
          json.field "created_at", install.created_at
        end
      end
    end

    def self.openxray_ltx(game : Catalog::Game) : String
      <<-LTX
      ; Written by xr-launcher — per-game mode for this distribution.
      [compatibility]
      game_mode = #{game.game_mode}

      LTX
    end

    # --- filesystem helpers -------------------------------------------------

    # Symlink `src` (file or directory) at `dst`; when symlinks are not
    # available (Windows without developer mode) fall back to a deep copy.
    def self.link_or_copy(src : String, dst : String) : Nil
      begin
        File.delete(dst) if File.symlink?(dst)
        File.symlink(src, dst)
      rescue ex : File::Error
        copy_entry(src, dst)
      end
    end

    # Symlink every child of `src` into `dst` (created if missing).
    def self.link_children(src : String, dst : String) : Nil
      Dir.mkdir(dst) unless Dir.exists?(dst)
      Dir.children(src).each do |name|
        link_or_copy(File.join(src, name), File.join(dst, name))
      end
    end

    # Copy every FILE child of `src` into `dst` (created if missing).
    # Used for scripts: they must be real files so the engine's overlay
    # can selectively replace them.
    def self.copy_children(src : String, dst : String) : Nil
      Dir.mkdir(dst) unless Dir.exists?(dst)
      Dir.children(src).each do |name|
        next if name.starts_with?(".")
        full = File.join(src, name)
        File.copy(full, File.join(dst, name)) if File.file?(full)
      end
    end

    # Deep copy that never follows symlinks (copies them as symlinks).
    def self.copy_entry(src : String, dst : String) : Nil
      if File.symlink?(src)
        File.symlink(File.readlink(src), dst)
      elsif Dir.exists?(src)
        Dir.mkdir(dst)
        Dir.children(src).each do |name|
          copy_entry(File.join(src, name), File.join(dst, name))
        end
      else
        File.copy(src, dst)
      end
    end
  end
end
