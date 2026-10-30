# xr-launcher GUI (egui.cr). The only file that pulls in the egui
# backend — headless builds (specs, CLI) never require it.
#
# Layout split:
#   * exml (assets/launcher.exml) owns the chrome — menu bar, settings
#     page, status bar, About modal — through the exml Runtime (store
#     slots + named actions), routed pages via ctx.router;
#   * native code owns the home: a ctx.side_panel game list (one
#     full-width game button: title + install info on one clickable
#     surface) and the central content (game page / install wizard).
#
# Every user-visible string goes through Launcher::L.t
# (config/locales/*.yml, embedded at compile time).

require "egui-cr/src/egui/backend_selector"
require "./launcher"
require "./launcher/i18n"

module Launcher
  module Assets
    def self.dir : String?
      candidates = [] of String
      if exe = Process.executable_path
        exe_dir = File.dirname(exe)
        candidates << File.join(exe_dir, "assets")
        candidates << File.join(exe_dir, "..", "assets")
        candidates << File.join(exe_dir, "..", "..", "launcher", "assets")
      end
      candidates << "assets"
      candidates.find { |c| Dir.exists?(c) }
    end

    def self.icon(name : String) : String?
      dir.try { |d| File.join(d, "icons", name) }
    end

    def self.exml_path : String?
      dir.try { |d| File.join(d, "launcher.exml") }
    end
  end

  class App < Egui::App
    COLOR_MUTED = Egui::Color32.new(160, 165, 175, 255)
    COLOR_OK    = Egui::Color32.new(120, 220, 120, 255)
    COLOR_WARN  = Egui::Color32.new(240, 200, 80, 255)
    COLOR_ERROR = Egui::Color32.new(240, 100, 100, 255)

    SETTINGS = "root/settings"

    # Compile-time fallback copy of the markup (resolved from the
    # compile working directory — launcher/ — like the i18n YAML embed):
    # the file next to the binary (hot-reloaded while it exists) wins,
    # the embedded document keeps a distributed binary self-contained.
    EXML_EMBEDDED = {{ read_file "assets/launcher.exml" }}

    @store = Store.load
    @status : String
    @wizard : WizardState? = nil
    @confirm_delete : String? = nil
    @selected = "cop"

    # exml side: parsed markup, one renderer, the store + actions.
    @exml : Egui::Exml::Document
    @renderer = Egui::Exml::Renderer.new
    @rt = Egui::Exml::Runtime.new

    def initialize
      super
      Locale.init(@store.locale)
      @status = L.t("status.ready")

      @store.prune!.each do |gone|
        @status = L.t("status.disappeared", path: gone.path)
      end
      @store.save

      @exml = self.class.load_exml
      lint_exml

      # The home element: inside the root/root page tree it opens the
      # sidebar panel and registers the deferred central panel, so both
      # complete inside ctx.page (the notepad <central> mechanism —
      # panels declared after render_routes would render into an empty
      # rect, the page bites the remainder).
      @renderer.on("launcher_home") do |node, ui, ctx, rt, renderer|
        ctx.side_panel(:left, id: "games", width: 250_f64) do |sidebar|
          draw_sidebar(ctx, sidebar)
        end
        ctx.central_panel do |content|
          if wizard = @wizard
            draw_wizard(ctx, content, wizard)
          else
            draw_game_page(ctx, content)
          end
        end
      end

      register_actions
    end

    # LAUNCHER_EXML env override, then assets/launcher.exml next to the
    # binary (hot-reloadable), else the embedded copy.
    def self.load_exml : Egui::Exml::Document
      candidates = [ENV["LAUNCHER_EXML"]?, Assets.exml_path].compact
      candidates.each do |c|
        return Egui::Exml::Document.load(c) if File.file?(c)
      end
      Egui::Exml::Document.parse(EXML_EMBEDDED)
    end

    private def lint_exml : Nil
      Egui::Exml.validate(@exml, known_custom: %w(launcher_home))
        .each { |i| STDERR.puts "exml: #{i}" }
    end

    def update(ctx : Egui::Context) : Nil
      @exml.reload_if_changed
      sync_store
      # exml renders the current route: menu bar + settings page /
      # About modal + status bar; on root/root the <launcher_home/>
      # element opens the sidebar + central panels inside the page.
      @renderer.render_routes(ctx, @exml, @rt)
    end

    # Model → exml store slots. All chrome strings are i18n slots
    # republished every frame, so a locale switch lands next frame.
    private def sync_store : Nil
      s = @rt.strings

      s["status"] = @status

      s["menu_file"] = L.t("menu.file")
      s["menu_settings"] = L.t("menu.settings")
      s["menu_help"] = L.t("menu.help")
      s["menu_refresh"] = L.t("menu.refresh")
      s["menu_quit"] = L.t("menu.quit")
      s["menu_settings_page"] = L.t("menu.settings_page")
      s["menu_about"] = L.t("menu.about")

      locale = I18n.locale
      s["lang_en_mark"] = locale == "en" ? "✓ " : ""
      s["lang_ru_mark"] = locale == "ru" ? "✓ " : ""
      s["locale_display"] = Locale::AVAILABLE[locale]? || "English"

      s["settings_title"] = L.t("settings.title")
      s["settings_language"] = L.t("settings.language")
      s["settings_language_note"] = L.t("settings.language_note")
      s["settings_store_line"] = L.t("settings.store_line", path: Paths.store_path)
      s["settings_back"] = L.t("settings.back")
      s["about_title"] = L.t("menu.about")
      s["about_text"] = L.t("about.text", version: VERSION)
    end

    # --- actions (fired from exml menus/buttons/combos) --------------------

    private def register_actions : Nil
      a = @rt.actions
      a["refresh"] = ->{
        @store = Store.load
        @store.prune!
        @store.save
        @status = L.t("status.refreshed")
      }
      a["quit"] = ->{ Egui::SystemPorts::Quit.quit! }
      a["settings"] = ->{ ctx.router.navigate(SETTINGS) }
      a["back"] = ->{ ctx.router.back }
      a["about"] = ->{ ctx.router.navigate("root/about") }
      a["about_ok"] = ->{ ctx.router.back }
      a["lang_en"] = ->{ set_locale("en") }
      a["lang_ru"] = ->{ set_locale("ru") }
      a["locale_changed"] = ->{
        case @rt.string("locale_display")
        when "Русский" then set_locale("ru")
        else               set_locale("en")
        end
      }
    end

    private def set_locale(locale : String) : Nil
      Locale.set(locale)
      @store.locale = locale
      @store.save
      @status = L.t("status.locale_saved", name: Locale::AVAILABLE[locale])
    end

    # --- the sidebar ---------------------------------------------------------

    private def draw_sidebar(ctx : Egui::Context, ui : Egui::Ui) : Nil
      ui.horizontal do |h|
        if (logo = Assets.icon("launcher_64.png")) && File.exists?(logo) &&
           (tex = ctx.load_image(logo)) > 0
          h.image(tex, Egui::Vec2.new(32.0, 32.0))
        end
        h.heading("OpenXRay")
      end
      ui.rich(muted(L.t("app.subtitle")))
      ui.separator

      Catalog.all.each do |game|
        draw_game_button(ui, game)
      end
    end

    # One game = one full-width clickable surface: the whole row (title
    # + install info) selects the game; selected/hover paint a filled
    # background across the sidebar width.
    private def draw_game_button(ui : Egui::Ui, game : Catalog::Game) : Nil
      selected = @selected == game.id
      installs = @store.for_game(game.id).size
      info = installs.zero? ? L.t("home.not_installed") : \
        L.t(installs == 1 ? "home.installs_count_one" : "home.installs_count", count: installs)

      size = ui.style.font_size
      pad = 8.0
      title_h = size * 1.25
      info_h = size * 0.85
      height = title_h + info_h + 2 * pad

      rect = ui.allocate_at_least(Egui::Vec2.new(ui.available_width, height))
      response = ui.interact(rect, Egui::Id.from("game-#{game.id}"), Egui::Sense.click)
      response.mark_changed if response.clicked?

      visuals = ui.style.visuals
      if selected
        ui.painter.rect(rect, 4.0, fill: visuals.selection_fill)
      elsif response.hovered?
        ui.painter.rect(rect, 4.0,
          fill: visuals.fade_color(visuals.selection_fill, 0.4_f64))
      end
      ui.painter.text(Egui::Pos2.new(rect.left + pad, rect.top + pad + title_h / 2),
        game_title(game), title_h, visuals.text_color, bold: true)
      ui.painter.text(Egui::Pos2.new(rect.left + pad, rect.top + pad + title_h + info_h / 2),
        info, info_h, COLOR_MUTED)

      if response.clicked?
        @selected = game.id
        @wizard = nil
        @confirm_delete = nil
      end
    end

    # --- the central content --------------------------------------------------

    private def game_title(game : Catalog::Game) : String
      L.t("games.#{game.id}.title")
    end

    private def muted(text : String) : Egui::RichText
      Egui::RichText.new(text).size(12.0).color(COLOR_MUTED)
    end

    private def draw_game_page(ctx : Egui::Context, ui : Egui::Ui) : Nil
      game = Catalog[@selected]

      ui.horizontal do |h|
        icon_path = Assets.icon("openxray_#{game.id}.png")
        if icon_path && File.exists?(icon_path) && (tex = ctx.load_image(icon_path)) > 0
          h.image(tex, Egui::Vec2.new(48.0, 48.0))
        end
        h.heading(game_title(game))
      end
      if game.experimental?
        ui.rich(Egui::RichText.new(L.t("home.experimental")).color(COLOR_WARN))
      end
      ui.rich(muted(L.t("games.#{game.id}.notes")), wrap: true)
      ui.separator

      installs = @store.for_game(game.id)
      if installs.empty?
        ui.label(L.t("home.no_installs"))
      else
        installs.each do |install|
          draw_install_row(ctx, ui, install)
          ui.separator
        end
      end

      if ui.big_button(L.t("home.install_button", title: game_title(game))).clicked?
        open_wizard
      end
    end

    private def open_wizard : Nil
      game = Catalog[@selected]
      @wizard = WizardState.new(game,
        engine: @store.recent_engine || "",
        source: @store.recent_sources[game.id]? || "")
    end

    private def draw_install_row(ctx : Egui::Context, ui : Egui::Ui, install : Store::Install) : Nil
      ui.label(File.expand_path(install.path))
      ui.rich(muted(L.t("home.created_line",
        created: install.created_at, engine: install.engine, source: install.source)), wrap: true)
      ui.horizontal do |h|
        if h.button(L.t("home.run")).clicked?
          begin
            Runner.run(install)
            @status = L.t("status.launched", path: install.path)
          rescue ex : InstallError | File::Error
            @status = L.t("status.launch_failed", message: ex.message)
          end
        end
        if h.button(L.t("home.open_folder")).clicked?
          @status = Egui::SystemPorts::RevealInFolder.show(install.path) \
            ? L.t("status.opened_folder", path: install.path) : L.t("status.no_file_manager")
        end
        if @confirm_delete == install.path
          if h.button(L.t("home.confirm_delete")).clicked?
            do_uninstall(install)
          end
          if h.button(L.t("home.cancel")).clicked?
            @confirm_delete = nil
          end
        elsif h.button(L.t("home.delete")).clicked?
          @confirm_delete = install.path
          @status = L.t("status.confirm_delete_status", path: install.path)
        end
      end
    end

    private def do_uninstall(install : Store::Install) : Nil
      begin
        Uninstaller.remove(install.path, @store) { |line| @status = line }
        @status = L.t("status.removed", path: install.path)
      rescue ex : Uninstaller::UnsafeDeleteError | File::Error
        @status = L.t("status.delete_failed", message: ex.message)
      end
      @confirm_delete = nil
    end

    # --- install wizard ------------------------------------------------------

    private def wizard_step_name(step : Int32) : String
      case step
      when 0 then L.t("wizard.steps.engine")
      when 1 then L.t("wizard.steps.source")
      else        L.t("wizard.steps.target")
      end
    end

    private def draw_wizard(ctx : Egui::Context, ui : Egui::Ui, w : WizardState) : Nil
      game = w.game
      ui.heading(L.t("home.install_button", title: game_title(game)).sub("…", ""))
      ui.rich(muted(L.t("wizard.step_of",
        step: w.step + 1, total: 3, name: wizard_step_name(w.step))))
      ui.separator

      case w.step
      when 0 then wizard_engine(ctx, ui, w)
      when 1 then wizard_source(ctx, ui, w)
      when 2 then wizard_target(ctx, ui, w)
      end

      ui.separator
      ui.horizontal do |h|
        if w.step > 0 && h.button(L.t("wizard.back")).clicked?
          w.step -= 1
          w.error = nil
        end
        if w.step < 2
          if h.button(L.t("wizard.next")).clicked? && w.error.nil?
            w.step += 1
          end
        else
          if h.big_button(L.t("wizard.install")).clicked? && w.error.nil?
            run_install(w)
          end
        end
        if h.button(L.t("wizard.cancel")).clicked?
          @wizard = nil
          @status = L.t("status.install_cancelled")
        end
      end

      if err = w.error
        ui.rich(Egui::RichText.new(err).color(COLOR_ERROR), wrap: true)
      end
    end

    private def wizard_engine(ctx : Egui::Context, ui : Egui::Ui, w : WizardState) : Nil
      ui.label(L.t("wizard.engine_intro"))
      ui.rich(muted(L.t("wizard.engine_layouts")), wrap: true)
      path_field(ctx, ui, :engine, w) { |dir|
        loc = Engine.resolve(dir)
        if loc.nil?
          L.t("errors.engine_missing_binaries", dir: dir)
        elsif loc.res_gamedata.empty?
          L.t("errors.engine_no_res_gamedata")
        else
          nil
        end
      }
    end

    private def wizard_source(ctx : Egui::Context, ui : Egui::Ui, w : WizardState) : Nil
      ui.label(L.t("wizard.source_intro", title: game_title(w.game)))
      ui.rich(muted(L.t("wizard.source_note")), wrap: true)
      path_field(ctx, ui, :source, w) do |dir|
        if key = Catalog.validate_source(w.game, dir)
          L.t(key)
        end
      end
    end

    private def wizard_target(ctx : Egui::Context, ui : Egui::Ui, w : WizardState) : Nil
      ui.label(L.t("wizard.target_intro"))
      w.target = File.join(Paths.default_installs_root, w.game.id) if w.target.empty?
      path_field(ctx, ui, :target, w) { |dir|
        if dir.empty?
          L.t("errors.target_empty")
        elsif File.exists?(dir) && !Dir.empty?(dir)
          L.t("errors.target_not_empty", path: dir)
        else
          nil
        end
      }
      ui.separator
      ui.label(L.t("wizard.will_create"))
      ui.rich(muted(L.t("wizard.will_create_body",
        target: w.target, mode: w.game.game_mode)), wrap: true)
    end

    # A path input row: editable text + folder picker; re-validates every
    # frame and stores the error on the wizard state.
    private def path_field(ctx : Egui::Context, ui : Egui::Ui,
                           field : Symbol, w : WizardState,
                           &validate : String -> String?) : Nil
      value = w.get(field)

      ui.horizontal do |h|
        if h.button(L.t("wizard.browse")).clicked?
          Egui::SystemPorts::PickFolderDialog.show(
            directory: value.empty? ? nil : value) do |picked|
            w.set(field, picked) if picked
          end
        end
        h.text_edit_singleline(value, hint: wizard_step_name(w.step)) { |text| w.set(field, text) }
      end

      err = validate.call(w.get(field))
      w.error = err
      if err
        ui.rich(Egui::RichText.new(err).color(COLOR_ERROR), wrap: true)
      else
        ui.rich(Egui::RichText.new(L.t("wizard.ok")).color(COLOR_OK))
      end
    end

    private def run_install(w : WizardState) : Nil
      @status = L.t("status.installing", title: game_title(w.game))
      begin
        install = Installer.install(w.game, w.source, w.engine, w.target, @store) { |line|
          @status = line
        }
        @status = L.t("status.installed", path: install.path)
        @selected = w.game.id
        @wizard = nil
      rescue ex : InstallError | File::Error
        w.error = ex.message.to_s
        @status = L.t("status.install_failed", message: ex.message)
      end
    end

    # Wizard state: the three paths plus the current step and validation
    # error. A plain class held by the app (immediate mode: the UI is
    # rebuilt from this every frame).
    class WizardState
      property game : Catalog::Game
      property step : Int32 = 0
      property engine : String
      property source : String
      property target : String = ""
      property error : String?

      def initialize(@game, @engine, @source)
      end

      def get(field : Symbol) : String
        case field
        when :engine then engine
        when :source then source
        when :target then target
        else raise ArgumentError.new("unknown wizard field #{field}")
        end
      end

      def set(field : Symbol, value : String) : Nil
        case field
        when :engine then @engine = value
        when :source then @source = value
        when :target then @target = value
        end
      end
    end
  end
end

# GUI entry: decode the window icon once, then hand control to egui.
if ARGV.empty?
  window_icon = nil
  if (icon_path = Launcher::Assets.icon("launcher_128.png")) && File.exists?(icon_path) &&
     (frame = Egui::ImageCodec.decode(File.read(icon_path).to_slice))
    window_icon = {rgba: frame.rgba, width: frame.width, height: frame.height}
  end
  Egui.run(Launcher::App.new,
    title: "OpenXRayLauncher #{Launcher::VERSION}",
    width: 980,
    height: 640,
    icon: window_icon)
else
  exit Launcher.cli(ARGV)
end
