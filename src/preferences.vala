namespace Pince {
    [GtkTemplate (ui = "/io/github/essicolo/Pince/preferences.ui")]
    public class Preferences : Adw.PreferencesDialog {
        [GtkChild] unowned Adw.ComboRow format_row;
        [GtkChild] unowned Adw.SwitchRow auto_rename_row;
        [GtkChild] unowned Adw.SwitchRow auto_fetch_row;
        [GtkChild] unowned Adw.EntryRow crossref_email_row;

        private Settings? settings = null;

        public Preferences () {
            // Try to load GSettings — may not be available in dev builds
            var schema_source = SettingsSchemaSource.get_default ();
            if (schema_source != null) {
                var schema = schema_source.lookup ("io.github.essicolo.Pince", true);
                if (schema != null) {
                    settings = new Settings ("io.github.essicolo.Pince");
                    format_row.selected = settings.get_enum ("default-format");
                    auto_rename_row.active = settings.get_boolean ("auto-rename-on-import");
                    auto_fetch_row.active = settings.get_boolean ("auto-fetch-doi");
                    crossref_email_row.text = settings.get_string ("crossref-email");
                }
            }

            format_row.notify["selected"].connect (() => {
                if (settings != null) {
                    settings.set_enum ("default-format", (int) format_row.selected);
                }
            });
            auto_rename_row.notify["active"].connect (() => {
                if (settings != null) {
                    settings.set_boolean ("auto-rename-on-import", auto_rename_row.active);
                }
            });
            auto_fetch_row.notify["active"].connect (() => {
                if (settings != null) {
                    settings.set_boolean ("auto-fetch-doi", auto_fetch_row.active);
                }
            });
            crossref_email_row.changed.connect (() => {
                if (settings != null) {
                    settings.set_string ("crossref-email", crossref_email_row.text);
                }
            });
        }
    }
}
