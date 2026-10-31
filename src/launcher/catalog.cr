# Game catalog: everything the launcher needs to know about a supported
# S.T.A.L.K.E.R. game — how to recognize an owned copy, which parts of it
# to link into an install, which fsgame.ltx template to write and which
# engine mode flag to launch with.
#
# The fsgame.ltx templates are byte-identical to the field-tested portable
# rigs (see LAUNCHER.md): SoC needs `config\` (not `configs\`) and a
# root-scanning `$arch_dir$` to find its .db archives; CoP/CS point the
# `$arch_dir_*` roots at the unpacked level/resource folders.

module Launcher
  module Catalog
    struct Game
      getter id : String
      getter title : String
      getter mode_flag : String      # engine CLI switch
      getter game_mode : String      # [compatibility] game_mode in openxray.ltx
      getter config_dir : String     # gamedata/<config_dir>/ picks up openxray.ltx
      getter fsgame_ltx : String
      getter? experimental : Bool
      getter notes : String

      def initialize(@id, @title, @mode_flag, @game_mode, @config_dir,
                     @fsgame_ltx, @experimental = false, @notes = "")
      end
    end

    SOC_FSGAME = dedent(<<-LTX
      $app_data_root$\t\t= true|\tfalse|\t$fs_root$|\t\t_appdata_\\
      $arch_dir$\t\t= false|\tfalse|\t$fs_root$
      $game_data$   \t\t= false|\ttrue|\t$fs_root$|\t\tgamedata\\
      $game_ai$\t\t= true|\t\tfalse|\t$game_data$|\t\tai\\
      $game_spawn$\t\t= true|\t\tfalse|\t$game_data$|\t\tspawns\\
      $game_anims$\t\t= true|\t\ttrue|\t$game_data$|\t\tanims\\
      $game_levels$\t\t= true|\t\tfalse|\t$game_data$|\t\tlevels\\
      $game_meshes$\t\t= true|\t\ttrue|\t$game_data$|\t\tmeshes\\
      $game_dm$\t\t= true|\t\ttrue|\t$game_data$|\t\tmeshes\\
      $game_shaders$\t\t= true|\t\ttrue|\t$game_data$|\t\tshaders\\
      $game_sounds$\t\t= true|\t\ttrue|\t$game_data$|\t\tsounds\\
      $game_textures$\t\t= true|\t\ttrue|\t$game_data$|\t\ttextures\\
      $game_scripts$\t\t= true|\t\tfalse|\t$game_data$|\t\tscripts\\
      $game_config$\t\t= true|\t\tfalse|\t$game_data$|\t\tconfig\\
      $level$\t\t\t= false|\tfalse|\t$game_levels$
      $game_saves$\t\t= true|\t\tfalse|\t$app_data_root$|\tsavedgames\\
      $logs$\t\t\t= true|\t\tfalse|\t$app_data_root$|\tlogs\\
      $screenshots$\t\t= true|\t\tfalse|\t$app_data_root$|\tscreenshots\\
      LTX
    )

    # Crystal has no <<~ heredoc: strip the source-code indentation so
    # every fsgame.ltx line starts flush at '$'.
    private def self.dedent(text : String) : String
      text.gsub(/^[ \t]+(?=\$)/, "")
    end

    COP_FSGAME = dedent(<<-LTX
      $app_data_root$\t\t= true|false|$fs_root$|_appdata_\\
      $arch_dir$\t\t= false| false| $fs_root$
      $game_arch_mp$\t\t= false| false| $fs_root$|\t\t    mp\\
      $arch_dir_levels$\t= false| false| $fs_root$|\t\t    levels\\
      $arch_dir_resources$\t= false| false| $fs_root$|\t\t    resources\\
      $arch_dir_localization$\t= false| false| $fs_root$|\t\t    localization\\
      $arch_dir_patches$\t= false| true|  $fs_root$|\t\t    patches\\
      $game_data$\t\t= false|\ttrue|\t$fs_root$|\t\tgamedata\\
      $game_ai$\t\t= true|\t\tfalse|\t$game_data$|\t\tai\\
      $game_spawn$\t\t= true|\t\tfalse|\t$game_data$|\t\tspawns\\
      $game_levels$\t\t= true|\t\tfalse|\t$game_data$|\t\tlevels\\
      $game_meshes$\t\t= true|\t\ttrue|\t$game_data$|\t\tmeshes\\|       *.ogf;*.omf|   Game Object files
      $game_anims$\t\t= true|\t\ttrue|\t$game_data$|\t\tanims\\|        *.anm;*.anms|  Animation files
      $game_dm$\t\t= true|\t\ttrue|\t$game_data$|\t\tmeshes\\|\t       *.dm|\t\t  Detail Model files
      $game_shaders$\t\t= true|\t\ttrue|\t$game_data$|\t\tshaders\\
      $game_sounds$\t\t= true|\t\ttrue|\t$game_data$|\t\tsounds\\
      $game_textures$\t\t= true|\t\ttrue|\t$game_data$|\t\ttextures\\
      $game_config$\t\t= true|\t\tfalse|\t$game_data$|\t\tconfigs\\
      $game_weathers$\t\t= true|  false|\t$game_config$|\t        environment\\weathers
      $game_weather_effects$\t= true|  false|\t$game_config$|\t        environment\\weather_effects
      $textures$\t\t= true|  true|  $game_data$|\t\t  textures\\
      $level$\t\t\t= false|\tfalse|\t$game_levels$
      $game_scripts$\t\t= true|  false|\t$game_data$|\t\t  scripts\\|\t      *.script|\t      Game script files
      $logs$\t\t\t= true|\t\tfalse|\t$app_data_root$|\tlogs\\
      $screenshots$\t\t= true|\t\tfalse|\t$app_data_root$|\tscreenshots\\
      $game_saves$\t\t= true|\t\tfalse|\t$app_data_root$|\tsavedgames\\
      $downloads$\t\t= false| false| $app_data_root$
      LTX
    )

    GAMES = {
      "soc" => Game.new(
        id: "soc", title: "S.T.A.L.K.E.R.: Shadow of Chernobyl",
        mode_flag: "-shoc", game_mode: "shoc", config_dir: "config",
        fsgame_ltx: SOC_FSGAME,
        experimental: true,
        notes: "Not an officially supported engine platform yet, but it runs " \
               "(see OpenXRay issue #392). Configs and scripts come from the .db archives; " \
               "only gamedata/config/openxray.ltx is overlaid."
      ),
      "cs" => Game.new(
        id: "cs", title: "S.T.A.L.K.E.R.: Clear Sky",
        mode_flag: "-cs", game_mode: "cs", config_dir: "configs",
        fsgame_ltx: COP_FSGAME,
        experimental: true,
        notes: "The engine has a -cs mode, but it is untested. " \
               "Treated like CoP: unpacked folders are linked, .db archives root-scanned."
      ),
      "cop" => Game.new(
        id: "cop", title: "S.T.A.L.K.E.R.: Call of Pripyat",
        mode_flag: "-cop", game_mode: "cop", config_dir: "configs",
        fsgame_ltx: COP_FSGAME,
        notes: "The engine's native platform. GOG/Steam installs ship unpacked " \
               "levels/resources/localization/mp/patches plus gamedata/configs+scripts; " \
               "all of it is linked and the engine's updated scripts are overlaid on top."
      ),
    }

    def self.all : Array(Game)
      GAMES.values.to_a
    end

    def self.[](id : String) : Game
      GAMES[id]? || raise ArgumentError.new("unknown game #{id.inspect} " \
        "(expected one of: #{GAMES.keys.join(", ")})")
    end

    def self.[]?(id : String) : Game?
      GAMES[id]?
    end

    # Unpacked asset roots linked next to fsgame.ltx for CoP/CS-layout
    # sources (present ones only).
    ASSET_DIRS = {"levels", "localization", "mp", "patches", "resources"}

    # Validate a candidate game source directory. Returns nil when the
    # directory looks like this game's install, or an i18n error KEY
    # (render it with Launcher::L.t) saying why it does not.
    def self.validate_source(game : Game, dir : String) : String?
      return "errors.source_not_found" unless Dir.exists?(dir)

      case game.id
      when "soc"
        archives = Dir.glob(File.join(dir, "gamedata.db*"))
        return "errors.source_soc_none" if archives.empty?
      when "cs"
        found = ASSET_DIRS.any? { |d| Dir.exists?(File.join(dir, d)) } ||
                !Dir.glob(File.join(dir, "*.db*")).empty?
        return "errors.source_cs_none" unless found
      when "cop"
        found = ASSET_DIRS.any? { |d| Dir.exists?(File.join(dir, d)) } ||
                !Dir.glob(File.join(dir, "gamedata.db*")).empty?
        return "errors.source_cop_none" unless found
      end
      nil
    end

    # Validate an ALREADY-ASSEMBLED distribution folder (the wizard's
    # "use an existing folder" branch): everything the game needs to
    # actually start — fsgame.ltx at the root, the engine binary plus
    # its shared modules in bin/, the GL shaders, and the game data
    # itself (an assembled install mirrors the source copy's data
    # markers at its root, so the source check closes the list).
    # Returns nil when the folder looks runnable, or an i18n error KEY.
    def self.validate_install(game : Game, dir : String) : String?
      return "errors.source_not_found" unless Dir.exists?(dir)
      return "errors.existing_no_fsgame" unless File.exists?(File.join(dir, "fsgame.ltx"))

      bin = File.join(dir, "bin")
      modules = Dir.exists?(bin) && Dir.children(bin).any? do |name|
        name.matches?({% if flag?(:win32) %} /\.dll$/i {% else %} /\.so$/ {% end %})
      end
      return "errors.existing_no_bin" unless modules &&
                                            File.exists?(File.join(bin, Engine.executable_name))

      return "errors.existing_no_shaders" unless Dir.exists?(
        File.join(dir, "gamedata", "shaders", "gl"))

      validate_source(game, dir)
    end
  end
end
