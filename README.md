# xr-launcher — universal OpenXRay game installer/launcher

This repository contains **xr-launcher** — a cross-platform GUI app (Crystal +
[egui-cr](https://github.com/OrelSokolov/egui.cr)) that assembles playable
S.T.A.L.K.E.R. distributions on OpenXRay **from copies the user already
owns**. It does not build the engine and it does not ship game assets: an
"install" is a small folder of symlinks + config files pointing at an
existing OpenXRay build and an existing GOG/Steam game install.

Supported games:

| id  | game                              | status                                      |
|-----|-----------------------------------|---------------------------------------------|
| soc | S.T.A.L.K.E.R.: Shadow of Chernobyl | works, experimental engine platform (#392) |
| cs  | S.T.A.L.K.E.R.: Clear Sky         | engine has `-cs` mode, untested             |
| cop | S.T.A.L.K.E.R.: Call of Pripyat   | engine's native platform                    |

## Build

Requires the [Crystal](https://crystal-lang.org) toolchain and `ruby`/`rake`
(for egui-cr's vendored C shims). Then, from the checkout root:

```bash
rake all        # deps + native shims + release build -> bin/xr-launcher
rake spec       # headless specs (no egui backend required)
```

or via crosspack from this folder (`crosspack.yml`; every entry runs
`rake deps` → `crystal spec` → `rake release`, so a build never ships
with red specs):

```bash
crosspack deps                    # verify/install this host's build deps
crosspack build launcher          # linux/amd64
crosspack build launcher-macos    # darwin/arm64
crosspack build launcher-windows  # from an x64 Native Tools prompt
crosspack pack ubuntu-25.10       # deb (also: debian-12, fedora-41 rpm,
                                  # arch PKGBUILD, windows-11.0 MSI via WiX,
                                  # macos .app) — output in crosspacks/
```

Runtime library deps (GL/X11/libyaml/openssl, verified with `ldd`) are
declared in the `deps:` section and land in the package metadata
(`crosspack resolve <target>` prints the resolved Depends line).

egui-cr's `shard.yml` pins one dependency to an SSH git URL;
`shards.override.yml` in this folder reroutes it over https so plain
checkouts work without an SSH key.

## What an "install" is

The install wizard asks for three folders — engine, original game, target —
and creates:

```
<target>/
  bin/                 per-file symlinks to the engine build (xr_3da, *.so)
  fsgame.ltx           per-game FS layout; the engine finds it in the cwd
                       (portable mode, see CLocatorAPI::setup_fs_path)
  gamedata/
    shaders/gl         symlink to the engine's res/gamedata/shaders/gl
    config[s]/openxray.ltx   [compatibility] game_mode = <soc|cs|cop>
    configs/           (CoP/CS) unpacked configs symlinked from the original
    scripts/           (CoP/CS) shipped scripts copied, engine's updated
                       res/gamedata/scripts overlaid on top
  _appdata_/           savedgames/, logs/, screenshots/ — everything the
                       game writes stays inside the install
  <game data>          SoC: gamedata.db0..dbd symlinks; CoP/CS: levels/,
                       resources/, localization/, mp/, patches/ symlinks
```

Launch runs `bin/xr_3da <mode-flag>` with `<target>` as the working
directory (plus the matching `-shoc`/`-cs`/`-cop` flag, so the mode is set
by both the config file and the command line). The engine process is
detached: closing the launcher does not close the game.

Delete removes **only this folder**. It refuses to delete folders not
registered in the launcher config, never follows symlinks while deleting, and the original
game copy is never touched. Saves live in `_appdata_/` and are deleted with
the install — the confirmation says so.

### Modified game (Mods)

Below the game list the sidebar has a **Mods** («Моды») entry — the same
wizard with one extra step (engine → compatibility mode → source → target)
where a selectbox picks the mode (`soc` / `cs` / `cop`) the engine runs the
distribution in. The mode sets the launch flag (`-shoc` / `-cs` / `-cop`),
`game_mode` in `openxray.ltx` and the `fsgame.ltx` layout; the source folder
is validated against the picked mode. Point it at a full modified copy of
the game (a mod applied on top of a GOG/Steam install). Such installs are
marked `custom` in `launcher.json`, listed on the Modified game page (with
their mode) and excluded from the per-game counts.

### Per-game quirks baked into the templates

- SoC `fsgame.ltx` uses `config\` (not `configs\`), needs the
  root-scanning `$arch_dir$` line for its `.db` archives, and its
  configs/scripts stay inside the archives — only `openxray.ltx` is
  overlaid (SoC needs `-shoc` or the CoP factory breaks spawns in confusing
  ways).
- CoP/CS point `$arch_dir_levels$`/`$arch_dir_resources$`/… at the
  symlinked unpacked folders.
- The SoC/CoP layouts are byte-identical to the field-tested portable rigs
  (`~/soc-openxray`, `~/cop-openxray`).

## i18n (interface languages)

The launcher is fully translated (English / Русский):

- Translations live in `launcher/config/locales/{en,ru}.yml` and are
  **embedded into the binary at compile time** (`I18n::Loader::YAML.embed`,
  [crystal-i18n](https://github.com/crystal-i18n/i18n)) — a distributed
  `xr-launcher` carries its catalogs and needs no locale files on disk.
  Because of that, **builds must run from `launcher/`** (both the embed and
  the exml `read_file` resolve from the compile working directory; the
  Rakefile and crosspack steps already do).
- The active language is picked at startup: the saved setting wins, else
  the system locale (`LANG`/`LC_ALL`, `ru_RU.UTF-8` → Russian), else
  English. It is stored as `"locale"` in `launcher.json` and switched
  live from the **Settings → Настройки** menu (File/Settings/Help menu
  bar — exml-declarative, `assets/launcher.exml`) or the combo box on the
  Settings page; a switch applies on the next frame.
- The exml markup (menu bar, settings page, status bar) interpolates i18n
  store slots (`{menu_file}` …), so translated chrome needs no markup
  duplication. The dynamic home (game tabs, installs, wizard) renders
  natively through the same `L.t` seam.
- All core messages (validation errors, install log lines, CLI output)
  go through `Launcher::L.t` with English fallbacks, so even a headless
  CLI on a system without the locale still speaks English. `spec/i18n_spec.cr`
  enforces that every locale file carries the full key set — a new string
  without translations fails the spec suite, not the user.

Adding a language: copy `en.yml` → `<code>.yml`, translate the values,
add the code to `Locale::AVAILABLE` (`src/launcher/i18n.cr`). The key-set
spec picks the new file up automatically.

## Launcher state

- The install list lives only in the config (single source of truth; no
  on-disk install markers). Saves are atomic (PID-suffixed tmp + rename)
  and keep the previous config as `launcher.json.bak`; a corrupt config is
  backed up to `launcher.json.corrupt` instead of being silently reset.
- Only one launcher instance may run: an exclusive `flock` on
  `<config_dir>/lock`; a second instance exits with an "already running"
  error (localized) instead of racing over the config.
- Index + recents:
  `~/.config/xr-launcher/launcher.json` (Linux) / `%APPDATA%\xr-launcher\`
  (Windows) / `~/Library/Application Support/xr-launcher/` (macOS).

## CLI (headless)

The GUI binary doubles as a CLI — same file, same logic:

```bash
xr-launcher list
xr-launcher install soc --engine ~/xray-16 --source ~/GOG/soc --dir ~/Games/OpenXRay/soc
xr-launcher run    ~/Games/OpenXRay/soc
xr-launcher remove ~/Games/OpenXRay/soc
```

## Desktop shortcut

`assets/icons/launcher.png` is the app logo (radiation trefoil — generated,
no licensing baggage); per-game icons come from `misc/media/icons`. A
Linux menu entry:

```ini
[Desktop Entry]
Type=Application
Name=OpenXRay Launcher
Comment=Assemble and run S.T.A.L.K.E.R. on OpenXRay
Exec=/path/to/xr-launcher
Icon=/path/to/launcher/assets/icons/launcher.png
Categories=Game;
```

`assets/xr-launcher.desktop` ships this template with `TryExec=xr-launcher`
— install to `~/.local/share/applications/` and fix the icon path, or let
a distro package substitute the prefix.

## Layout / code map

```
  src/launcher.cr          library entry + headless CLI (no egui)
  src/launcher_gui.cr      egui-cr GUI: exml chrome + native home — the
                           only egui-dependent file
  src/launcher/i18n.cr     locale init/switch + the L.t lookup seam
  src/launcher/catalog.cr  game definitions: mode flags, fsgame.ltx
                           templates, source validation
  src/launcher/engine.cr   engine folder detection (checkout / bin dir /
                           installed prefix)
  src/launcher/installer.cr  the assembler (symlinks, overlays, config)
  src/launcher/uninstaller.cr safe recursive delete (config-gated,
                             symlink-aware)
  src/launcher/runner.cr   detached launch with the right cwd + mode flag
  src/launcher/store.cr    JSON index of installs + locale setting
  src/launcher/single_instance.cr  flock guard: one launcher at a time
  src/launcher/paths.cr    per-OS config dirs (spec-overridable)
  assets/launcher.exml     declarative UI: menu bar, settings page,
                           status bar (hot-reloads; embedded as a
                           compile-time fallback)
  config/locales/*.yml     embedded translations (en/ru)
  spec/                    headless specs (fake engine + fake game trees,
                           locale key-set completeness)
```

Verification: `rake spec` (unit) and the real-world end-to-end — install
SoC/CoP from a GOG copy, launch, check `_appdata_/logs/` for `FATAL` /
`SCRIPT RUNTIME ERROR` / early log end, then remove.
