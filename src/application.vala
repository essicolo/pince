namespace Pince {
    public class Application : Adw.Application {
        public Application () {
            Object (
                application_id: "io.github.essicolo.Pince",
                flags: ApplicationFlags.HANDLES_OPEN
            );
        }

        construct {
            ActionEntry[] action_entries = {
                { "about", this.on_about_action },
                { "preferences", this.on_preferences_action },
                { "quit", this.quit },
                { "open-library", this.on_open_library },
                { "new-library", this.on_new_library },
            };
            this.add_action_entries (action_entries, this);
        }

        public override void startup () {
            base.startup ();

            // Keyboard shortcuts — must be set after startup
            this.set_accels_for_action ("app.quit", { "<primary>q" });
            this.set_accels_for_action ("app.open-library", { "<primary>o" });
            this.set_accels_for_action ("app.new-library", { "<primary>n" });
            this.set_accels_for_action ("win.toggle-search", { "<primary>f" });
            this.set_accels_for_action ("win.select-all", { "<primary>a" });

            // Register bundled icon so GTK finds it by app ID
            Gtk.IconTheme.get_for_display (Gdk.Display.get_default ())
                .add_resource_path ("/io/github/essicolo/Pince/icons");

            // Load custom CSS
            var css = new Gtk.CssProvider ();
            css.load_from_resource ("/io/github/essicolo/Pince/style.css");
            Gtk.StyleContext.add_provider_for_display (
                Gdk.Display.get_default (),
                css,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }

        public override void activate () {
            base.activate ();
            var win = this.active_window ?? new Window (this);
            win.present ();

            // Reopen last-used library
            var pince_win = (Window) win;
            if (pince_win.is_library_empty ()) {
                var last_path = RecentLibraries.get_last ();
                if (last_path != null) {
                    var file = File.new_for_path (last_path);
                    if (file.query_exists ()) {
                        pince_win.open_library_file (file);
                    }
                }
            }
        }

        public override void open (File[] files, string hint) {
            this.activate ();
            var win = this.active_window as Window;
            if (win != null && files.length > 0) {
                win.open_library_file (files[0]);
            }
        }

        private void on_about_action () {
            var about = new Adw.AboutDialog () {
                application_name = "Pince",
                application_icon = "io.github.essicolo.Pince",
                developer_name = "Pince Contributors",
                version = "0.1.0",
                developers = { "Pince Contributors" },
                copyright = "© 2026 Pince Contributors",
                license_type = Gtk.License.GPL_3_0,
                comments = _("A lightweight personal document library"),
                website = "https://github.com/essicolo/pince",
            };
            about.present (this.active_window);
        }

        private void on_preferences_action () {
            var prefs = new Preferences ();
            prefs.present (this.active_window);
        }

        private void on_open_library () {
            var win = this.active_window as Window;
            if (win != null) {
                win.show_open_library_dialog ();
            }
        }

        private void on_new_library () {
            var win = this.active_window as Window;
            if (win != null) {
                win.show_new_library_dialog ();
            }
        }
    }
}
