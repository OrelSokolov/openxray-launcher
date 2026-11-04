# Headless screenshot run of the sidebar — reproduces the widget
# inspector's gradient edits as PNGs under tmp/shots/, no window, no GL
# (Egui::Capybara drives the real Launcher::App).
#
#   crystal run spec/sidebar_shots.cr --link-flags "-Llib/egui-cr/lib"
#
# ENV["XR_LAUNCHER_HEADLESS"] must be set before src/launcher_gui.cr is
# required so its GUI entry block stays inert (see launcher_gui.cr).

ENV["XR_LAUNCHER_HEADLESS"] = "1"

require "file_utils"
require "../src/launcher"

# Isolated config dir (like spec_helper): never touch the real
# launcher.json the GUI App might save into.
cfg = File.join(Dir.tempdir, "xr-launcher-shots-#{Random.new.hex(8)}")
Dir.mkdir(cfg)
Launcher::Paths.config_dir = cfg

require "egui-cr/src/egui/backend_selector"
require "egui-cr/src/egui/capybara"
require "egui-cr/src/egui/capybara/fonts"
require "egui-cr/src/egui/capybara/images"
require "../src/launcher_gui"

OUT = "tmp/shots"

# Real icons in the shots: decode PNGs (the sokol shim's stb provider —
# headless installs none by default) and composite ImageCmds through the
# registry's pixel backup.
Egui::ImageCodec.use(Egui::Backend::Sokol::StbImageCodec.new)

app = Launcher::App.new
Egui::Capybara::Fonts.install_for!(app)
Egui::Capybara::Images.install_for!(app)

Egui::Capybara.drive(app, width: 980, height: 640) do |t|
  # The selected game card (default "cop") and one unselected neighbour.
  sel = t.find("#game-cop")
  other = t.find("#game-soc")

  shot = ->(name : String) do
    path = t.screenshot("#{OUT}/#{name}.png")
    puts path
  end

  # 0. Baseline: the selected card's amber gradient.
  shot.call("01_default")

  # 1. Inspector edit of background (gradient TOP) only — the bottom
  #    stays amber (the hardcoded ACCENT_DARK fallback).
  t.ctx.set_id_style(sel.id, "background", Egui::Color32.rgb(64, 120, 220))
  t.idle(2)
  shot.call("02_top_only")

  # 2. background2 (gradient BOTTOM) only — the top stays amber
  #    (ACCENT_LIGHT fallback).
  t.ctx.clear_id_style(sel.id, "background")
  t.ctx.set_id_style(sel.id, "background2", Egui::Color32.rgb(64, 120, 220))
  t.idle(2)
  shot.call("03_bottom_only")

  # 3. Both ends overridden — a clean custom gradient.
  t.ctx.set_id_style(sel.id, "background", Egui::Color32.rgb(96, 160, 240))
  t.idle(2)
  shot.call("04_both")

  # 4. A color picked with transparency: over the dark panel it reads
  #    as an unexplained near-black top.
  t.ctx.set_id_style(sel.id, "background", Egui::Color32.rgba(70, 130, 210, 80))
  t.idle(2)
  shot.call("05_transparent_top")

  # 5. An edit made in the inspector's Hover STATE tab: exists only in
  #    the per-state bag — invisible until the pointer is over the row.
  t.ctx.clear_id_style(sel.id)
  t.ctx.set_id_style(other.id, "background",
    Egui::Color32.rgb(120, 80, 200), "hover")
  t.idle(2)
  shot.call("06_hover_state_idle")   # no pointer over it: nothing painted
  t.hover(other)
  shot.call("07_hover_state_hover")  # pointer over it: the override shows

  # 6. Class-tab edit (sidebar.entry) vs selection: the amber card is
  #    the widget's hardcoded fallback, not a class rule — editing the
  #    class recolors the plain rows but the selected card stays amber
  #    (per-element overrides from step 3-4 were cleared).
  t.move_to(Egui::Pos2.new(600.0, 20.0)) # pointer off the sidebar
  t.ctx.stylesheet.rule("sidebar.entry",
    Egui::StyleVars{"background" => Egui::Color32.rgb(40, 60, 90)})
  t.idle(2)
  shot.call("08_class_rule")
end

FileUtils.rm_rf(cfg)
puts "done: #{OUT}/*.png"
