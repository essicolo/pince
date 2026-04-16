namespace Pince {
    [GtkTemplate (ui = "/io/github/essicolo/Pince/document-row.ui")]
    public class DocumentRow : Gtk.Box {
        [GtkChild] unowned Gtk.Image filetype_icon;
        [GtkChild] unowned Gtk.Label title_label;
        [GtkChild] unowned Gtk.Label subtitle_label;
        [GtkChild] unowned Gtk.Label year_label;
        [GtkChild] unowned Gtk.Image star_icon;
        [GtkChild] unowned Gtk.Image reading_status_icon;

        public Document? document { get; private set; }

        public signal void star_toggled ();

        public DocumentRow () {
            setup_star_click ();
        }

        private void setup_star_click () {
            var gesture = new Gtk.GestureClick ();
            gesture.button = Gdk.BUTTON_PRIMARY;
            gesture.pressed.connect ((n_press, x, y) => {
                if (document == null) return;
                document.starred = !document.starred;
                update_star ();
                star_toggled ();
            });
            star_icon.add_controller (gesture);
        }

        public void bind_document (Document doc) {
            this.document = doc;
            populate ();
        }

        public void unbind_document () {
            this.document = null;
        }

        private void update_star () {
            if (document == null) return;
            if (document.starred) {
                star_icon.icon_name = "starred-symbolic";
                star_icon.remove_css_class ("dim-label");
                star_icon.add_css_class ("warning");
            } else {
                star_icon.icon_name = "non-starred-symbolic";
                star_icon.remove_css_class ("warning");
                star_icon.add_css_class ("dim-label");
            }
        }

        private void update_reading_status () {
            if (document == null) return;
            reading_status_icon.visible = false;
            switch (document.reading_status) {
                case ReadingStatus.READ:
                    title_label.remove_css_class ("bold-label");
                    break;
                default:
                    // Unread — bold title
                    title_label.add_css_class ("bold-label");
                    break;
            }
        }

        private void populate () {
            if (document == null) return;

            title_label.label = document.title.length > 0 ? document.title : "(Untitled)";

            var parts = new Gee.ArrayList<string> ();
            var authors_str = document.get_authors_display ();
            if (authors_str.length > 0) {
                parts.add (authors_str);
            }
            if (document.tags.size > 0) {
                var tag_strs = new string[document.tags.size];
                for (int i = 0; i < document.tags.size; i++) {
                    tag_strs[i] = "#" + document.tags[i];
                }
                parts.add (string.joinv ("  ", tag_strs));
            }

            if (parts.size > 0) {
                var subtitle_parts = new string[parts.size];
                for (int i = 0; i < parts.size; i++) {
                    subtitle_parts[i] = parts[i];
                }
                subtitle_label.label = string.joinv ("  —  ", subtitle_parts);
                subtitle_label.visible = true;
            } else {
                subtitle_label.visible = false;
            }

            year_label.label = document.year;
            year_label.visible = document.year.length > 0;
            filetype_icon.icon_name = Utils.get_filetype_icon_name (document.filetype);
            update_star ();
            update_reading_status ();
        }
    }
}
