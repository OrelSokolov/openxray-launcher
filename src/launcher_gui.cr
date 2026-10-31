# xr-launcher GUI (egui.cr). The only file that pulls in the egui
# backend — headless builds (specs, CLI) never require it.
#
# Layout split:
#   * exml (assets/launcher.exml) owns the chrome — menu bar, settings
#     page, status bar, About modal — through the exml Runtime (store
#     slots + named actions), routed pages via ctx.router;
#   * native code owns the home: a ctx.side_panel game list (one
#     full-width game button: title + install info on one clickable
#     surface) and the central game page; the install wizard is an
#     Egui::Wizard embedded window shown over it.
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

    # The "Modified game" pseudo-entry: not a catalog game but a wizard
    # flavor where the user picks the engine compatibility mode.
    MOD_ID           = "mod"
    MOD_DEFAULT_MODE = "cop"

    # Compile-time fallback copy of the markup (resolved from the
    # compile working directory — launcher/ — like the i18n YAML embed):
    # the file next to the binary (hot-reloaded while it exists) wins,
    # the embedded document keeps a distributed binary self-contained.
    EXML_EMBEDDED = {{ read_file "assets/launcher.exml" }}

    @store = Store.load
    @status : String
    @wizard : WizardState? = nil
    @logs : LogsState? = nil
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
          if logs = @logs
            draw_logs_page(ctx, content, logs)
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
      # The install wizard on top, once opened — after the page so the
      # embedded window layers above it.
      draw_install_wizard(ctx)
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
      s["about_title"] = L.t("menu.about")
      s["about_text"] = L.t("about.text", version: VERSION)
    end

    # --- actions (fired from exml menus/buttons/combos) --------------------

    private def register_actions : Nil
      a = @rt.actions
      a["refresh"] = ->{
        @store = Store.load
        @status = L.t("status.refreshed")
      }
      a["quit"] = ->{ Egui::SystemPorts::Quit.quit! }
      a["settings"] = ->{ ctx.router.navigate(SETTINGS) }
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

      ui.separator
      mods = @store.custom_installs.size
      info = mods.zero? ? L.t("home.not_installed") : \
        L.t(mods == 1 ? "home.installs_count_one" : "home.installs_count", n: mods)
      draw_sidebar_entry(ui, id: MOD_ID, title: L.t("games.mod.title"), info: info)
    end

    # One game = one full-width clickable surface: the whole row (title
    # + install info) selects the game; selected/hover paint a filled
    # background across the sidebar width.
    private def draw_game_button(ui : Egui::Ui, game : Catalog::Game) : Nil
      # NOTE: the param must NOT be named `count` — crystal-i18n treats
      # that as pluralization and looks up `key.one/.other` sub-keys.
      installs = @store.for_game(game.id).count { |i| !i.custom? }
      info = installs.zero? ? L.t("home.not_installed") : \
        L.t(installs == 1 ? "home.installs_count_one" : "home.installs_count", n: installs)
      draw_sidebar_entry(ui, id: game.id, title: sidebar_title(game), info: info)
    end

    # The clickable row itself: title + muted info line, selection and
    # hover painted across the full sidebar width.
    private def draw_sidebar_entry(ui : Egui::Ui, id : String,
                                   title : String, info : String) : Nil
      selected = @selected == id

      size = ui.style.font_size
      pad = 8.0
      title_h = size * 1.25
      info_h = size * 0.85
      height = title_h + info_h + 2 * pad

      rect = ui.allocate_at_least(Egui::Vec2.new(ui.available_width, height))
      response = ui.interact(rect, Egui::Id.from("game-#{id}"), Egui::Sense.click)
      response.mark_changed if response.clicked?

      visuals = ui.style.visuals
      if selected
        ui.painter.rect(rect, 4.0, fill: visuals.selection_fill)
      elsif response.hovered?
        ui.painter.rect(rect, 4.0,
          fill: visuals.fade_color(visuals.selection_fill, 0.4_f64))
      end
      ui.painter.text(Egui::Pos2.new(rect.left + pad, rect.top + pad + title_h / 2),
        title, title_h, visuals.text_color, bold: true)
      ui.painter.text(Egui::Pos2.new(rect.left + pad, rect.top + pad + title_h + info_h / 2),
        info, info_h, COLOR_MUTED)

      if response.clicked?
        @selected = id
        @wizard = nil
        @logs = nil
        @confirm_delete = nil
      end
    end

    # --- the central content --------------------------------------------------

    private def game_title(game : Catalog::Game) : String
      L.t("games.#{game.id}.title")
    end

    # Sidebar rows drop the "S.T.A.L.K.E.R.:" franchise prefix — it
    # would repeat in every entry under the same logo. The full title
    # stays on the game page heading.
    private def sidebar_title(game : Catalog::Game) : String
      game_title(game).sub(/^S\.T\.A\.L\.K\.E\.R\.:\s*/, "")
    end

    private def muted(text : String) : Egui::RichText
      Egui::RichText.new(text).size(12.0).color(COLOR_MUTED)
    end

    # A text button with a lucide icon left of the label. The icon is
    # embedded at compile time (`Icon.from_file`) and tinted with the
    # live theme text color; the parse is cached per tint, so a
    # per-frame call site is cheap.
    private def icon_button(ui : Egui::Ui, text : String, icon : Egui::Svg) : Egui::Response
      ui.add(Egui::Button.new(text).icon(icon))
    end

    private def draw_game_page(ctx : Egui::Context, ui : Egui::Ui) : Nil
      return draw_mod_page(ctx, ui) if @selected == MOD_ID
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

      installs = @store.for_game(game.id).reject(&.custom?)
      if installs.empty?
        ui.label(L.t("home.no_installs"))
      else
        installs.each do |install|
          draw_install_row(ctx, ui, install)
          ui.separator
        end
      end

      # First install: the big Install button; anything already
      # installed: the same wizard entry, renamed and re-iconed.
      install_btn = installs.empty? ?
        ui.big_button(L.t("home.install_button", title: game_title(game)),
          icon: Egui::Icon.from_file(:lucide, :download, tint: ui.style.visuals.text_color)) :
        ui.big_button(L.t("home.add_more"),
          icon: Egui::Icon.from_file(:lucide, :plus, tint: ui.style.visuals.text_color))
      open_wizard if install_btn.clicked?
    end

    # The "Modified game" page: same shape as a game page, but each
    # install carries its own compatibility mode (shown per row) and
    # the wizard gains the mode-select step.
    private def draw_mod_page(ctx : Egui::Context, ui : Egui::Ui) : Nil
      ui.heading(L.t("games.mod.title"))
      ui.rich(muted(L.t("games.mod.notes")), wrap: true)
      ui.separator

      installs = @store.custom_installs
      if installs.empty?
        ui.label(L.t("home.no_installs"))
      else
        installs.each do |install|
          mode_game = Catalog[install.game]? # install.game = the chosen compat mode
          draw_install_row(ctx, ui, install,
            subtitle: mode_game ? game_title(mode_game) : nil)
          ui.separator
        end
      end

      install_btn = installs.empty? ?
        ui.big_button(L.t("home.install_button", title: L.t("games.mod.title")),
          icon: Egui::Icon.from_file(:lucide, :download, tint: ui.style.visuals.text_color)) :
        ui.big_button(L.t("home.add_more"),
          icon: Egui::Icon.from_file(:lucide, :plus, tint: ui.style.visuals.text_color))
      open_wizard(mod: true) if install_btn.clicked?
    end

    private def draw_install_row(ctx : Egui::Context, ui : Egui::Ui,
                                 install : Store::Install, subtitle : String? = nil) : Nil
      ui.label(File.expand_path(install.path))
      ui.rich(muted(subtitle), wrap: true) if subtitle
      ui.rich(muted(L.t("home.created_line",
        created: install.created_at, engine: install.engine, source: install.source)), wrap: true)

      # Play: the big full-width button, like Install on the game page.
      if ui.big_button(L.t("home.run"),
          icon: Egui::Icon.from_file(:lucide, :play, tint: ui.style.visuals.text_color)).clicked?
        begin
          Runner.run(install)
          @status = L.t("status.launched", path: install.path)
        rescue ex : InstallError | File::Error
          @status = L.t("status.launch_failed", message: ex.message)
        end
      end

      ui.horizontal do |h|
        fg = h.style.visuals.text_color
        if icon_button(h, L.t("home.logs"),
            Egui::Icon.from_file(:lucide, :scroll_text, tint: fg)).clicked?
          @wizard = nil
          @logs = LogsState.new(install)
        end
        if icon_button(h, L.t("home.open_folder"),
            Egui::Icon.from_file(:lucide, :folder_open, tint: fg)).clicked?
          # FileOpen (not RevealInFolder): the button must open the
          # install folder ITSELF — Reveal* opens the PARENT with the
          # folder selected (xdg-open dirname / explorer /select).
          @status = Egui::SystemPorts::FileOpen.show(install.path) \
            ? L.t("status.opened_folder", path: install.path) : L.t("status.no_file_manager")
        end
        if @confirm_delete == install.path
          if icon_button(h, L.t("home.confirm_delete"),
              Egui::Icon.from_file(:lucide, :trash, tint: fg)).clicked?
            do_uninstall(install)
          end
          if icon_button(h, L.t("home.cancel"),
              Egui::Icon.from_file(:lucide, :x, tint: fg)).clicked?
            @confirm_delete = nil
          end
        elsif icon_button(h, L.t("home.delete"),
            Egui::Icon.from_file(:lucide, :trash, tint: fg)).clicked?
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

    # --- logs / crash inspector page ----------------------------------------

    private def draw_logs_page(ctx : Egui::Context, ui : Egui::Ui, logs : LogsState) : Nil
      install = logs.install
      ui.heading(L.t("logs.title"))
      ui.label(File.expand_path(install.path))
      ui.rich(muted(L.t("logs.dir_line",
        path: File.join(install.path, "_appdata_", "logs"))), wrap: true)
      ui.separator

      fg = ui.style.visuals.text_color
      ui.horizontal do |h|
        if h.big_button(L.t("logs.analyze"),
            icon: Egui::Icon.from_file(:lucide, :search, tint: fg)).clicked?
          report = LogAnalyzer.scan(install)
          logs.report = report
          logs.markdown = logs_report_markdown(install, report)
        end
        if (md = logs.markdown) &&
           icon_button(h, L.t("logs.copy_report"),
            Egui::Icon.from_file(:lucide, :clipboard_list, tint: fg)).clicked?
          Egui::SystemPorts::Clipboard.text = md
          @status = L.t("status.report_copied")
        end
        if logs.confirm_clear?
          if icon_button(h, L.t("logs.confirm_clear"),
              Egui::Icon.from_file(:lucide, :trash, tint: fg)).clicked?
            do_clear_logs(logs)
          end
          if icon_button(h, L.t("logs.cancel"),
              Egui::Icon.from_file(:lucide, :x, tint: fg)).clicked?
            logs.confirm_clear = false
          end
        elsif icon_button(h, L.t("logs.clear"),
            Egui::Icon.from_file(:lucide, :trash, tint: fg)).clicked?
          logs.confirm_clear = true
        end
        if icon_button(h, L.t("logs.back"),
            Egui::Icon.from_file(:lucide, :arrow_left, tint: fg)).clicked?
          @logs = nil
        end
      end

      if md = logs.markdown
        ui.separator
        # The report can grow past the panel — it scrolls inside the
        # remaining height (header + buttons stay pinned above).
        ui.scroll_area do |s|
          s.markdown(md, id: "logs-report")
        end
      end
    end

    private def do_clear_logs(logs : LogsState) : Nil
      begin
        n = LogAnalyzer.clear(logs.install)
        # The old report describes deleted files — drop it, the next
        # Analyze rebuilds it from whatever the next run produces.
        logs.report = nil
        logs.markdown = nil
        @status = L.t("status.logs_cleared", n: n)
      rescue ex : File::Error
        @status = L.t("status.delete_failed", message: ex.message)
      end
      logs.confirm_clear = false
    end

    private def finding_line(title : String, finding : LogAnalyzer::Finding) : String
      finding.any? ?
        L.t("logs.finding_bad", title: title, n: finding.count) :
        L.t("logs.finding_ok", title: title)
    end

    # The whole analysis as a markdown document — what the page renders
    # through ui.markdown and what "Copy report" puts on the clipboard
    # (pasteable into an issue or a chat). Paths go into `code` chips so
    # underscores like _appdata_ never light up as markup.
    private def logs_report_markdown(install : Store::Install,
                                     report : LogAnalyzer::Report) : String
      log_dir = File.join(install.path, "_appdata_", "logs")
      String.build do |s|
        s << "## " << L.t("logs.title") << '\n'
        s << '`' << File.expand_path(install.path) << "`\n\n"
        s << L.t("logs.dir_line", path: "`#{log_dir}`") << "\n\n"
        s << L.t("logs.files_line", n: report.files.size, lines: report.lines) << "\n\n"
        if report.files.empty?
          s << "> " << L.t("logs.no_logs") << '\n'
        else
          verdict = report.crashes.any? ?
            L.t("logs.verdict_bad", n: report.crashes.count) : L.t("logs.verdict_ok")
          s << "**" << verdict << "**\n\n"
          {L.t("logs.crashes")  => report.crashes,
           L.t("logs.textures") => report.textures,
           L.t("logs.scripts")  => report.scripts,
           L.t("logs.warnings") => report.warnings}.each do |title, finding|
            s << "- **" << finding_line(title, finding) << "**\n"
            finding.samples.each { |sample| s << "  - `" << sample << "`\n" }
          end
        end
      end
    end

    # --- install wizard ------------------------------------------------------

    # The install wizard on the egui.cr Wizard component: banner +
    # scrollable step bodies + the Back/Next/Cancel footer, shown as an
    # embedded window over the game page. WizardState carries the
    # paths; the step bodies re-read it every frame (immediate mode).
    # Text is a snapshot taken at open — a locale switch lands on the
    # next wizard run.

    private def wizard_title(w : WizardState) : String
      w.mod? ? L.t("games.mod.title") : game_title(w.game)
    end

    private def open_wizard(mod : Bool = false) : Nil
      if mod
        game = Catalog[MOD_DEFAULT_MODE]
        source = @store.recent_sources[MOD_ID]? || ""
      else
        game = Catalog[@selected]
        source = @store.recent_sources[game.id]? || ""
      end
      w = WizardState.new(game,
        engine: @store.recent_engine || "",
        source: source, mod: mod)
      w.wizard = build_wizard(w)
      @wizard = w
    end

    # The wizard forks on its FIRST step: register an already assembled
    # game folder as-is, or assemble a new distribution from scratch
    # (engine [+ compatibility mode for a mod] → source → target). The
    # choice step's on_next rewrites the step list past the fork point
    # (Engine, source, target steps for scratch; a single existing-
    # folder step otherwise). Each step re-validates its path every
    # frame into `w.error`, which gates Next via `can_next`.
    private def build_wizard(w : WizardState) : Egui::Wizard
      # --- the fork ----------------------------------------------------------

      choice = Egui::WizardStep.new(L.t("wizard.steps.choice")) do |ui|
        ui.label(L.t("wizard.choice_intro"))
        ui.allocate_space(Egui::Vec2.new(0.0, 8.0))
        if ui.radio(!w.existing?, L.t("wizard.choice_scratch")).clicked?
          w.existing = false
        end
        ui.rich(muted(L.t("wizard.choice_scratch_note")), wrap: true)
        ui.allocate_space(Egui::Vec2.new(0.0, 8.0))
        if ui.radio(w.existing?, L.t("wizard.choice_existing")).clicked?
          w.existing = true
        end
        ui.rich(muted(L.t("wizard.choice_existing_note")), wrap: true)
      end

      # Modified game only: pick the engine compatibility mode. The
      # choice rewrites the wizard's base game, so every later step
      # (source validation, fsgame.ltx, launch flag) follows it. It
      # sits BEFORE the fork — the mode applies to both branches.
      mode : Egui::WizardStep? = nil
      if w.mod?
        mode = Egui::WizardStep.new(L.t("wizard.steps.mode")) do |ui|
          ui.label(L.t("wizard.mode_intro"))
          ui.rich(muted(L.t("wizard.mode_note")), wrap: true)

          options = Catalog.all.map { |g| sidebar_title(g) }
          ui.combo_box("wizard-mode", sidebar_title(w.game), options) do |picked|
            Catalog.all.each do |g|
              w.game = g if sidebar_title(g) == picked
            end
          end

          ui.separator
          ui.rich(muted(L.t("wizard.mode_selected_line",
            title: game_title(w.game), mode: w.game.game_mode, flag: w.game.mode_flag)), wrap: true)
        end
      end

      # --- scratch branch ----------------------------------------------------

      engine = Egui::WizardStep.new(L.t("wizard.steps.engine")) do |ui|
        ui.label(L.t("wizard.engine_intro"))
        ui.rich(muted(L.t("wizard.engine_layouts")), wrap: true)
        path_field(ui, :engine, w, L.t("wizard.steps.engine")) { |dir|
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
      engine.can_next { |_wiz| w.error.nil? }

      source = Egui::WizardStep.new(L.t("wizard.steps.source")) do |ui|
        intro = w.mod? ? "wizard.source_intro_mod" : "wizard.source_intro"
        ui.label(L.t(intro, title: game_title(w.game)))
        ui.rich(muted(L.t("wizard.source_note")), wrap: true)
        path_field(ui, :source, w, L.t("wizard.steps.source")) do |dir|
          if key = Catalog.validate_source(w.game, dir)
            L.t(key)
          end
        end
      end
      source.can_next { |_wiz| w.error.nil? }

      # The last step replaces the footer's Finish with a custom
      # Install: the component's Finish closes the wizard
      # unconditionally, while a FAILED install must keep it open on
      # this step so the user can fix the target and retry.
      target = Egui::WizardStep.new(L.t("wizard.steps.target")) do |ui|
        ui.label(L.t("wizard.target_intro"))
        if w.target.empty?
          w.target = File.join(Paths.default_installs_root,
            w.mod? ? "mod-#{w.game.id}" : w.game.id)
        end
        path_field(ui, :target, w, L.t("wizard.steps.target")) { |dir|
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
      target.buttons = [
        Egui::Wizard::Button.back(L.t("wizard.back")),
        Egui::Wizard::Button.custom(L.t("wizard.install")) do |wiz|
          run_install(w) if w.error.nil?
          wiz.finish! unless w.failed?
        end,
        Egui::Wizard::Button.cancel(L.t("wizard.cancel")),
      ]

      # --- existing-folder branch --------------------------------------------

      # One step: point at an assembled distribution. The full
      # "runnable" check (fsgame.ltx, engine binary + modules, GL
      # shaders, game data) lives in Catalog.validate_install and is
      # shared with register_install. Registering is bookkeeping only
      # (the standard Finish button suffices — nothing can half-fail),
      # so no custom footer here.
      existing = Egui::WizardStep.new(L.t("wizard.steps.existing")) do |ui|
        ui.label(L.t("wizard.existing_intro"))
        ui.rich(muted(L.t("wizard.existing_note")), wrap: true)
        path_field(ui, :existing, w, L.t("wizard.steps.existing")) do |dir|
          Catalog.validate_install(w.game, dir).try { |key| L.t(key) }
        end
      end
      existing.finish_label = L.t("wizard.register")

      # --- wire the fork -----------------------------------------------------

      # Rewrite the step list past the fork: keep the choice (plus the
      # mode step for a mod), swap the tail. Re-running on every Next
      # from the choice step also re-forks when the user went back and
      # switched the radio.
      choice.on_next do |wiz|
        keep = [choice] of Egui::WizardStep
        mode.try { |m| keep << m }
        tail = w.existing? ? [existing] : [engine, source, target]
        wiz.steps.clear
        wiz.steps.concat(keep)
        wiz.steps.concat(tail)
      end

      steps = [choice] of Egui::WizardStep
      mode.try { |m| steps << m }
      steps.concat([engine, source, target])

      wizard = Egui::Wizard.new(
        L.t("home.install_button", title: wizard_title(w)).sub("…", ""), steps,
        id: "install-wizard")
      wizard.on_finish { |_wiz| register_install(w) }
      wizard.on_cancel { |_wiz| @status = L.t("status.install_cancelled") }
      wizard
    end

    # Drive the open wizard; show reports the frame the user is done
    # with the window (Install finished, Cancel, ✕/Escape).
    private def draw_install_wizard(ctx : Egui::Context) : Nil
      return unless (w = @wizard)
      @wizard = nil if w.wizard.show(ctx)
    end

    # A path input row: editable text + folder picker; re-validates every
    # frame and stores the error on the wizard state.
    private def path_field(ui : Egui::Ui, field : Symbol, w : WizardState,
                           hint : String, &validate : String -> String?) : Nil
      value = w.get(field)

      ui.horizontal do |h|
        if icon_button(h, L.t("wizard.browse"),
            Egui::Icon.from_file(:lucide, :folder_open, tint: h.style.visuals.text_color)).clicked?
          Egui::SystemPorts::PickFolderDialog.show(
            directory: value.empty? ? nil : value) do |picked|
            w.set(field, picked) if picked
          end
        end
        h.text_edit_singleline(value, hint: hint) { |text| w.set(field, text) }
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
      @status = L.t("status.installing", title: wizard_title(w))
      w.failed = false
      begin
        install = Installer.install(w.game, w.source, w.engine, w.target, @store,
          custom: w.mod?) { |line|
          @status = line
        }
        @status = L.t("status.installed", path: install.path)
        @selected = w.mod? ? MOD_ID : w.game.id
      rescue ex : InstallError | File::Error
        w.failed = true
        @status = L.t("status.install_failed", message: ex.message)
      end
    end

    # The "existing folder" branch: validate + store bookkeeping only —
    # the folder itself is left untouched and becomes playable as-is.
    # Re-validated here: the gate only proves the last frame was clean.
    private def register_install(w : WizardState) : Nil
      path = File.expand_path(w.existing_dir)
      if key = Catalog.validate_install(w.game, path)
        @status = L.t("status.register_failed", message: L.t(key))
        return
      end
      begin
        install = Store::Install.new(
          id: Store.next_id(w.game.id),
          game: w.game.id,
          path: path,
          engine: engine_hint(path),
          source: "",
          created_at: Time.local.to_rfc3339,
          custom: w.mod?)
        @store.add_install(install)
        @store.save
        @status = L.t("status.registered", path: path)
        @selected = w.mod? ? MOD_ID : w.game.id
      rescue ex : File::Error | IO::Error
        @status = L.t("status.register_failed", message: ex.message)
      end
    end

    # Where the engine of a registered install lives, when we can tell:
    # an assembled distribution links bin/xr_3da at the engine build, so
    # the symlink's target dir is the hint. Otherwise "" (informational
    # only — the row on the game page shows it).
    private def engine_hint(path : String) : String
      exe = File.join(path, "bin", Engine.executable_name)
      return File.dirname(File.readlink(exe)) if File.symlink?(exe)
      ""
    rescue ex : File::Error
      ""
    end

    # Logs page state: the install being inspected plus the last scan
    # result and its markdown rendering (nil until Analyze is pressed;
    # immediate mode rebuilds the page from this every frame).
    class LogsState
      property install : Store::Install
      property report : LogAnalyzer::Report?
      property markdown : String?
      property? confirm_clear : Bool = false

      def initialize(@install)
      end
    end

    # Wizard state: the Egui::Wizard component (step chrome and
    # navigation) plus the data the step bodies rebuild from every
    # frame: the fork choice (register an existing folder vs assemble
    # from scratch) with its path, the three scratch paths, the
    # modified-game compat mode and the current validation error.
    # `failed` flags the last Install run so the custom Install button
    # keeps the window open on failure. For a modified game `game` is
    # the picked mode's base game and gets swapped when the selectbox
    # changes.
    class WizardState
      # Late-init: the wizard is built right after the state exists
      # (step bodies and gates close over the state), by open_wizard.
      property! wizard : Egui::Wizard
      property game : Catalog::Game
      property engine : String
      property source : String
      property target : String = ""
      property existing_dir : String = ""
      property? existing : Bool = false   # the fork: register vs assemble
      property error : String?
      property? mod : Bool = false
      property? failed : Bool = false

      def initialize(@game, @engine, @source, @mod = false)
      end

      def get(field : Symbol) : String
        case field
        when :engine then engine
        when :source then source
        when :target then target
        when :existing then existing_dir
        else raise ArgumentError.new("unknown wizard field #{field}")
        end
      end

      def set(field : Symbol, value : String) : Nil
        case field
        when :engine then @engine = value
        when :source then @source = value
        when :target then @target = value
        when :existing then @existing_dir = value
        end
      end
    end
  end
end

# GUI entry: single instance only (an old window still open must not
# race the config), then decode the window icon and hand control to egui.
if ARGV.empty?
  begin
    Launcher::SingleInstance.acquire!
  rescue Launcher::SingleInstance::AlreadyRunning
    STDERR.puts "xr-launcher: already running"
    Egui::SystemPorts::MessageBox.info(
      Launcher::L.t("errors.already_running"), "OpenXRayLauncher")
    exit 1
  end

  window_icon = nil
  if (icon_path = Launcher::Assets.icon("launcher_128.png")) && File.exists?(icon_path) &&
     (frame = Egui::ImageCodec.decode(File.read(icon_path).to_slice))
    window_icon = {rgba: frame.rgba, width: frame.width, height: frame.height}
  end
  Egui.run(Launcher::App.new,
    title: "OpenXRayLauncher #{Launcher::VERSION}",
    width: 980,
    height: 640,
    icon: window_icon,
    # Custom Win11-style window frame (egui.cr chrome): no system
    # titlebar, the frame draws its own caption with min/max/close.
    decorations: false,
    chrome: true,
    chrome_style: Egui::WindowFrame::Style::Windows)
else
  exit Launcher.cli(ARGV)
end
