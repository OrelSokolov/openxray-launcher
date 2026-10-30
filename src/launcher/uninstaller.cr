# Removal of a launcher-created distribution. Two invariants:
#   1. never touch anything outside the install dir (verified by the
#      `.installed_ok` marker — no marker, no delete);
#   2. never follow symlinks while deleting — game data archives stay
#      in the original copy the symlinks point at.

require "./paths"
require "./i18n"
require "./store"

module Launcher
  module Uninstaller
    class UnsafeDeleteError < Exception
    end

    # Remove the launcher-created install at `path`, dropping it from the
    # store. `path` must carry our marker; the original game copy and the
    # engine folder are never modified.
    def self.remove(path : String, store : Store? = nil,
                    &log : String -> Nil) : Nil
      path = File.expand_path(path)
      marker = File.join(path, Paths::MARKER_NAME)

      raise UnsafeDeleteError.new(L.t("errors.no_marker", path: path)) unless File.exists?(marker)
      raise UnsafeDeleteError.new(L.t("errors.refuse_root")) if path == "/"

      log.call(L.t("install.removing", path: path))
      remove_dir(path)
      store.try &.remove_install(path)
      store.try &.save
      log.call(L.t("install.removed", path: path))
    end

    # Recursive delete that treats symlinks (files AND directories) as
    # leaves: the link goes, the target stays.
    def self.remove_dir(path : String) : Nil
      if File.symlink?(path) || !Dir.exists?(path)
        File.delete(path) if File.exists?(path) || File.symlink?(path)
      else
        Dir.children(path).each do |name|
          remove_dir(File.join(path, name))
        end
        Dir.delete(path)
      end
    end
  end
end
