namespace Pince {
    public class Utils {
        public static async string read_stream_to_string (InputStream input_stream) throws Error {
            var output = new MemoryOutputStream.resizable ();
            yield output.splice_async (
                input_stream,
                OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET,
                Priority.DEFAULT,
                null
            );
            var data = output.steal_data ();
            var size = output.get_data_size ();
            data[size] = 0;
            return (string) data;
        }

        public static string get_filetype_icon_name (string filetype) {
            switch (filetype) {
                case "pdf":
                    return "x-office-document-symbolic";
                case "docx":
                case "doc":
                case "odt":
                    return "x-office-document-symbolic";
                case "txt":
                case "md":
                case "tex":
                    return "text-x-generic-symbolic";
                case "epub":
                    return "x-office-document-symbolic";
                case "html":
                case "htm":
                    return "text-html-symbolic";
                default:
                    return "document-open-symbolic";
            }
        }

        public static void open_file (string path) {
            var file = File.new_for_path (path);
            var launcher = new Gtk.FileLauncher (file);
            launcher.launch.begin (null, null);
        }

        public static void open_folder (string folder_path) {
            var file = File.new_for_path (folder_path);
            var launcher = new Gtk.FileLauncher (file);
            launcher.launch.begin (null, null);
        }

        public static string resolve_path (string path, string library_dir) {
            if (Path.is_absolute (path)) return path;
            return Path.build_filename (library_dir, path);
        }
    }
}
