# Engine detection: turn a user-supplied "engine folder" into the two
# paths an install actually needs — the binaries and the engine-side
# gamedata overlay (res/gamedata: GL shaders, updated scripts).
#
# Recognized layouts, in order:
#   1. xray-16 checkout: <root>/bin/x86_64/Release/xr_3da + <root>/res/gamedata
#   2. a bin dir itself: <dir>/xr_3da + <dir>/../../..(res/gamedata)
#   3. installed prefix: <prefix>/lib/openxray/xr_3da + <prefix>/share/openxray/gamedata

module Launcher
  module Engine
    struct Location
      getter bin_dir : String
      getter res_gamedata : String   # engine's gamedata overlay root (has shaders/gl)
      getter kind : Symbol           # :repo, :bindir, :prefix

      def initialize(@bin_dir, @res_gamedata, @kind)
      end

      def executable : String
        File.join(bin_dir, executable_name)
      end
    end

    def self.executable_name : String
      {% if flag?(:win32) %} "xr_3da.exe" {% else %} "xr_3da" {% end %}
    end

    def self.resolve(dir : String) : Location?
      return nil if dir.empty? || !Dir.exists?(dir)

      exe = executable_name

      # 1. repo checkout
      release = File.join(dir, "bin", "x86_64", "Release")
      if File.exists?(File.join(release, exe)) &&
         res_gamedata_at?(File.join(dir, "res"))
        return Location.new(release, File.join(dir, "res", "gamedata"), :repo)
      end
      # arm64 mac checkout
      release = File.join(dir, "bin", "arm64", "Release")
      if File.exists?(File.join(release, exe)) &&
         res_gamedata_at?(File.join(dir, "res"))
        return Location.new(release, File.join(dir, "res", "gamedata"), :repo)
      end

      # 2. the bin dir itself (bin/x86_64/Release inside a checkout)
      if File.exists?(File.join(dir, exe))
        # bin/x86_64/Release -> up three levels is the repo root
        root = File.expand_path(File.join(dir, "..", "..", ".."))
        if res_gamedata_at?(File.join(root, "res"))
          return Location.new(dir, File.join(root, "res", "gamedata"), :bindir)
        end
        # bare binaries: usable, but no GL shaders -> renderer will be broken.
        # Still resolve (the install itself succeeds); the UI warns.
        return Location.new(dir, "", :bindir)
      end

      # 3. installed prefix (crosspack/deb layout: opt/openxray + share/openxray)
      libdir = File.join(dir, "lib", "openxray")
      share = File.join(dir, "share", "openxray", "gamedata")
      if File.exists?(File.join(libdir, exe)) && res_gamedata_at?(File.join(dir, "share", "openxray"))
        return Location.new(libdir, share, :prefix)
      end

      nil
    end

    private def self.res_gamedata_at?(res_root : String) : Bool
      gl = File.join(res_root, "gamedata", "shaders", "gl")
      Dir.exists?(gl) && !Dir.empty?(gl)
    end

    # Everything from bin_dir that the install should link (the engine
    # binary plus shared modules).
    def self.bin_files(bin_dir : String) : Array(String)
      Dir.children(bin_dir).select do |name|
        full = File.join(bin_dir, name)
        File.file?(full) && !File.symlink?(full) &&
          (name == executable_name ||
           name.matches?({% if flag?(:win32) %} /\.dll$/i {% else %} /\.so$/ {% end %}))
      end
    end
  end
end
