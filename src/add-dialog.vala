namespace Pince {

    private class ImportEntry {
        public Document document;
        public Adw.ExpanderRow expander;
        public Adw.EntryRow title_row;
        public Adw.EntryRow authors_row;
        public Adw.EntryRow year_row;
        public Adw.EntryRow tags_row;
        public Adw.EntryRow doi_row;
        public bool is_duplicate = false;

        public ImportEntry (Document doc) {
            this.document = doc;
        }

        public void sync_to_document () {
            document.title = title_row.text;
            document.set_authors_from_string (authors_row.text);
            document.year = year_row.text;
            document.set_tags_from_string (tags_row.text);
            document.doi = doi_row.text.strip ();
        }

        public void sync_from_document () {
            title_row.text = document.title;
            authors_row.text = document.get_authors_display ();
            year_row.text = document.year;
            tags_row.text = document.get_tags_display ();
            doi_row.text = document.doi;
            expander.title = document.title.length > 0 ? document.title : "(Untitled)";
        }
    }

    [GtkTemplate (ui = "/io/github/essicolo/Pince/add-dialog.ui")]
    public class AddDialog : Adw.Dialog {
        [GtkChild] unowned Gtk.Button cancel_button;
        [GtkChild] unowned Gtk.Button add_all_button;
        [GtkChild] unowned Gtk.Button add_all_fetch_button;
        [GtkChild] unowned Adw.StatusPage progress_status;
        [GtkChild] unowned Gtk.Box results_box;
        [GtkChild] unowned Gtk.Label summary_label;
        [GtkChild] unowned Gtk.ListBox file_list;

        private Gee.ArrayList<ImportEntry> entries;
        private Library? library;

        public signal void documents_ready (Gee.ArrayList<Document> docs);

        public AddDialog (Library? lib) {
            entries = new Gee.ArrayList<ImportEntry> ();
            this.library = lib;
        }

        construct {
            cancel_button.clicked.connect (() => {
                close ();
            });

            add_all_button.clicked.connect (() => {
                add_all_and_close ();
            });

            add_all_fetch_button.clicked.connect (() => {
                fetch_then_add.begin ();
            });
        }

        private void add_all_and_close () {
            foreach (var entry in entries) {
                entry.sync_to_document ();
                // Auto-generate cite key from metadata
                entry.document.generate_cite_key ();
            }
            var docs = new Gee.ArrayList<Document> ();
            foreach (var entry in entries) {
                docs.add (entry.document);
            }
            documents_ready (docs);
            close ();
        }

        public async void extract_files (Gee.ArrayList<string> paths) {
            progress_status.visible = true;
            results_box.visible = false;

            foreach (var path in paths) {
                var doc = yield MetadataExtractor.extract (path);
                entries.add (new ImportEntry (doc));
            }

            show_results ();
        }

        private void show_results () {
            progress_status.visible = false;
            results_box.visible = true;

            int doi_count = 0;
            foreach (var entry in entries) {
                if (entry.document.doi.length > 0) doi_count++;
            }

            int dup_count = 0;
            foreach (var entry in entries) {
                if (entry.is_duplicate) dup_count++;
            }

            var summary = _("%d documents, %d with DOIs").printf (entries.size, doi_count);
            if (dup_count > 0) {
                summary += _(", %d possible duplicates").printf (dup_count);
            }
            summary_label.label = summary;

            add_all_button.sensitive = true;
            add_all_fetch_button.sensitive = true;

            if (doi_count > 0) {
                add_all_fetch_button.label = _("Add All + Fetch %d DOIs").printf (doi_count);
                add_all_fetch_button.tooltip_text =
                    _("Fetch metadata from api.crossref.org for %d documents with DOIs, then add all. Only the DOI string is sent (requires internet).").printf (doi_count);
            } else {
                add_all_fetch_button.label = _("Add All + Fetch DOIs");
                add_all_fetch_button.tooltip_text =
                    _("Enter DOIs manually in each row below, then click to fetch metadata from api.crossref.org and add all (requires internet).");
            }

            foreach (var entry in entries) {
                create_file_row (entry);
                file_list.append (entry.expander);
            }
        }

        private void create_file_row (ImportEntry entry) {
            var doc = entry.document;

            var expander = new Adw.ExpanderRow ();
            expander.title = doc.title.length > 0 ? doc.title : "(Untitled)";

            var basename = Path.get_basename (doc.path);
            var subtitle_parts = new Gee.ArrayList<string> ();
            if (doc.authors.size > 0) {
                subtitle_parts.add (doc.get_authors_display ());
            }
            if (doc.year.length > 0) {
                subtitle_parts.add (doc.year);
            }
            subtitle_parts.add (basename);
            var sub_arr = new string[subtitle_parts.size];
            for (int j = 0; j < subtitle_parts.size; j++) sub_arr[j] = subtitle_parts[j];
            expander.subtitle = string.joinv (" - ", sub_arr);

            var icon = new Gtk.Image ();
            icon.icon_name = Utils.get_filetype_icon_name (doc.filetype);
            expander.add_prefix (icon);

            if (doc.doi.length > 0) {
                var doi_icon = new Gtk.Image ();
                doi_icon.icon_name = "emblem-ok-symbolic";
                doi_icon.tooltip_text = "DOI: " + doc.doi;
                doi_icon.add_css_class ("success");
                expander.add_suffix (doi_icon);
            }

            // Check for duplicates
            if (library != null) {
                var dup = library.find_duplicate (doc);
                if (dup != null) {
                    var dup_icon = new Gtk.Image ();
                    dup_icon.icon_name = "dialog-warning-symbolic";
                    dup_icon.tooltip_text = _("Possible duplicate of: %s").printf (dup.title);
                    dup_icon.add_css_class ("warning");
                    expander.add_suffix (dup_icon);
                    entry.is_duplicate = true;
                }
            }

            var title_row = new Adw.EntryRow ();
            title_row.title = _("Title");
            title_row.text = doc.title;
            expander.add_row (title_row);

            var authors_row = new Adw.EntryRow ();
            authors_row.title = _("Authors (separated by \" and \")");
            authors_row.text = doc.get_authors_display ();
            expander.add_row (authors_row);

            var year_row = new Adw.EntryRow ();
            year_row.title = _("Year");
            year_row.text = doc.year;
            expander.add_row (year_row);

            var tags_row = new Adw.EntryRow ();
            tags_row.title = _("Tags (comma-separated)");
            tags_row.text = doc.get_tags_display ();
            expander.add_row (tags_row);

            var doi_row = new Adw.EntryRow ();
            doi_row.title = "DOI";
            doi_row.text = doc.doi;
            expander.add_row (doi_row);

            entry.expander = expander;
            entry.title_row = title_row;
            entry.authors_row = authors_row;
            entry.year_row = year_row;
            entry.tags_row = tags_row;
            entry.doi_row = doi_row;
        }

        private async void fetch_then_add () {
            // Read any user edits before fetching
            foreach (var entry in entries) {
                entry.sync_to_document ();
            }

            add_all_button.sensitive = false;
            add_all_fetch_button.sensitive = false;
            add_all_fetch_button.label = _("Fetching...");

            int fetched = 0;
            int errors = 0;

            foreach (var entry in entries) {
                var doc = entry.document;

                // If no DOI, try to find one by title search
                if (doc.doi.length == 0 && doc.title.length >= 5) {
                    try {
                        bool found = yield CrossRefClient.search_by_title (doc);
                        if (found) {
                            fetched++;
                            entry.sync_from_document ();
                            entry.expander.subtitle = Path.get_basename (doc.path) + " (found by title)";
                            continue;
                        }
                    } catch (Error e) {
                        // Title search failed, skip
                    }
                }

                if (doc.doi.length == 0) continue;

                // Clean DOI
                var doi = doc.doi;
                if (doi.has_prefix ("https://doi.org/")) {
                    doi = doi.substring ("https://doi.org/".length);
                } else if (doi.has_prefix ("http://doi.org/")) {
                    doi = doi.substring ("http://doi.org/".length);
                } else if (doi.has_prefix ("doi:")) {
                    doi = doi.substring ("doi:".length);
                }
                doc.doi = doi.strip ();

                try {
                    yield CrossRefClient.fetch_metadata (doc);
                    fetched++;
                    entry.sync_from_document ();
                    entry.expander.subtitle = Path.get_basename (doc.path) + " (metadata fetched)";
                } catch (Error e) {
                    errors++;
                    warning ("DOI fetch failed for %s: %s", doc.doi, e.message);
                }
            }

            summary_label.label = "%d documents, %d metadata fetched%s".printf (
                entries.size, fetched,
                errors > 0 ? ", %d failed".printf (errors) : ""
            );

            // Auto-add all documents after fetch
            add_all_and_close ();
        }
    }
}
