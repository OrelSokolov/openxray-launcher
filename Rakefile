# xr-launcher build tasks. Mirrors egui-cr's flow: the native sokol
# shims must be compiled inside lib/egui-cr before crystal can link.
#
#   rake deps        # shards install (uses shards.override.yml)
#   rake native      # build egui-cr's vendored C inside lib/egui-cr
#   rake build       # debug build  -> bin/xr-launcher
#   rake release     # release build -> bin/xr-launcher
#   rake spec        # headless specs (no egui backend required)
#   rake all         # deps + native + release

NATIVE_LIB = "lib/egui-cr/lib/libegui_cr_sokol.a"
BIN = "bin/xr-launcher"
LINK_FLAGS = "-L#{File.expand_path(File.dirname(__FILE__) + "/lib/egui-cr/lib")}"

task :deps do
  sh "shards install"
end

file NATIVE_LIB do
  sh "cd lib/egui-cr && rake build:native"
end

task :native => [NATIVE_LIB]

task :build => [:native] do
  sh "crystal build src/launcher_gui.cr -o #{BIN} --link-flags='#{LINK_FLAGS}'"
end

task :release => [:native] do
  sh "crystal build --release src/launcher_gui.cr -o #{BIN} --link-flags='#{LINK_FLAGS}'"
end

task :spec do
  sh "crystal spec"
end

task :cli do
  sh "crystal build src/launcher.cr -o bin/xr-launcher-cli"
end

task :all => [:deps, :release]

task :default => :build
