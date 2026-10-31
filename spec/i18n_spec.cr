require "./spec_helper"
require "yaml"

# Keys the launcher code actually looks up (GUI + core). A new call
# site without a YAML entry fails here first, not as "translation
# missing" in the user's face.
REQUIRED_KEYS = [
  # chrome / menus / settings
  "app.subtitle", "menu.file", "menu.settings", "menu.help",
  "menu.install", "menu.refresh", "menu.quit", "menu.settings_page",
  "menu.about",
  # home
  "home.experimental", "home.not_installed", "home.installs_count",
  "home.installs_count_one", "home.no_installs", "home.install_button",
  "home.add_more", "home.created_line", "home.run", "home.open_folder",
  "home.delete",
  "home.confirm_delete", "home.cancel",
  # wizard
  "wizard.step_of", "wizard.steps.engine", "wizard.steps.source",
  "wizard.steps.target", "wizard.engine_intro", "wizard.engine_layouts",
  "wizard.source_intro", "wizard.source_note", "wizard.target_intro",
  "wizard.will_create", "wizard.will_create_body", "wizard.browse",
  "wizard.ok", "wizard.back", "wizard.next", "wizard.install",
  "wizard.cancel",
  # settings
  "settings.title", "settings.language", "settings.language_note",
  "settings.store_line",
  # status
  "status.ready", "status.installing", "status.installed",
  "status.install_failed", "status.install_cancelled", "status.launched",
  "status.launch_failed", "status.opened_folder", "status.no_file_manager",
  "status.confirm_delete_status", "status.removed", "status.delete_failed",
  "status.refreshed", "status.locale_saved",
  # games
  "games.soc.title", "games.soc.notes", "games.cs.title", "games.cs.notes",
  "games.cop.title", "games.cop.notes",
  "about.text",
] of String

def flatten(node : YAML::Any, prefix : String = "") : Array(String)
  case node.raw
  when Hash
    node.as_h.flat_map { |k, v| flatten(v, prefix.empty? ? k.as_s : "#{prefix}.#{k.as_s}") }
  else
    [prefix]
  end
end

def locale_keys(path : String) : Array(String)
  flatten(YAML.parse(File.read(path)).as_h.first_value)
end

describe "launcher locales" do
  Dir["config/locales/*.yml"].each do |path|
    locale = File.basename(path, ".yml")
    it "has every required key in #{locale}" do
      keys = locale_keys(path)
      missing = REQUIRED_KEYS - keys
      missing.should be_empty
    end
  end

  it "keeps en and ru key sets identical" do
    en = locale_keys("config/locales/en.yml")
    ru = locale_keys("config/locales/ru.yml")
    (en - ru).should be_empty
    (ru - en).should be_empty
  end
end

describe Launcher::Locale do
  it "falls back to English builtins before init" do
    Launcher::Locale.initialized?.should be_false
    Launcher::L.t("errors.source_not_found").should eq("directory does not exist")
    Launcher::L.t("errors.target_not_empty", path: "/x")
      .should eq("target /x is not empty")
  end

  it "interpolates %{params} in the pre-init fallback" do
    Launcher::L.t("install.bin_linked", n: 7).should contain("7")
  end

  it "translates through i18n after init and switches locales" do
    Launcher::Locale.init("ru")
    Launcher::Locale.initialized?.should be_true
    Launcher::L.t("home.run").should eq("Играть")
    Launcher::Locale.init("en")
    Launcher::L.t("home.run").should eq("Play")
    Launcher::Locale.set("ru")
    Launcher::L.t("status.ready").should eq("Готово.")
    Launcher::Locale.set("en")
  end

  it "keeps unknown keys readable" do
    Launcher::Locale.init("en")
    Launcher::L.t("no.such.key").should eq("no.such.key")
  end

  it "does not trigger pluralization for numeric params (count: would)" do
    # Regression: a param literally named `count` makes crystal-i18n
    # look up `key.one`/`key.other` plural sub-keys — the flat keys
    # then render as "translation missing". Numeric params are `n:`.
    Launcher::Locale.init("en")
    Launcher::L.t("home.installs_count", n: 3).should eq("3 installs")
    Launcher::L.t("home.installs_count_one", n: 1).should eq("1 install")
    Launcher::Locale.set("ru")
    Launcher::L.t("home.installs_count", n: 2).should eq("установок: 2")
    Launcher::Locale.set("en")
  end

  it "detects the locale from the environment" do
    orig = ENV["LANG"]?
    ENV["LANG"] = "ru_RU.UTF-8"
    Launcher::Locale.detect.should eq("ru")
    ENV["LANG"] = "en_US.UTF-8"
    Launcher::Locale.detect.should eq("en")
    ENV["LANG"] = orig.to_s
  end
end
