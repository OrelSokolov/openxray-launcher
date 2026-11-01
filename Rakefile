# xr-launcher build tasks. Mirrors egui-cr's flow: the native sokol
# shims must be compiled inside lib/egui-cr before crystal can link.
#
#   rake deps        # shards install (uses shards.override.yml)
#   rake native      # build egui-cr's vendored C inside lib/egui-cr
#   rake build       # debug build  -> bin/xr-launcher[.exe]
#   rake build:dev   # debug build with the widget inspector (F12)
#                    #   -> bin/xr-launcher-dev[.exe]
#   rake release     # release build -> bin/xr-launcher[.exe]
#   rake spec        # headless specs (no egui backend required)
#   rake all         # deps + native + release

WINDOWS = Gem.win_platform?
DARWIN  = RUBY_PLATFORM.include?("darwin")

NATIVE_LIB = WINDOWS ? "lib/egui-cr/lib/egui_cr_sokol.lib" : "lib/egui-cr/lib/libegui_cr_sokol.a"
BIN = WINDOWS ? "bin/xr-launcher.exe" : "bin/xr-launcher"
BIN_DEV = WINDOWS ? "bin/xr-launcher-dev.exe" : "bin/xr-launcher-dev"
LIBDIR = File.expand_path(File.dirname(__FILE__) + "/lib/egui-cr/lib")

# Link flags mirror egui-cr's Rakefile: MSVC Crystal resolves library
# search dirs from /LIBPATH: (not -L), macOS needs the Cocoa/GL
# frameworks the sokol shim references, Linux just the lib dir.
LINK_FLAGS = if WINDOWS
               "/LIBPATH:#{LIBDIR}"
             elsif DARWIN
               "-L#{LIBDIR} -framework Cocoa -framework OpenGL " \
               "-framework QuartzCore -framework AVFoundation -framework CoreMedia " \
               "-framework IOKit"
             else
               "-L#{LIBDIR}"
             end

task :deps do
  sh "shards install"
end

file NATIVE_LIB do
  sh "cd lib/egui-cr && rake build:native"
end

task :native => [NATIVE_LIB]

task :build => [:native] do
  # Double quotes: the flags must stay grouped under cmd.exe too.
  sh "crystal build src/launcher_gui.cr -o #{BIN} --link-flags \"#{LINK_FLAGS}\""
end

# Debug build with egui.cr's widget inspector compiled in: the panel
# opens on F12 (right-click → «Inspect» too) — see the inspector:
# flag in src/launcher_gui.cr's Egui.run call.
task "build:dev" => [:native] do
  sh "crystal build -Dwidget_inspector src/launcher_gui.cr -o #{BIN_DEV} --link-flags \"#{LINK_FLAGS}\""
end

task :release => [:native] do
  sh "crystal build --release src/launcher_gui.cr -o #{BIN} --link-flags \"#{LINK_FLAGS}\""
end

task :spec do
  sh "crystal spec"
end

task :cli do
  sh "crystal build src/launcher.cr -o bin/xr-launcher-cli"
end

task :all => [:deps, :release]

task :default => :build
