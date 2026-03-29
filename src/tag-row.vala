namespace Pince {
    public class TagRow : Gtk.ListBoxRow {
        public string tag_name { get; private set; }

        public TagRow (string tag, int count) {
            this.tag_name = tag;

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            box.margin_start = 8;
            box.margin_end = 8;
            box.margin_top = 4;
            box.margin_bottom = 4;

            var label = new Gtk.Label (tag);
            label.xalign = 0;
            label.hexpand = true;
            label.ellipsize = Pango.EllipsizeMode.END;
            box.append (label);

            var count_label = new Gtk.Label (count.to_string ());
            count_label.add_css_class ("dim-label");
            count_label.add_css_class ("caption");
            box.append (count_label);

            this.child = box;
        }
    }
}
