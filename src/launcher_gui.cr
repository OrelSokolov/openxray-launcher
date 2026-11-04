# xr-launcher GUI (egui.cr). The only file that pulls in the egui
# backend — headless builds (specs, CLI) never require it.
#
# Layout split:
#   * exml (assets/launcher.exml) owns the chrome — menu bar, settings
#     page, status bar, About modal — through the exml Runtime (store
#     slots + named actions), routed pages via ctx.router;
#   * native code owns the home: a ctx.side_panel game list (one
#     full-width game card: icon + title + install info on one
#     clickable surface) and the central game page (gradient header
#     card, install cards, the install wizard as an Egui::Wizard
#     embedded window shown over it).
#
# The look — the "Zone" theme (App.xr_theme): dark browser-style
# surfaces, one amber accent, rounded buttons with drop shadows
# (`button` class rules), full-width gradient CTA buttons (`hero.*`
# rules + #hero_button) and shadowed cards (#card).
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

  # One sidebar row as a real Widget (was paint-in-place: raw
  # allocate/interact/painter calls the widget inspector could not
  # see). Living through `Ui#add` gives it an inspector pick, a stable
  # explicit id ("game-<key>") and the style cascade — the whole look
  # lives in the "sidebar.entry" class rules of xr_theme (base shape,
  # a `:hover` translucent surface, the `:selected` amber gradient
  # card with a drop shadow). Here only the state string changes —
  # CSS pseudo-class style, same pattern as egui.cr's own Sidebar.
  class SidebarEntry
    include Egui::Widget

    def initialize(key : String, @title : String, @info : String,
                   @selected : Bool, @icon_path : String?)
      @id_name = "game-#{key}"
    end

    def style_class : String?
      "sidebar.entry"
    end

    def inspector_label : String?
      @title
    end

    def style_properties : Array(Egui::StyleProp)
      Egui::StyleProps.sizable + [
        Egui::StyleProp.new("background", :color, states: true),
        Egui::StyleProp.new("background2", :color, states: true,
          label: "background 2 (gradient)"),
        Egui::StyleProp.new("stroke", :color, states: true),
        Egui::StyleProp.new("rounding", :number, fallback: 10.0, min: 0.0),
        Egui::StyleProp.new("text_color", :color),
        Egui::StyleProp.new("info_color", :color),
        Egui::StyleProp.new("icon_size", :number, fallback: 24.0, min: 0.0),
        Egui::StyleProp.new("shadow.color", :color, states: true),
        Egui::StyleProp.new("shadow.blur", :number, min: 0.0),
        Egui::StyleProp.new("shadow.x", :number),
        Egui::StyleProp.new("shadow.y", :number),
      ]
    end

    def ui(ui : Egui::Ui) : Egui::Response
      id = resolve_id(ui)
      vars = style_vars(ui, id)

      size = ui.style.font_size
      title_h = size * 1.15
      info_h = size * 0.8
      height = {title_h + info_h + 16.0, 48.0}.max
      sz = styled_size(Egui::Vec2.new(ui.available_width, height), vars, ui, id)

      rect = ui.allocate_at_least(sz)
      response = ui.interact(rect, id, Egui::Sense.click)

      # The state bag: base rule + the overlay of the live state. The
      # selected card keeps its :selected look while hovered (the
      # gradient does not give way to the hover surface) — same
      # precedence as egui.cr's own Sidebar tabs.
      state = @selected ? "selected" : (response.hovered? ? "hover" : nil)
      sv = style_vars(ui, id, state)
      painter = ui.painter
      rounding = sv.f64("rounding", 10.0)

      # The card's drop shadow (the :selected rule's shadow.*) — under
      # the fill like before.
      if (shadow = sv.shadow?) && !shadow.inset?
        painter.box_shadow(rect, shadow.color, blur: shadow.blur,
          rounding: rounding, spread: shadow.spread, offset: shadow.offset)
      end

      # Fill: whatever the cascade gives — the :hover translucent
      # surface or the :selected amber gradient; nothing at rest.
      if (fill = sv.color?("background"))
        painter.rect(rect, rounding, fill: fill,
          fill2: sv.color?("background2"), stroke_color: sv.color?("stroke"))
      end

      title_color = sv.color("text_color", ui.style.visuals.text_color)
      info_color = sv.color("info_color", App::COLOR_MUTED)

      tx = rect.left + 12.0
      if (path = @icon_path) && File.exists?(path) &&
         (tex = ui.ctx.load_image(path)) > 0
        icon_side = sv.f64("icon_size", 24.0)
        icon_box = Egui::Rect.from_min_size(
          Egui::Pos2.new(tx, rect.center.y - icon_side / 2.0),
          Egui::Vec2.new(icon_side, icon_side))
        painter.image(icon_box, tex)
        tx += icon_side + 10.0
      end

      block_h = title_h + info_h + 4.0
      block_top = rect.top + (rect.height - block_h) / 2.0
      painter.text(Egui::Pos2.new(tx, block_top + title_h / 2.0),
        @title, title_h, title_color, bold: true)
      painter.text(Egui::Pos2.new(tx, block_top + title_h + 4.0 + info_h / 2.0),
        @info, info_h, info_color)

      response
    end
  end

  class App < Egui::App
    COLOR_MUTED = Egui::Color32.rgb(154, 161, 176)
    COLOR_OK    = Egui::Color32.rgb(120, 220, 120)
    COLOR_WARN  = Egui::Color32.rgb(240, 200, 80)
    COLOR_ERROR = Egui::Color32.rgb(240, 100, 100)

    # --- the "Zone" palette: dark browser-style surfaces + amber accent ---

    ACCENT   = Egui::Color32.rgb(206, 122, 30)  # selection / CTA accent
    ACCENT_LIGHT = Egui::Color32.rgb(222, 146, 62) # gradient top
    ACCENT_DARK  = Egui::Color32.rgb(170, 95, 20)  # gradient bottom
    ON_ACCENT    = Egui::Color32.rgb(40, 27, 6)    # near-black text on amber
    COLOR_DANGER = Egui::Color32.rgb(235, 90, 90)

    # Elevated surfaces (cards): fill, header gradient ends, hairline
    # stroke, drop shadow.
    CARD_FILL     = Egui::Color32.rgb(26, 29, 37)
    CARD_TOP      = Egui::Color32.rgb(33, 37, 48)
    CARD_BOTTOM   = Egui::Color32.rgb(23, 26, 33)
    CARD_STROKE   = Egui::Color32.rgba(255, 255, 255, 20)
    CARD_SHADOW   = Egui::Color32.rgba(0, 0, 0, 110)
    CARD_ROUNDING = 12.0

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

    # Live launches of THIS launcher session: install path → Process.
    # Complements the pid file (which survives restarts but says
    # nothing about processes we can wait on directly).
    @running = {} of String => Process
    @run_watcher_active = false

    # exml side: parsed markup, one renderer, the store + actions.
    @exml : Egui::Exml::Document
    @renderer = Egui::Exml::Renderer.new
    @rt = Egui::Exml::Runtime.new

    # The "Zone" theme: dark browser-style palette plus class rules so
    # every button in the app (wizard footer, exml chrome, dialogs)
    # picks up the rounded/shadowed look. Derived from the egui.cr
    # defaults — a palette swap via `DefaultTheme.build`, then a few
    # sheet rules on top.
    def self.xr_theme : Egui::Theme
      theme = Egui::DefaultTheme.build("xr-zone", dark: true) do |v|
        v.window_fill = Egui::Color32.rgb(19, 21, 27)
        v.window_stroke = Egui::Color32.rgb(45, 49, 60)
        v.title_bar_fill = v.window_fill
        v.panel_fill = Egui::Color32.rgb(12, 13, 17)
        v.text_color = Egui::Color32.rgb(228, 231, 238)
        v.title_color = Egui::Color32.rgb(246, 247, 250)
        v.button_weak = Egui::Color32.rgba(255, 255, 255, 10)
        v.button_hovered = Egui::Color32.rgba(255, 255, 255, 16)
        v.button_active = Egui::Color32.rgba(255, 255, 255, 24)
        v.button_stroke = Egui::Color32.rgba(255, 255, 255, 20)
        v.selection_fill = ACCENT
        v.hyperlink_color = Egui::Color32.rgb(110, 168, 254)
        v.separator_color = Egui::Color32.rgba(255, 255, 255, 22)
        v.modal_dim = Egui::Color32.rgba(0, 0, 0, 120)
      end

      sheet = theme.sheet
      # Buttons: dark surface with a subtle drop shadow that lifts a
      # little on hover and sinks (inset) on press; `transition`
      # animates between states. NOTE: every state rule must carry
      # `background` — the user-agent theme ships a `button:hover`
      # overlay of its own (v.button_hovered, a translucent white),
      # and the state layer ALWAYS beats class rules: without an
      # explicit hover fill here, the fill transitions towards that
      # white through bright semi-opaque grays — a flash on hover.
      sheet.rule("button", Egui::StyleVars{
        "background"     => Egui::Color32.rgb(24, 24, 27),
        "padding.bottom" => 6.0,
        "padding.left"   => 14.0,
        "padding.right"  => 14.0,
        "padding.top"    => 6.0,
        "rounding"       => 8.0,
        "shadow.blur"    => 2.0,
        "shadow.color"   => Egui::Color32.rgb(0, 0, 0),
        "shadow.y"       => 1.0,
        "stroke"         => Egui::Color32.rgb(60, 60, 60),
        "text_color"     => Egui::Color32.rgb(190, 190, 190),
        "transition"     => 120.0,
      })
      sheet.rule("button:hover", Egui::StyleVars{
        "background"  => Egui::Color32.rgb(32, 32, 36),
        "shadow.blur" => 4.0,
        "shadow.y"    => 1.0,
        "stroke"      => Egui::Color32.rgb(98, 98, 98),
      })
      sheet.rule("button:active", Egui::StyleVars{
        "background"   => Egui::Color32.rgb(12, 12, 13),
        "shadow.inset" => true,
      })
      # Hero (primary CTA) buttons — drawn inside `with_style_scope
      # ("hero")` (see #hero_button): same shape, bigger, slate
      # vertical-gradient surface.
      sheet.rule("hero.button", Egui::StyleVars{
        "background"     => Egui::Color32.rgb(90, 99, 112),
        "background2"    => Egui::Color32.rgb(32, 31, 41),
        "font_size"      => 15.0,
        "font_weight"    => 400.0,
        "padding.top"    => 10.0,
        "padding.right"  => 18.0,
        "padding.bottom" => 10.0,
        "padding.left"   => 18.0,
        "rounding"       => 12.0,
        "text_color"     => Egui::Color32.rgb(255, 255, 255),
      })
      sheet.rule("hero.button:hover", Egui::StyleVars{
        "background"     => Egui::Color32.rgb(134, 146, 164),
        "background2"    => Egui::Color32.rgb(37, 35, 49),
        "shadow.blur"    => 9.0,
        "shadow.y"       => 3.0,
      })
      sheet.rule("hero.button:active", Egui::StyleVars{"shadow.inset" => true})
      # The Play button (#draw_install_row) — the same hero shape in a
      # brighter slate-blue gradient; it runs inside a nested
      # `with_style_scope("hero") { with_style_scope("play") }`, so its
      # class path is "hero.play.button" (which does NOT inherit from
      # "hero.button" — the rule below carries the full shape).
      sheet.rule("hero.play.button", Egui::StyleVars{
        "background"     => Egui::Color32.rgb(143, 157, 179),
        "background2"    => Egui::Color32.rgb(65, 73, 95),
        "font_size"      => 18.5,
        "padding.top"    => 10.0,
        "padding.right"  => 18.0,
        "padding.bottom" => 10.0,
        "padding.left"   => 18.0,
        "rounding"       => 12.0,
        "text_color"     => Egui::Color32.rgb(255, 255, 255),
      })
      sheet.rule("hero.play.button:hover", Egui::StyleVars{
        "background"  => Egui::Color32.rgb(171, 185, 206),
        "background2" => Egui::Color32.rgb(76, 84, 104),
        "shadow.blur" => 9.0,
        "shadow.y"    => 3.0,
      })
      sheet.rule("hero.play.button:active",
        Egui::StyleVars{"shadow.inset" => true})
      # Wizard chrome follows the card surfaces.
      sheet.rule("wizard.header", Egui::StyleVars{"background" => CARD_TOP})
      sheet.rule("side_image", Egui::StyleVars{"background" => CARD_BOTTOM})
      # The home sidebar's game cards (SidebarEntry): rounded web-nav
      # rows; hover a white surface, selected the grey card with a drop
      # shadow and a near-black label. Everything is the cascade —
      # editable per state in the widget inspector.
      sheet.rule("sidebar.entry", Egui::StyleVars{
        "icon_size" => 24.0,
        "rounding"  => 10.0,
      })
      sheet.rule("sidebar.entry:hover", Egui::StyleVars{
        "background" => Egui::Color32.rgb(32, 37, 45),
      })
      sheet.rule("sidebar.entry:selected", Egui::StyleVars{
        "background"    => Egui::Color32.rgb(147, 156, 176),
        "info_color"    => Egui::Color32.rgb(70, 46, 8),
        "shadow.blur"   => 10.0,
        "shadow.color"  => Egui::Color32.rgb(0, 0, 0),
        "shadow.y"      => 3.0,
        "text_color"    => Egui::Color32.rgb(40, 27, 6),
      })
      theme
    end

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
      # The theme swap must land before the first frame; it goes last —
      # an instance call before every ivar is assigned trips Crystal's
      # "possibly uninitialized ivar" check.
      self.theme = self.class.xr_theme
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
      start_run_watcher(ctx)
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
      ui.horizontal(wrap: false) do |h|
        if (logo = Assets.icon("launcher_64.png")) && File.exists?(logo) &&
           (tex = ctx.load_image(logo)) > 0
          h.image(tex, Egui::Vec2.new(32.0, 32.0))
        end
        h.heading("OpenXRay")
      end
      ui.rich(muted(L.t("app.subtitle")))
      ui.allocate_space(Egui::Vec2.new(0.0, 10.0))

      Catalog.all.each do |game|
        draw_game_button(ui, game)
        ui.allocate_space(Egui::Vec2.new(0.0, 4.0))
      end

      ui.allocate_space(Egui::Vec2.new(0.0, 6.0))
      mods = @store.custom_installs.size
      info = mods.zero? ? L.t("home.not_installed") : \
        L.t(mods == 1 ? "home.installs_count_one" : "home.installs_count", n: mods)
      draw_sidebar_entry(ui, id: MOD_ID, title: L.t("games.mod.title"),
        info: info, icon_path: Assets.icon("launcher_64.png"))
    end

    # One game = one full-width clickable surface: the whole row (icon +
    # title + install info) selects the game. The card itself is the
    # SidebarEntry widget (pickable/editable in the F12 widget
    # inspector); this wrapper only routes the click.
    private def draw_game_button(ui : Egui::Ui, game : Catalog::Game) : Nil
      # NOTE: the param must NOT be named `count` — crystal-i18n treats
      # that as pluralization and looks up `key.one/.other` sub-keys.
      installs = @store.for_game(game.id).count { |i| !i.custom? }
      info = installs.zero? ? L.t("home.not_installed") : \
        L.t(installs == 1 ? "home.installs_count_one" : "home.installs_count", n: installs)
      draw_sidebar_entry(ui, id: game.id, title: sidebar_title(game),
        info: info, icon_path: Assets.icon("openxray_#{game.id}.png"))
    end

    # The clickable row itself: optional icon + title + muted info line.
    # Selected paints an amber gradient card with a drop shadow and a
    # near-black label; hover a translucent surface; both rounded like a
    # web nav item. All of it is the SidebarEntry's cascade, editable in
    # the widget inspector — here only the selection state changes.
    private def draw_sidebar_entry(ui : Egui::Ui, id : String, title : String,
                                   info : String, icon_path : String?) : Nil
      response = ui.add(SidebarEntry.new(id, title, info, @selected == id,
        icon_path))
      return unless response.clicked?
      response.mark_changed
      @selected = id
      @wizard = nil
      @logs = nil
      @confirm_delete = nil
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

    # A web-style card: rounded elevated surface (drop shadow + hairline
    # stroke, optional vertical gradient fill) around a block of
    # content. Mirrors `Ui#frame`'s back-paint trick — paint slots are
    # reserved BEFORE the content lays out, then filled with the final
    # outer rect, so the shadow lands under the fill under the content.
    private def card(ui : Egui::Ui, fill : Egui::Color32? = CARD_FILL,
                     fill2 : Egui::Color32? = nil, &block : Egui::Ui ->) : Nil
      shadow_idx = ui.painter.add_noop
      fill_idx = ui.painter.add_noop
      outer = ui.frame(rounding: CARD_ROUNDING,
        margin: Egui::Vec2.new(18.0, 14.0), &block)
      clip = ui.painter.clip
      ui.painter.set(shadow_idx, Egui::ShadowCmd.new(clip, outer,
        CARD_ROUNDING, 16.0, 0.0, Egui::Vec2.new(0.0, 5.0), CARD_SHADOW, false))
      if fill || fill2
        ui.painter.set(fill_idx, Egui::RectCmd.new(clip, outer, CARD_ROUNDING,
          fill, CARD_STROKE, 1.0, fill2))
      end
    end

    # The primary CTA: full-width slate gradient button — the
    # "hero.button" scope class (see .xr_theme) supplies the gradient
    # fill, size and shadow; call it inside `with_style_scope("hero")`.
    private def hero_button(ui : Egui::Ui, text : String, icon : Egui::Svg) : Egui::Response
      btn = Egui::Button.new(text)
        .min_size(Egui::Vec2.new(ui.available_width, 46.0))
        .rounding(12.0)
        .icon(icon)
      ui.add(btn)
    end

    private def draw_game_page(ctx : Egui::Context, ui : Egui::Ui) : Nil
      return draw_mod_page(ctx, ui) if @selected == MOD_ID
      game = Catalog[@selected]

      # The game header: a gradient hero card (icon + title + notes).
      card(ui, fill: CARD_TOP, fill2: CARD_BOTTOM) do |c|
        c.horizontal(wrap: false) do |h|
          icon_path = Assets.icon("openxray_#{game.id}.png")
          if icon_path && File.exists?(icon_path) && (tex = ctx.load_image(icon_path)) > 0
            h.image(tex, Egui::Vec2.new(44.0, 44.0))
          end
          h.heading(game_title(game))
        end
        if game.experimental?
          c.rich(Egui::RichText.new(L.t("home.experimental")).color(COLOR_WARN))
        end
        c.rich(muted(L.t("games.#{game.id}.notes")), wrap: true)
      end
      ui.allocate_space(Egui::Vec2.new(0.0, 8.0))

      installs = @store.for_game(game.id).reject(&.custom?)
      if installs.empty?
        card(ui) do |c|
          c.allocate_space(Egui::Vec2.new(0.0, 14.0))
          c.label(L.t("home.no_installs"), align: :center)
          c.allocate_space(Egui::Vec2.new(0.0, 12.0))
        end
      else
        installs.each do |install|
          card(ui) { |c| draw_install_row(ctx, c, install) }
          ui.allocate_space(Egui::Vec2.new(0.0, 8.0))
        end
      end

      # First install: the big Install button; anything already
      # installed: the same wizard entry, renamed and re-iconed.
      first = installs.empty?
      label = first ? L.t("home.install_button", title: game_title(game)) : L.t("home.add_more")
      ui.with_style_scope("hero") do |h|
        icon = first ? Egui::Icon.from_file(:lucide, :download, tint: Egui::Color32.rgb(255, 255, 255)) \
                     : Egui::Icon.from_file(:lucide, :plus, tint: Egui::Color32.rgb(255, 255, 255))
        if hero_button(h, label, icon).clicked?
          open_wizard
        end
      end
    end

    # The "Modified game" page: same shape as a game page, but each
    # install carries its own compatibility mode (shown per row) and
    # the wizard gains the mode-select step.
    private def draw_mod_page(ctx : Egui::Context, ui : Egui::Ui) : Nil
      # The game header: a gradient hero card, same shape as a game page.
      card(ui, fill: CARD_TOP, fill2: CARD_BOTTOM) do |c|
        c.heading(L.t("games.mod.title"))
        c.rich(muted(L.t("games.mod.notes")), wrap: true)
      end
      ui.allocate_space(Egui::Vec2.new(0.0, 8.0))

      installs = @store.custom_installs
      if installs.empty?
        card(ui) do |c|
          c.allocate_space(Egui::Vec2.new(0.0, 14.0))
          c.label(L.t("home.no_installs"), align: :center)
          c.allocate_space(Egui::Vec2.new(0.0, 12.0))
        end
      else
        installs.each do |install|
          mode_game = Catalog[install.game]? # install.game = the chosen compat mode
          card(ui) do |c|
            draw_install_row(ctx, c, install,
              subtitle: mode_game ? game_title(mode_game) : nil)
          end
          ui.allocate_space(Egui::Vec2.new(0.0, 8.0))
        end
      end

      first = installs.empty?
      label = first ? L.t("home.install_button", title: L.t("games.mod.title")) : L.t("home.add_more")
      ui.with_style_scope("hero") do |h|
        icon = first ? Egui::Icon.from_file(:lucide, :download, tint: Egui::Color32.rgb(255, 255, 255)) \
                     : Egui::Icon.from_file(:lucide, :plus, tint: Egui::Color32.rgb(255, 255, 255))
        if hero_button(h, label, icon).clicked?
          open_wizard(mod: true)
        end
      end
    end

    # One install inside a card: path + creation info, the big gradient
    # Play button, then a row of quiet secondary actions.
    private def draw_install_row(ctx : Egui::Context, ui : Egui::Ui,
                                 install : Store::Install, subtitle : String? = nil) : Nil
      ui.label(File.expand_path(install.path))
      ui.rich(muted(subtitle), wrap: true) if subtitle
      ui.rich(muted(L.t("home.created_line",
        created: install.created_at, engine: install.engine, source: install.source)), wrap: true)
      ui.allocate_space(Egui::Vec2.new(0.0, 4.0))

      # Play: the big full-width gradient button, like Install on the
      # game page, but in the brighter "hero.play" variant. While the
      # game runs (this session or a pid parked by an earlier launch)
      # it shows the running state and does not relaunch.
      running = install_running?(install)
      ui.with_style_scope("hero") do |h|
        h.with_style_scope("play") do |p|
          icon = running ? Egui::Icon.from_file(:lucide, :iteration_ccw, tint: Egui::Color32.rgb(255, 255, 255)) \
                         : Egui::Icon.from_file(:lucide, :play, tint: Egui::Color32.rgb(255, 255, 255))
          if !running && hero_button(p, L.t("home.run"), icon).clicked?
            begin
              @running[install.path] = Runner.run(install)
              @status = L.t("status.launched", path: install.path)
            rescue ex : InstallError | File::Error
              @status = L.t("status.launch_failed", message: ex.message)
            end
          elsif running && hero_button(p, L.t("home.running"), icon).clicked?
            @status = L.t("status.already_running", path: install.path)
          end
        end
      end
      ui.allocate_space(Egui::Vec2.new(0.0, 4.0))

      ui.horizontal(wrap: false) do |h|
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
          # Confirm: a red-tinted danger button for the destructive step.
          confirm = Egui::Button.new(L.t("home.confirm_delete"))
            .icon(Egui::Icon.from_file(:lucide, :trash, tint: Egui::Color32.rgb(255, 170, 170)))
          confirm.style do |s|
            s.background = Egui::Color32.rgba(235, 90, 90, 60)
            s.stroke = Egui::Color32.rgba(235, 90, 90, 170)
            s.text_color = Egui::Color32.rgb(255, 180, 180)
          end
          if h.add(confirm).clicked?
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

    # Is this install's game running? Processes launched by THIS
    # session are asked directly (and reaped via terminated?); anything
    # else falls back to the parked pid file — so a game started by the
    # CLI or by a previous launcher session counts too.
    private def install_running?(install : Store::Install) : Bool
      if process = @running[install.path]?
        unless process.terminated?
          return true
        end
        # Just noticed the exit: forget the process and — only if no
        # newer launch overwrote it — the pid file; report the end of
        # the run in the status bar.
        @running.delete(install.path)
        Runner.clear_pid(install) if Runner.running_pid(install) == process.pid
        @status = L.t("status.exited", path: install.path)
      end
      Runner.running?(install)
    end

    # Repaints run on demand, so an exit that happens while the user
    # idles would go unnoticed. This fiber polls the tracked processes
    # (plus the parked pids — a CLI launch never lands in @running):
    # once a second while anything runs, otherwise a slow 5 s sweep
    # that also catches a game started from the CLI meanwhile.
    private def start_run_watcher(ctx : Egui::Context) : Nil
      return if @run_watcher_active
      @run_watcher_active = true
      spawn do
        while true
          live = @running.any? { |_, process| !process.terminated? } ||
                 @store.installs.any? { |install| Runner.running?(install) }
          if live
            ctx.request_repaint
            sleep(Time::Span.new(seconds: 1))
          else
            sleep(Time::Span.new(seconds: 5))
          end
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
      # The standard footer falls back to the component's English
      # defaults; the target step's custom buttons carry their own
      # L.t labels.
      wizard.back_label = L.t("wizard.back")
      wizard.next_label = L.t("wizard.next")
      wizard.cancel_label = L.t("wizard.cancel")
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
# XR_LAUNCHER_HEADLESS: require-for-the-class only — the headless
# screenshot driver (spec/sidebar_shots.cr) builds Launcher::App itself.
if ENV["XR_LAUNCHER_HEADLESS"]?
  # no entry — the requiring script drives the frames
elsif ARGV.empty?
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
    chrome_style: Egui::WindowFrame::Style::Windows,
    # Widget inspector panel (F12 toggles it): compiled in only by
    # `rake build:dev` (-Dwidget_inspector); other builds stay :off.
    inspector: {% if flag?(:widget_inspector) %} :on {% else %} :off {% end %})
else
  exit Launcher.cli(ARGV)
end
