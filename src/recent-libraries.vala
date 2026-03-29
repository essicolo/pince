namespace Pince {
    /**
     * Manages a list of recently opened library file paths.
     * Stored in ~/.local/share/pince/recent-libraries.txt
     * One path per line, most recent first. Max 10 entries.
     */
    public class RecentLibraries {
        private const int MAX_ENTRIES = 10;

        private static string get_file_path () {
            var dir = Path.build_filename (Environment.get_user_data_dir (), "pince");
            return Path.build_filename (dir, "recent-libraries.txt");
        }

        public static Gee.ArrayList<string> load () {
            var list = new Gee.ArrayList<string> ();
            var path = get_file_path ();
            try {
                string contents;
                FileUtils.get_contents (path, out contents);
                foreach (var line in contents.split ("\n")) {
                    var trimmed = line.strip ();
                    if (trimmed.length > 0 && !list.contains (trimmed)) {
                        list.add (trimmed);
                    }
                }
            } catch (Error e) {
                // File doesn't exist yet — that's fine
            }
            return list;
        }

        public static void add (string library_path) {
            var list = load ();

            // Remove if already present (will re-add at top)
            list.remove (library_path);

            // Insert at the beginning
            list.insert (0, library_path);

            // Trim to max
            while (list.size > MAX_ENTRIES) {
                list.remove_at (list.size - 1);
            }

            save_list (list);
        }

        public static string? get_last () {
            var list = load ();
            if (list.size > 0) {
                return list[0];
            }
            return null;
        }

        private static void save_list (Gee.ArrayList<string> list) {
            var path = get_file_path ();
            var dir = Path.get_dirname (path);

            // Create directory if needed
            var dir_file = File.new_for_path (dir);
            try {
                if (!dir_file.query_exists ()) {
                    dir_file.make_directory_with_parents (null);
                }
            } catch (Error e) {
                warning ("Failed to create data dir: %s", e.message);
                return;
            }

            var sb = new StringBuilder ();
            foreach (var entry in list) {
                sb.append (entry);
                sb.append ("\n");
            }

            try {
                FileUtils.set_contents (path, sb.str);
            } catch (Error e) {
                warning ("Failed to save recent libraries: %s", e.message);
            }
        }
    }
}
