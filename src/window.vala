namespace Pince {
    [GtkTemplate (ui = "/io/github/essicolo/Pince/window.ui")]
    public class Window : Adw.ApplicationWindow {
        [GtkChild] unowned Adw.SplitButton add_button;
        [GtkChild] unowned Gtk.ToggleButton search_toggle;
        [GtkChild] unowned Adw.WindowTitle title_widget;
        [GtkChild] unowned Gtk.ToggleButton sidebar_toggle;
        [GtkChild] unowned Gtk.Paned sidebar_paned;
        [GtkChild] unowned Gtk.SearchBar search_bar;
        [GtkChild] unowned Gtk.SearchEntry search_entry;
        [GtkChild] unowned Gtk.ListBox tag_list;
        [GtkChild] unowned Gtk.Button clear_tag_button;
        [GtkChild] unowned Gtk.ToggleButton filter_starred;
        [GtkChild] unowned Gtk.ToggleButton filter_unread;
        [GtkChild] unowned Gtk.ToggleButton filter_read;
        [GtkChild] unowned Gtk.ListView document_list_view;
        [GtkChild] unowned Gtk.Label status_label;
        [GtkChild] unowned Gtk.Box detail_content;
        [GtkChild] unowned Adw.StatusPage detail_empty;
        [GtkChild] unowned Adw.EntryRow title_entry;
        [GtkChild] unowned Adw.EntryRow authors_entry;
        [GtkChild] unowned Adw.EntryRow year_entry;
        [GtkChild] unowned Adw.EntryRow tags_entry;
        [GtkChild] unowned Adw.EntryRow doi_entry;
        [GtkChild] unowned Adw.EntryRow isbn_entry;
        [GtkChild] unowned Gtk.Button fetch_metadata_button;
        [GtkChild] unowned Gtk.Spinner fetch_spinner;
        [GtkChild] unowned Gtk.Label fetch_status_label;
        [GtkChild] unowned Adw.EntryRow journal_entry;
        [GtkChild] unowned Adw.EntryRow volume_entry;
        [GtkChild] unowned Adw.EntryRow pages_entry;
        [GtkChild] unowned Adw.EntryRow publisher_entry;
        [GtkChild] unowned Gtk.TextView note_view;
        [GtkChild] unowned Gtk.Label abstract_label;
        [GtkChild] unowned Gtk.Label path_label;
        [GtkChild] unowned Gtk.Button open_file_button;
        [GtkChild] unowned Gtk.Button open_folder_button;
        [GtkChild] unowned Gtk.Button remove_button;
        [GtkChild] unowned Gtk.DropDown sort_dropdown;
        [GtkChild] unowned Gtk.ToggleButton star_toggle_button;
        [GtkChild] unowned Gtk.ToggleButton read_toggle_button;
        [GtkChild] unowned Gtk.LinkButton doi_link_button;
        [GtkChild] unowned Adw.ToastOverlay toast_overlay;
        [GtkChild] unowned Gtk.Button open_notes_button;
        [GtkChild] unowned Gtk.Button move_file_button;
        [GtkChild] unowned Gtk.Button rename_file_button;
        [GtkChild] unowned Adw.OverlaySplitView content_split;

        private Library library;
        private Document? selected_document = null;
        private string? active_tag_filter = null;
        private bool updating_detail = false;
        private Gee.ArrayList<string>? pending_drop_paths = null;
        private Gee.ArrayList<Document> undo_stack;
        private GLib.ListStore list_store;
        private Gtk.MultiSelection selection_model;
        private GLib.FileMonitor? folder_monitor = null;

        public Window (Application app) {
            Object (application: app);
        }

        public bool is_library_empty () {
            return library.file_path.length == 0;
        }

        construct {
            library = new Library ();
            undo_stack = new Gee.ArrayList<Document> ();

            add_button.clicked.connect (on_add_clicked);
            search_entry.search_changed.connect (on_search_changed);
            clear_tag_button.clicked.connect (on_clear_tag);
            tag_list.row_selected.connect (on_tag_selected);
            fetch_metadata_button.clicked.connect (on_fetch_metadata);
            open_file_button.clicked.connect (on_open_file);
            open_folder_button.clicked.connect (on_open_folder);
            remove_button.clicked.connect (on_remove_document);
            move_file_button.clicked.connect (on_move_files);
            rename_file_button.clicked.connect (on_rename_files);

            title_entry.changed.connect (on_detail_changed);
            authors_entry.changed.connect (on_detail_changed);
            year_entry.changed.connect (on_detail_changed);
            tags_entry.changed.connect (on_detail_changed);
            doi_entry.changed.connect (on_detail_changed);
            isbn_entry.changed.connect (on_detail_changed);
            journal_entry.changed.connect (on_detail_changed);
            volume_entry.changed.connect (on_detail_changed);
            pages_entry.changed.connect (on_detail_changed);
            publisher_entry.changed.connect (on_detail_changed);
            note_view.buffer.changed.connect (on_detail_changed);

            sort_dropdown.notify["selected"].connect (() => {
                refresh_document_list ();
            });

            star_toggle_button.toggled.connect (() => {
                if (updating_detail || selected_document == null) return;
                selected_document.starred = star_toggle_button.active;
                if (star_toggle_button.active) {
                    star_toggle_button.icon_name = "starred-symbolic";
                } else {
                    star_toggle_button.icon_name = "non-starred-symbolic";
                }
                library.update_document (selected_document);
                refresh_document_list ();
            });

            read_toggle_button.toggled.connect (() => {
                if (updating_detail || selected_document == null) return;
                selected_document.reading_status = read_toggle_button.active
                    ? ReadingStatus.READ : ReadingStatus.UNREAD;
                library.update_document (selected_document);
                refresh_document_list ();
            });

            // Sidebar toggle
            sidebar_toggle.active = true;
            sidebar_toggle.toggled.connect (() => {
                var start = sidebar_paned.start_child;
                if (start != null) {
                    start.visible = sidebar_toggle.active;
                }
            });

            // Filter buttons — reading status toggles are mutually exclusive
            filter_starred.toggled.connect (() => {
                refresh_document_list ();
            });
            filter_unread.toggled.connect (() => {
                if (filter_unread.active) filter_read.active = false;
                refresh_document_list ();
            });
            filter_read.toggled.connect (() => {
                if (filter_read.active) filter_unread.active = false;
                refresh_document_list ();
            });

            library.changed.connect (refresh_view);

            setup_drag_drop ();

            // Save library on window close
            this.close_request.connect (() => {
                if (library.file_path.length > 0) {
                    try {
                        library.save ();
                    } catch (Error e) {
                        warning ("Save on close failed: %s", e.message);
                    }
                }
                return false;  // allow close
            });
            setup_list_view ();

            var search_action = new SimpleAction ("toggle-search", null);
            search_action.activate.connect (() => {
                search_toggle.active = !search_toggle.active;
                if (search_toggle.active) {
                    search_entry.grab_focus ();
                }
            });
            this.add_action (search_action);

            var dup_action = new SimpleAction ("find-duplicates", null);
            dup_action.activate.connect (on_find_duplicates);
            this.add_action (dup_action);

            var stats_action = new SimpleAction ("show-stats", null);
            stats_action.activate.connect (on_show_stats);
            this.add_action (stats_action);

            var props_action = new SimpleAction ("library-properties", null);
            props_action.activate.connect (on_library_properties);
            this.add_action (props_action);

            var recent_action = new SimpleAction ("recent-libraries", null);
            recent_action.activate.connect (on_recent_libraries);
            this.add_action (recent_action);

            var merge_action = new SimpleAction ("merge-library", null);
            merge_action.activate.connect (on_merge_library);
            this.add_action (merge_action);

            var undo_remove_action = new SimpleAction ("undo-remove", null);
            undo_remove_action.activate.connect (() => {
                if (undo_stack.size > 0) {
                    var doc = undo_stack.remove_at (undo_stack.size - 1);
                    library.add_document (doc);
                }
            });
            this.add_action (undo_remove_action);

            var remove_action = new SimpleAction ("remove-document", null);
            remove_action.activate.connect (() => {
                on_remove_document ();
            });
            this.add_action (remove_action);

            var select_all_action = new SimpleAction ("select-all", null);
            select_all_action.activate.connect (() => {
                selection_model.select_all ();
            });
            this.add_action (select_all_action);

            // Add Folder action
            var add_folder_action = new SimpleAction ("add-folder", null);
            add_folder_action.activate.connect (() => {
                on_add_folder ();
            });
            this.add_action (add_folder_action);

            // Rename All action
            var rename_all_action = new SimpleAction ("rename-all", null);
            rename_all_action.activate.connect (() => {
                on_rename_all ();
            });
            this.add_action (rename_all_action);

            // Watch Folder action
            var watch_action = new SimpleAction ("watch-folder", null);
            watch_action.activate.connect (on_watch_folder);
            this.add_action (watch_action);

            // Stop Watching action
            var stop_watch_action = new SimpleAction ("stop-watching", null);
            stop_watch_action.activate.connect (on_stop_watching);
            this.add_action (stop_watch_action);

            // Open linked notes in external editor
            open_notes_button.clicked.connect (on_open_notes);

            // Restore watched folder from settings on startup
            restore_watched_folder ();
        }

        private void setup_drag_drop () {
            var drop_target = new Gtk.DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop_target.drop.connect (on_drop);
            ((Gtk.Widget) this).add_controller (drop_target);
        }

        private bool on_drop (Value value, double x, double y) {
            var file_list = (Gdk.FileList) value;
            var files = file_list.get_files ();

            var paths = new Gee.ArrayList<string> ();
            foreach (var file in files) {
                paths.add (file.get_path ());
            }

            if (paths.size > 0) {
                if (library.file_path.length == 0) {
                    pending_drop_paths = paths;
                    prompt_create_library_then_add ();
                } else {
                    add_files.begin (paths);
                }
            }

            return true;
        }

        private void prompt_create_library_then_add () {
            var dialog = new Adw.AlertDialog (
                _("No Library Open"),
                _("Create or open a library before adding documents.")
            );
            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("create", _("Create Library"));
            dialog.set_response_appearance ("create", Adw.ResponseAppearance.SUGGESTED);
            dialog.default_response = "create";

            dialog.response.connect ((response) => {
                if (response == "create") {
                    create_library_for_pending_files ();
                } else {
                    pending_drop_paths = null;
                }
            });

            dialog.present (this);
        }

        private void create_library_for_pending_files () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Create Library");
            dialog.initial_name = "library.json";

            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            var json_filter = new Gtk.FileFilter ();
            json_filter.name = _("CSL JSON (.json)");
            json_filter.add_pattern ("*.json");
            filters.append (json_filter);
            var bib_filter = new Gtk.FileFilter ();
            bib_filter.name = _("BibTeX (.bib)");
            bib_filter.add_pattern ("*.bib");
            filters.append (bib_filter);
            dialog.filters = filters;

            dialog.save.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.save.end (res);
                    setup_new_library (file.get_path ());
                    if (pending_drop_paths != null) {
                        add_files.begin (pending_drop_paths);
                        pending_drop_paths = null;
                    }
                } catch (Error e) {
                    pending_drop_paths = null;
                }
            });
        }

        private void setup_new_library (string path) {
            library = new Library ();
            library.changed.connect (refresh_view);
            var fmt = path.has_suffix (".bib") ? LibraryFormat.BIBTEX : LibraryFormat.CSL_JSON;
            try {
                library.save_as (path, fmt);
                save_last_library_path (path);
            } catch (Error e) {
                warning ("Failed to create library: %s", e.message);
            }
            refresh_view ();
        }

        private async void add_files (Gee.ArrayList<string> paths) {
            if (library.file_path.length == 0) return;

            var dialog = new AddDialog (library);
            dialog.documents_ready.connect ((docs) => {
                foreach (var doc in docs) {
                    library.add_document (doc);
                }
                // Auto-rename if preference is enabled
                if (should_auto_rename ()) {
                    rename_documents_sync (docs);
                }
            });
            dialog.present (this);
            yield dialog.extract_files (paths);
        }

        private void on_add_clicked () {
            if (library.file_path.length == 0) {
                prompt_create_library_then_add ();
                return;
            }

            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Add Documents");

            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            var all_docs = new Gtk.FileFilter ();
            all_docs.name = _("Documents");
            all_docs.add_mime_type ("application/pdf");
            all_docs.add_mime_type ("application/vnd.openxmlformats-officedocument.wordprocessingml.document");
            all_docs.add_mime_type ("application/vnd.oasis.opendocument.text");
            all_docs.add_mime_type ("text/plain");
            all_docs.add_pattern ("*.pdf");
            all_docs.add_pattern ("*.docx");
            all_docs.add_pattern ("*.odt");
            all_docs.add_pattern ("*.txt");
            all_docs.add_pattern ("*.epub");
            all_docs.add_pattern ("*.md");
            filters.append (all_docs);

            var all_files = new Gtk.FileFilter ();
            all_files.name = _("All Files");
            all_files.add_pattern ("*");
            filters.append (all_files);

            dialog.filters = filters;

            dialog.open_multiple.begin (this, null, (obj, res) => {
                try {
                    var files = dialog.open_multiple.end (res);
                    var paths = new Gee.ArrayList<string> ();
                    for (uint i = 0; i < files.get_n_items (); i++) {
                        var file = (File) files.get_item (i);
                        paths.add (file.get_path ());
                    }
                    if (paths.size > 0) {
                        add_files.begin (paths);
                    }
                } catch (Error e) {}
            });
        }

        private void on_add_folder () {
            if (library.file_path.length == 0) {
                prompt_create_library_then_add ();
                return;
            }

            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Add Folder");

            dialog.select_folder.begin (this, null, (obj, res) => {
                try {
                    var folder = dialog.select_folder.end (res);
                    collect_folder_files.begin (folder.get_path ());
                } catch (Error e) {}
            });
        }

        private async void collect_folder_files (string folder_path) {
            string[] supported_extensions = { ".pdf", ".docx", ".odt", ".txt", ".epub", ".md" };
            var paths = new Gee.ArrayList<string> ();

            try {
                var dir = Dir.open (folder_path);
                string? name;
                while ((name = dir.read_name ()) != null) {
                    var lower = name.down ();
                    bool supported = false;
                    foreach (var ext in supported_extensions) {
                        if (lower.has_suffix (ext)) {
                            supported = true;
                            break;
                        }
                    }
                    if (supported) {
                        paths.add (Path.build_filename (folder_path, name));
                    }
                }
            } catch (Error e) {
                warning ("Failed to read folder: %s", e.message);
                return;
            }

            if (paths.size == 0) {
                var toast = new Adw.Toast (_("No supported documents found in folder"));
                toast.timeout = 3;
                toast_overlay.add_toast (toast);
                return;
            }

            // Sort for consistent ordering
            paths.sort ((a, b) => {
                return strcmp (a.down (), b.down ());
            });

            yield add_files (paths);
        }

        private void on_search_changed () {
            refresh_document_list ();
        }

        private void on_clear_tag () {
            tag_list.unselect_all ();
            active_tag_filter = null;
            filter_starred.active = false;
            filter_unread.active = false;
            filter_read.active = false;
            refresh_document_list ();
        }

        private void on_tag_selected (Gtk.ListBoxRow? row) {
            if (row == null) {
                active_tag_filter = null;
            } else {
                var tag_row = row as TagRow;
                if (tag_row != null) {
                    active_tag_filter = tag_row.tag_name;
                }
            }
            refresh_document_list ();
        }

        private Gee.ArrayList<Document> get_selected_documents () {
            var docs = new Gee.ArrayList<Document> ();
            var bitset = selection_model.get_selection ();
            uint pos = 0;
            uint val;
            // Iterate through the selection bitset
            if (bitset.get_size () > 0) {
                var iter = Gtk.BitsetIter ();
                if (iter.init_first (bitset, out val)) {
                    docs.add ((Document) list_store.get_item (val));
                    while (iter.next (out val)) {
                        docs.add ((Document) list_store.get_item (val));
                    }
                }
            }
            return docs;
        }

        private void setup_list_view () {
            list_store = new GLib.ListStore (typeof (Document));

            selection_model = new Gtk.MultiSelection (list_store);
            selection_model.selection_changed.connect (() => {
                var selected = get_selected_documents ();
                if (selected.size == 1) {
                    selected_document = selected[0];
                    show_detail (true);
                    populate_detail ();
                } else if (selected.size > 1) {
                    selected_document = selected[0];
                    show_detail (true);
                    populate_detail ();
                } else {
                    selected_document = null;
                    hide_detail ();
                }
            });

            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((obj) => {
                var li = (Gtk.ListItem) obj;
                var row = new DocumentRow ();
                row.star_toggled.connect (() => {
                    if (row.document != null) {
                        library.update_document (row.document);
                        if (selected_document == row.document) {
                            populate_detail ();
                        }
                    }
                });
                li.child = row;

                // Double-click to open file
                var dbl_click = new Gtk.GestureClick ();
                dbl_click.button = Gdk.BUTTON_PRIMARY;
                dbl_click.pressed.connect ((n_press, x, y) => {
                    if (n_press == 2 && row.document != null) {
                        var path = row.document.get_resolved_path (get_library_dir ());
                        Utils.open_file (path);
                    }
                });
                li.child.add_controller (dbl_click);

                // Right-click context menu
                setup_item_context_menu (li, row);
            });

            factory.bind.connect ((obj) => {
                var li = (Gtk.ListItem) obj;
                var row = li.child as DocumentRow;
                var doc = li.item as Document;
                if (row != null && doc != null) {
                    row.bind_document (doc);
                }
            });

            factory.unbind.connect ((obj) => {
                var li = (Gtk.ListItem) obj;
                var row = li.child as DocumentRow;
                if (row != null) {
                    row.unbind_document ();
                }
            });

            document_list_view.factory = factory;
            document_list_view.model = selection_model;
            document_list_view.add_css_class ("document-list");
        }

        private void setup_item_context_menu (Gtk.ListItem list_item, DocumentRow row) {
            var menu = new GLib.Menu ();
            menu.append (_("Open File"), "row.open-file");
            menu.append (_("Open Folder"), "row.open-folder");

            var file_ops_section = new GLib.Menu ();
            file_ops_section.append (_("Move to..."), "row.move-files");
            file_ops_section.append (_("Rename (Author-Year)"), "row.rename-files");
            menu.append_section (null, file_ops_section);

            var status_section = new GLib.Menu ();
            status_section.append (_("Mark as Unread"), "row.mark-unread");
            status_section.append (_("Mark as Read"), "row.mark-read");
            status_section.append (_("Toggle Star"), "row.toggle-star");
            menu.append_section (null, status_section);

            var select_section = new GLib.Menu ();
            select_section.append (_("Select All"), "row.select-all");
            menu.append_section (null, select_section);

            var citation_section = new GLib.Menu ();
            citation_section.append (_("Copy Citation (APA)"), "row.copy-apa");
            citation_section.append (_("Copy Citation (BibTeX)"), "row.copy-bibtex");
            menu.append_section (null, citation_section);

            var delete_section = new GLib.Menu ();
            delete_section.append (_("Remove"), "row.remove");
            menu.append_section (null, delete_section);

            var action_group = new SimpleActionGroup ();

            var open_action = new SimpleAction ("open-file", null);
            open_action.activate.connect (() => {
                if (row.document == null) return;
                var path = row.document.get_resolved_path (get_library_dir ());
                Utils.open_file (path);
            });
            action_group.add_action (open_action);

            var folder_action = new SimpleAction ("open-folder", null);
            folder_action.activate.connect (() => {
                if (row.document == null) return;
                var folder = row.document.get_folder_path (get_library_dir ());
                Utils.open_folder (folder);
            });
            action_group.add_action (folder_action);

            var remove_action = new SimpleAction ("remove", null);
            remove_action.activate.connect (() => {
                on_remove_document ();
            });
            action_group.add_action (remove_action);

            var apa_action = new SimpleAction ("copy-apa", null);
            apa_action.activate.connect (() => {
                var selected = get_selected_documents ();
                if (selected.size == 0 && row.document != null) {
                    selected.add (row.document);
                }
                var sb = new StringBuilder ();
                foreach (var doc in selected) {
                    if (sb.len > 0) sb.append ("\n\n");
                    sb.append (CitationFormatter.format_apa (doc));
                }
                Gdk.Display.get_default ().get_clipboard ().set_text (sb.str);
            });
            action_group.add_action (apa_action);

            var bibtex_action = new SimpleAction ("copy-bibtex", null);
            bibtex_action.activate.connect (() => {
                var selected = get_selected_documents ();
                if (selected.size == 0 && row.document != null) {
                    selected.add (row.document);
                }
                var sb = new StringBuilder ();
                foreach (var doc in selected) {
                    if (sb.len > 0) sb.append ("\n");
                    sb.append (CitationFormatter.format_bibtex (doc));
                }
                Gdk.Display.get_default ().get_clipboard ().set_text (sb.str);
            });
            action_group.add_action (bibtex_action);

            // Batch status actions — apply to all selected, or just this row
            var mark_unread_action = new SimpleAction ("mark-unread", null);
            mark_unread_action.activate.connect (() => {
                apply_to_selected_or_row (row, (doc) => {
                    doc.reading_status = ReadingStatus.UNREAD;
                });
            });
            action_group.add_action (mark_unread_action);

            var mark_read_action = new SimpleAction ("mark-read", null);
            mark_read_action.activate.connect (() => {
                apply_to_selected_or_row (row, (doc) => {
                    doc.reading_status = ReadingStatus.READ;
                });
            });
            action_group.add_action (mark_read_action);

            var toggle_star_action = new SimpleAction ("toggle-star", null);
            toggle_star_action.activate.connect (() => {
                apply_to_selected_or_row (row, (doc) => {
                    doc.starred = !doc.starred;
                });
            });
            action_group.add_action (toggle_star_action);

            var select_all_action = new SimpleAction ("select-all", null);
            select_all_action.activate.connect (() => {
                selection_model.select_all ();
            });
            action_group.add_action (select_all_action);

            var move_action = new SimpleAction ("move-files", null);
            move_action.activate.connect (() => {
                on_move_files ();
            });
            action_group.add_action (move_action);

            var rename_action = new SimpleAction ("rename-files", null);
            rename_action.activate.connect (() => {
                on_rename_files ();
            });
            action_group.add_action (rename_action);

            list_item.child.insert_action_group ("row", action_group);

            var popover = new Gtk.PopoverMenu.from_model (menu);
            popover.set_parent (list_item.child);
            popover.has_arrow = false;

            var gesture = new Gtk.GestureClick ();
            gesture.button = Gdk.BUTTON_SECONDARY;
            gesture.pressed.connect ((n_press, x, y) => {
                var rect = Gdk.Rectangle () { x = (int) x, y = (int) y, width = 1, height = 1 };
                popover.pointing_to = rect;
                popover.popup ();
            });
            list_item.child.add_controller (gesture);
        }

        private void show_detail (bool show) {
            detail_content.visible = show;
            detail_empty.visible = !show;
            content_split.show_sidebar = true;
        }

        private void hide_detail () {
            detail_content.visible = false;
            detail_empty.visible = true;
            content_split.show_sidebar = false;
        }

        private void populate_detail () {
            if (selected_document == null) return;

            updating_detail = true;
            title_entry.text = selected_document.title;
            authors_entry.text = selected_document.get_authors_display ();
            year_entry.text = selected_document.year;
            tags_entry.text = selected_document.get_tags_display ();
            doi_entry.text = selected_document.doi;
            isbn_entry.text = selected_document.isbn;
            journal_entry.text = selected_document.journal;
            volume_entry.text = selected_document.volume;
            pages_entry.text = selected_document.pages;
            publisher_entry.text = selected_document.publisher;
            note_view.buffer.text = selected_document.note;

            path_label.label = selected_document.path;

            fetch_status_label.visible = false;

            abstract_label.label = selected_document.abstract_text.length > 0
                ? selected_document.abstract_text
                : _("(No abstract)");

            // Star toggle
            star_toggle_button.active = selected_document.starred;
            star_toggle_button.icon_name = selected_document.starred
                ? "starred-symbolic" : "non-starred-symbolic";

            // Reading status
            read_toggle_button.active = selected_document.reading_status == ReadingStatus.READ;

            // DOI link
            if (selected_document.doi.length > 0) {
                doi_link_button.uri = "https://doi.org/" + selected_document.doi;
                doi_link_button.label = "https://doi.org/" + selected_document.doi;
                doi_link_button.visible = true;
            } else {
                doi_link_button.visible = false;
            }

            updating_detail = false;
        }

        private void on_detail_changed () {
            if (updating_detail || selected_document == null) return;

            selected_document.title = title_entry.text;
            selected_document.set_authors_from_string (authors_entry.text);
            selected_document.year = year_entry.text;
            selected_document.set_tags_from_string (tags_entry.text);
            selected_document.doi = doi_entry.text;
            selected_document.isbn = isbn_entry.text;
            selected_document.journal = journal_entry.text;
            selected_document.volume = volume_entry.text;
            selected_document.pages = pages_entry.text;
            selected_document.publisher = publisher_entry.text;
            selected_document.note = note_view.buffer.text;

            // Update DOI link
            if (selected_document.doi.length > 0) {
                doi_link_button.uri = "https://doi.org/" + selected_document.doi;
                doi_link_button.label = "https://doi.org/" + selected_document.doi;
                doi_link_button.visible = true;
            } else {
                doi_link_button.visible = false;
            }

            library.update_document (selected_document);
        }

        /**
         * Smart metadata fetch: if DOI is filled, fetch by DOI.
         * Otherwise, search by title. Tries OpenAlex first (broader
         * coverage: CrossRef + arXiv + PubMed), falls back to CrossRef.
         */
        private void on_fetch_metadata () {
            if (selected_document == null) return;

            var doi = doi_entry.text.strip ();
            var isbn_raw = isbn_entry.text.strip ();
            var title = title_entry.text.strip ();

            // Clean DOI if provided
            if (doi.length > 0) {
                if (doi.has_prefix ("https://doi.org/")) {
                    doi = doi.substring ("https://doi.org/".length);
                } else if (doi.has_prefix ("http://doi.org/")) {
                    doi = doi.substring ("http://doi.org/".length);
                } else if (doi.has_prefix ("doi:")) {
                    doi = doi.substring ("doi:".length);
                }
                doi = doi.strip ();
                selected_document.doi = doi;
                updating_detail = true;
                doi_entry.text = doi;
                updating_detail = false;
            }

            // Normalize ISBN (strip hyphens/spaces) so the validator and
            // OpenLibrary both see digits-only.
            string isbn_norm = "";
            if (isbn_raw.length > 0) {
                isbn_norm = IsbnClient.normalize_isbn (isbn_raw);
                selected_document.isbn = isbn_norm;
                updating_detail = true;
                isbn_entry.text = isbn_norm;
                updating_detail = false;
            }

            if (doi.length == 0 && isbn_norm.length == 0 && title.length < 5) {
                fetch_status_label.label = _("Enter a DOI, an ISBN, or a title to search.");
                fetch_status_label.remove_css_class ("success");
                fetch_status_label.add_css_class ("error");
                fetch_status_label.visible = true;
                return;
            }

            // Save title for search
            selected_document.title = title;

            fetch_metadata_button.sensitive = false;
            fetch_spinner.visible = true;
            fetch_spinner.spinning = true;
            fetch_status_label.remove_css_class ("error");
            fetch_status_label.remove_css_class ("success");

            // ISBN is the most specific identifier — try it first when present.
            if (isbn_norm.length > 0) {
                fetch_by_isbn.begin ();
            } else if (doi.length > 0) {
                fetch_by_doi.begin ();
            } else {
                fetch_by_title.begin ();
            }
        }

        private async void fetch_by_isbn () {
            if (!IsbnClient.is_valid_isbn (selected_document.isbn)) {
                finish_fetch_error (_("Invalid ISBN: must be 10 or 13 digits with a valid check digit."));
                return;
            }

            fetch_status_label.label = _("Fetching by ISBN from OpenLibrary...");
            fetch_status_label.visible = true;

            try {
                yield IsbnClient.fetch_metadata (selected_document);
                finish_fetch (true);
            } catch (Error e) {
                // OpenLibrary didn't have it — fall back to DOI / title if available.
                if (selected_document.doi.length > 0) {
                    fetch_status_label.label = _("ISBN not found, trying DOI...");
                    yield fetch_by_doi ();
                } else if (selected_document.title.length >= 5) {
                    fetch_status_label.label = _("ISBN not found, searching by title...");
                    yield try_title_search ();
                } else {
                    finish_fetch_error (_("No OpenLibrary entry for ISBN %s.").printf (selected_document.isbn));
                }
            }
        }

        /**
         * Types that indicate the DOI points to a sub-part rather than
         * a real scholarly work — discard these and try title search.
         */
        private static bool is_bad_entry_type (string t) {
            return t == "component" || t == "grant" || t == "peer-review"
                || t == "reference-entry";
        }

        private async void fetch_by_doi () {
            // Remember original title in case DOI fetch overwrites it with garbage
            var original_title = selected_document.title;

            // Try OpenAlex first (covers CrossRef + arXiv + more)
            fetch_status_label.label = _("Fetching by DOI from OpenAlex...");
            fetch_status_label.visible = true;

            bool got_good_result = false;

            try {
                yield OpenAlexClient.fetch_metadata (selected_document);
                if (!is_bad_entry_type (selected_document.entry_type)
                    && selected_document.title.length > 0) {
                    got_good_result = true;
                }
            } catch (Error e) {
                // OpenAlex failed (404 etc), will try CrossRef
            }

            if (!got_good_result) {
                // Fallback to CrossRef
                fetch_status_label.label = _("Trying CrossRef...");
                try {
                    yield CrossRefClient.fetch_metadata (selected_document);
                    if (!is_bad_entry_type (selected_document.entry_type)
                        && selected_document.title.length > 0) {
                        got_good_result = true;
                    }
                } catch (Error e) {
                    // CrossRef also failed
                }
            }

            // If DOI returned a bad type (component/grant), try title search instead
            if (!got_good_result || is_bad_entry_type (selected_document.entry_type)) {
                // Restore original title if DOI fetch overwrote with garbage
                if (original_title.length > 5) {
                    selected_document.title = original_title;
                }
                if (selected_document.title.length >= 5) {
                    fetch_status_label.label = _("DOI returned non-article type, searching by title...");
                    yield try_title_search ();
                    return;
                }
                finish_fetch_error (_("DOI returned a '%s', not a scholarly work. Try editing the DOI or title.").printf (
                    selected_document.entry_type));
                return;
            }

            finish_fetch (true);
        }

        private async void fetch_by_title () {
            yield try_title_search ();
        }

        private async void try_title_search () {
            var original_title = selected_document.title;

            // If the title looks like filename garbage, try extracting real title from PDF
            if (looks_like_filename_title (original_title)) {
                fetch_status_label.label = _("Title looks like a filename, reading PDF...");
                fetch_status_label.visible = true;
                var pdf_title = try_extract_pdf_title ();
                if (pdf_title != null && pdf_title.length >= 10) {
                    selected_document.title = pdf_title;
                }
            }

            // Try OpenAlex first (better coverage)
            fetch_status_label.label = _("Searching by title on OpenAlex...");
            fetch_status_label.visible = true;

            try {
                bool found = yield OpenAlexClient.search_by_title (selected_document);
                if (found && !is_bad_entry_type (selected_document.entry_type)) {
                    finish_fetch (true);
                    return;
                }
            } catch (Error e) {
                // OpenAlex failed, try CrossRef
            }

            // Fallback to CrossRef
            fetch_status_label.label = _("Trying CrossRef...");
            try {
                bool found = yield CrossRefClient.search_by_title (selected_document);
                if (found && !is_bad_entry_type (selected_document.entry_type)) {
                    finish_fetch (true);
                    return;
                }
            } catch (Error e) {
                // CrossRef also failed
            }

            // Restore original title if search replaced it
            if (selected_document.title == original_title || selected_document.title.length == 0) {
                selected_document.title = original_title;
            }

            finish_fetch_error (_("No match found. Try editing the title or adding a DOI."));
        }

        /**
         * Detect if a title looks like it was derived from a filename
         * rather than being a real paper title.
         */
        private bool looks_like_filename_title (string title) {
            if (title.length == 0) return true;

            // Contains hex hash prefix (12+ hex chars)
            try {
                var hex_regex = new Regex ("^[0-9a-f]{8,}", RegexCompileFlags.CASELESS);
                if (hex_regex.match (title, 0, null)) return true;
            } catch (RegexError e) {}

            // Very short (< 15 chars) and no spaces
            if (title.length < 15 && !title.contains (" ")) return true;

            return false;
        }

        /**
         * Try to extract the real title from the document's PDF file.
         * Returns null if extraction fails.
         */
        private string? try_extract_pdf_title () {
            if (selected_document == null) return null;
            if (selected_document.filetype != "pdf") return null;

            var path = selected_document.get_resolved_path (get_library_dir ());
            try {
                var file_uri = File.new_for_path (path).get_uri ();
                var pdf_doc = new Poppler.Document.from_file (file_uri, null);
                return MetadataExtractor.extract_title_from_pdf_text (pdf_doc);
            } catch (Error e) {
                return null;
            }
        }

        private void finish_fetch (bool found) {
            fetch_spinner.visible = false;
            fetch_spinner.spinning = false;
            fetch_metadata_button.sensitive = true;

            if (found) {
                show_fetch_success ();
            } else {
                fetch_status_label.label = _("No match found.");
                fetch_status_label.remove_css_class ("success");
                fetch_status_label.add_css_class ("error");
                fetch_status_label.visible = true;
            }
        }

        private void finish_fetch_error (string message) {
            fetch_spinner.visible = false;
            fetch_spinner.spinning = false;
            fetch_metadata_button.sensitive = true;
            fetch_status_label.label = message;
            fetch_status_label.remove_css_class ("success");
            fetch_status_label.add_css_class ("error");
            fetch_status_label.visible = true;
        }

        private void show_fetch_success () {
            var fields = new Gee.ArrayList<string> ();
            if (selected_document.title.length > 0) fields.add (_("title"));
            if (selected_document.authors.size > 0) fields.add (_("authors"));
            if (selected_document.year.length > 0) fields.add (_("year"));
            if (selected_document.journal.length > 0) fields.add (_("journal"));
            if (selected_document.abstract_text.length > 0) fields.add (_("abstract"));
            if (selected_document.publisher.length > 0) fields.add (_("publisher"));

            var field_parts = new string[fields.size];
            for (int i = 0; i < fields.size; i++) {
                field_parts[i] = fields[i];
            }

            fetch_status_label.label = _("Fetched: %s").printf (
                string.joinv (", ", field_parts)
            );
            fetch_status_label.remove_css_class ("error");
            fetch_status_label.add_css_class ("success");
            fetch_status_label.visible = true;

            populate_detail ();
            library.update_document (selected_document);
            refresh_document_list ();
        }

        private void on_find_duplicates () {
            var groups = library.find_all_duplicates ();

            if (groups.size == 0) {
                var dialog = new Adw.AlertDialog (
                    _("No Duplicates Found"),
                    _("No duplicate documents were found in the library.")
                );
                dialog.add_response ("ok", _("OK"));
                dialog.present (this);
                return;
            }

            var sb = new StringBuilder ();
            int total_dups = 0;
            foreach (var group in groups) {
                total_dups += group.size - 1;
                sb.append ("---\n");
                foreach (var doc in group) {
                    sb.append ("  %s".printf (doc.title));
                    if (doc.doi.length > 0) {
                        sb.append (" [%s]".printf (doc.doi));
                    }
                    sb.append ("\n");
                }
            }

            var dialog = new Adw.AlertDialog (
                ngettext (
                    "%d Duplicate Group Found",
                    "%d Duplicate Groups Found",
                    (ulong) groups.size
                ).printf (groups.size),
                _("%d documents appear to be duplicates:\n\n%s\nRemove duplicates? (Keeps the first entry in each group.)").printf (
                    total_dups, sb.str
                )
            );
            dialog.add_response ("cancel", _("Keep All"));
            dialog.add_response ("remove", _("Remove Duplicates"));
            dialog.set_response_appearance ("remove", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";

            dialog.response.connect ((response) => {
                if (response == "remove") {
                    foreach (var group in groups) {
                        for (int i = 1; i < group.size; i++) {
                            if (selected_document == group[i]) {
                                selected_document = null;
                                hide_detail ();
                            }
                            library.remove_document (group[i]);
                        }
                    }
                }
            });

            dialog.present (this);
        }

        private void on_show_stats () {
            if (library.documents.size == 0) {
                var dialog = new Adw.AlertDialog (
                    _("Library Statistics"),
                    _("No documents in the library.")
                );
                dialog.add_response ("ok", _("OK"));
                dialog.present (this);
                return;
            }

            var sb = new StringBuilder ();
            int total = library.documents.size;
            sb.append (_("Total documents: %d\n").printf (total));

            // Documents per filetype
            var filetypes = new Gee.HashMap<string, int> ();
            foreach (var doc in library.documents) {
                var ft = doc.filetype.length > 0 ? doc.filetype : "unknown";
                filetypes[ft] = filetypes.has_key (ft) ? filetypes[ft] + 1 : 1;
            }
            sb.append (_("\nDocuments per filetype:\n"));
            foreach (var entry in filetypes.entries) {
                sb.append ("  %s: %d\n".printf (entry.key, entry.value));
            }

            // Documents per year (top 10)
            var years = new Gee.HashMap<string, int> ();
            foreach (var doc in library.documents) {
                var yr = doc.year.length > 0 ? doc.year : "unknown";
                years[yr] = years.has_key (yr) ? years[yr] + 1 : 1;
            }
            // Sort by count descending
            var year_entries = new Gee.ArrayList<Gee.Map.Entry<string, int>> ();
            foreach (var entry in years.entries) {
                year_entries.add (entry);
            }
            year_entries.sort ((a, b) => {
                return b.value - a.value;
            });
            sb.append (_("\nTop years:\n"));
            int year_count = int.min (10, year_entries.size);
            for (int i = 0; i < year_count; i++) {
                sb.append ("  %s: %d\n".printf (year_entries[i].key, year_entries[i].value));
            }

            // Top 10 tags
            var tag_counts = new Gee.HashMap<string, int> ();
            foreach (var doc in library.documents) {
                foreach (var tag in doc.tags) {
                    tag_counts[tag] = tag_counts.has_key (tag) ? tag_counts[tag] + 1 : 1;
                }
            }
            var tag_entries = new Gee.ArrayList<Gee.Map.Entry<string, int>> ();
            foreach (var entry in tag_counts.entries) {
                tag_entries.add (entry);
            }
            tag_entries.sort ((a, b) => {
                return b.value - a.value;
            });
            if (tag_entries.size > 0) {
                sb.append (_("\nTop tags:\n"));
                int tag_limit = int.min (10, tag_entries.size);
                for (int i = 0; i < tag_limit; i++) {
                    sb.append ("  %s: %d\n".printf (tag_entries[i].key, tag_entries[i].value));
                }
            }

            // DOI stats
            int with_doi = 0;
            foreach (var doc in library.documents) {
                if (doc.doi.length > 0) with_doi++;
            }
            sb.append (_("\nWith DOI: %d\nWithout DOI: %d\n").printf (with_doi, total - with_doi));

            var dialog = new Adw.AlertDialog (
                _("Library Statistics"),
                sb.str
            );
            dialog.add_response ("ok", _("OK"));
            dialog.present (this);
        }

        private void on_recent_libraries () {
            var recent = RecentLibraries.load ();

            if (recent.size == 0) {
                var d = new Adw.AlertDialog (
                    _("No Recent Libraries"),
                    _("No libraries have been opened yet.")
                );
                d.add_response ("ok", _("OK"));
                d.present (this);
                return;
            }

            var dialog = new Adw.Dialog ();
            dialog.title = _("Recent Libraries");
            dialog.content_width = 450;
            dialog.content_height = 300;

            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = false;
            var close_btn = new Gtk.Button.with_label (_("Close"));
            header.pack_start (close_btn);
            toolbar.add_top_bar (header);

            var scrolled = new Gtk.ScrolledWindow ();
            scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;

            var listbox = new Gtk.ListBox ();
            listbox.selection_mode = Gtk.SelectionMode.NONE;
            listbox.add_css_class ("boxed-list");
            listbox.margin_start = 12;
            listbox.margin_end = 12;
            listbox.margin_top = 12;
            listbox.margin_bottom = 12;

            foreach (var path in recent) {
                var row = new Adw.ActionRow ();
                row.title = Path.get_basename (path);
                row.subtitle = path;
                row.activatable = true;
                row.add_suffix (new Gtk.Image.from_icon_name ("go-next-symbolic"));

                row.activated.connect (() => {
                    var file = File.new_for_path (path);
                    if (file.query_exists ()) {
                        open_library_file (file);
                        dialog.close ();
                    } else {
                        row.subtitle = _("File not found: %s").printf (path);
                    }
                });

                listbox.append (row);
            }

            scrolled.child = listbox;
            toolbar.content = scrolled;
            dialog.child = toolbar;

            close_btn.clicked.connect (() => {
                dialog.close ();
            });

            dialog.present (this);
        }

        private void on_library_properties () {
            if (library.file_path.length == 0) {
                var d = new Adw.AlertDialog (
                    _("No Library Open"),
                    _("Open or create a library first.")
                );
                d.add_response ("ok", _("OK"));
                d.present (this);
                return;
            }

            var dialog = new Adw.Dialog ();
            dialog.title = _("Library Properties");
            dialog.content_width = 400;
            dialog.content_height = 350;

            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.show_start_title_buttons = false;
            header.show_end_title_buttons = false;

            var close_btn = new Gtk.Button.with_label (_("Close"));
            header.pack_start (close_btn);

            var save_btn = new Gtk.Button.with_label (_("Save"));
            save_btn.add_css_class ("suggested-action");
            header.pack_end (save_btn);

            toolbar.add_top_bar (header);

            var clamp = new Adw.Clamp ();
            clamp.maximum_size = 380;
            clamp.margin_start = 16;
            clamp.margin_end = 16;
            clamp.margin_top = 16;
            clamp.margin_bottom = 16;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);

            var file_group = new Adw.PreferencesGroup ();
            file_group.title = _("File");

            var path_row = new Adw.ActionRow ();
            path_row.title = _("Path");
            path_row.subtitle = library.file_path;
            path_row.subtitle_selectable = true;
            file_group.add (path_row);

            var format_row = new Adw.ActionRow ();
            format_row.title = _("Format");
            format_row.subtitle = library.format == LibraryFormat.CSL_JSON ? "CSL JSON" : "BibTeX";
            file_group.add (format_row);

            var count_row = new Adw.ActionRow ();
            count_row.title = _("Documents");
            count_row.subtitle = library.documents.size.to_string ();
            file_group.add (count_row);

            box.append (file_group);

            var meta_group = new Adw.PreferencesGroup ();
            meta_group.title = _("Metadata");

            var author_entry = new Adw.EntryRow ();
            author_entry.title = _("Author");
            author_entry.text = library.library_author;
            meta_group.add (author_entry);

            var created_row = new Adw.ActionRow ();
            created_row.title = _("Created");
            created_row.subtitle = library.created.length > 0 ? library.created : _("Unknown");
            meta_group.add (created_row);

            var updated_row = new Adw.ActionRow ();
            updated_row.title = _("Last Updated");
            updated_row.subtitle = library.updated.length > 0 ? library.updated : _("Never");
            meta_group.add (updated_row);

            var version_row = new Adw.ActionRow ();
            version_row.title = _("Pince Version");
            version_row.subtitle = library.pince_version;
            meta_group.add (version_row);

            box.append (meta_group);

            clamp.child = box;
            toolbar.content = clamp;
            dialog.child = toolbar;

            close_btn.clicked.connect (() => {
                dialog.close ();
            });

            save_btn.clicked.connect (() => {
                library.library_author = author_entry.text;
                try {
                    library.save ();
                    updated_row.subtitle = library.updated;
                } catch (Error e) {
                    warning ("Save failed: %s", e.message);
                }
                dialog.close ();
            });

            dialog.present (this);
        }

        private void on_merge_library () {
            if (library.file_path.length == 0) {
                var dialog = new Adw.AlertDialog (
                    _("No Library Open"),
                    _("Open or create a library before merging.")
                );
                dialog.add_response ("ok", _("OK"));
                dialog.present (this);
                return;
            }

            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Select Library to Merge");

            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            var lib_filter = new Gtk.FileFilter ();
            lib_filter.name = _("Library Files");
            lib_filter.add_pattern ("*.json");
            lib_filter.add_pattern ("*.bib");
            filters.append (lib_filter);
            dialog.filters = filters;

            dialog.open.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    merge_library_from_file (file.get_path ());
                } catch (Error e) {}
            });
        }

        private void merge_library_from_file (string path) {
            var temp_lib = new Library ();
            try {
                temp_lib.load (path);
            } catch (Error e) {
                var err_dialog = new Adw.AlertDialog (
                    _("Error Loading Library"),
                    e.message
                );
                err_dialog.add_response ("ok", _("OK"));
                err_dialog.present (this);
                return;
            }

            int added = 0;
            int skipped = 0;

            foreach (var doc in temp_lib.documents) {
                var existing = library.find_duplicate (doc);
                if (existing != null) {
                    skipped++;
                } else {
                    library.add_document (doc);
                    added++;
                }
            }

            if (toast_overlay != null) {
                var toast = new Adw.Toast (
                    _("Merged %d documents, %d duplicates skipped").printf (added, skipped)
                );
                toast.timeout = 5;
                toast_overlay.add_toast (toast);
            } else {
                var summary = new Adw.AlertDialog (
                    _("Merge Complete"),
                    _("Merged %d documents, %d duplicates skipped.").printf (added, skipped)
                );
                summary.add_response ("ok", _("OK"));
                summary.present (this);
            }
        }

        private delegate void DocAction (Document doc);

        private void apply_to_selected_or_row (DocumentRow row, DocAction action) {
            var selected = get_selected_documents ();
            Gee.ArrayList<Document> targets;
            if (selected.size > 1) {
                targets = selected;
            } else if (row.document != null) {
                targets = new Gee.ArrayList<Document> ();
                targets.add (row.document);
            } else {
                return;
            }
            foreach (var doc in targets) {
                action (doc);
            }
            library.update_documents (targets);
            if (selected_document != null) {
                populate_detail ();
            }
        }

        private string get_library_dir () {
            return library.get_library_dir ();
        }

        private GLib.Settings? get_settings () {
            var schema_source = SettingsSchemaSource.get_default ();
            if (schema_source == null) return null;
            var schema = schema_source.lookup ("io.github.essicolo.Pince", true);
            if (schema == null) return null;
            return new GLib.Settings ("io.github.essicolo.Pince");
        }

        private bool should_auto_rename () {
            var settings = get_settings ();
            return settings != null && settings.get_boolean ("auto-rename-on-import");
        }

        private void on_open_file () {
            if (selected_document == null) return;
            var path = selected_document.get_resolved_path (get_library_dir ());
            Utils.open_file (path);
        }

        private void on_open_folder () {
            if (selected_document == null) return;
            var folder = selected_document.get_folder_path (get_library_dir ());
            Utils.open_folder (folder);
        }

        private void on_remove_document () {
            var selected = get_selected_documents ();
            if (selected.size == 0 && selected_document != null) {
                selected.add (selected_document);
            }
            if (selected.size == 0) return;

            var settings = get_settings ();
            bool confirm = settings != null ? settings.get_boolean ("confirm-remove") : true;

            if (confirm) {
                show_remove_confirmation (selected);
            } else {
                do_remove_documents (selected);
            }
        }

        private void show_remove_confirmation (Gee.ArrayList<Document> selected) {
            var dialog = new Adw.AlertDialog (
                ngettext (
                    _("Remove %d document?"),
                    _("Remove %d documents?"),
                    (ulong) selected.size
                ).printf (selected.size),
                _("This only removes the entry from the library. The file on disk is not deleted.")
            );

            var check = new Gtk.CheckButton.with_label (_("Don't tell me again"));
            dialog.set_extra_child (check);

            dialog.add_response ("cancel", _("Cancel"));
            dialog.add_response ("remove", _("Remove"));
            dialog.set_response_appearance ("remove", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.default_response = "cancel";

            dialog.response.connect ((response) => {
                if (response == "remove") {
                    if (check.active) {
                        var settings = get_settings ();
                        if (settings != null) {
                            settings.set_boolean ("confirm-remove", false);
                        }
                    }
                    do_remove_documents (selected);
                }
            });

            dialog.present (this);
        }

        private void do_remove_documents (Gee.ArrayList<Document> selected) {
            selected_document = null;
            hide_detail ();

            foreach (var doc in selected) {
                library.remove_document (doc);
                undo_stack.add (doc);
            }
            while (undo_stack.size > 10) {
                undo_stack.remove_at (0);
            }

            var toast = new Adw.Toast (
                ngettext (
                    _("Removed %d document"),
                    _("Removed %d documents"),
                    (ulong) selected.size
                ).printf (selected.size)
            );
            toast.button_label = _("Undo");
            toast.action_name = "win.undo-remove";
            toast_overlay.add_toast (toast);
        }

        private void push_undo_and_toast (Document doc) {
            undo_stack.add (doc);
            // Keep only last 5
            while (undo_stack.size > 5) {
                undo_stack.remove_at (0);
            }

            var toast = new Adw.Toast (_("Document removed"));
            toast.button_label = _("Undo");
            toast.action_name = "win.undo-remove";
            toast.timeout = 5;
            toast_overlay.add_toast (toast);
        }

        // --- Move / Rename file features ---

        private void on_move_files () {
            var selected = get_selected_documents ();
            if (selected.size == 0 && selected_document != null) {
                selected.add (selected_document);
            }
            if (selected.size == 0) return;

            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Move %d file(s) to...").printf (selected.size);

            dialog.select_folder.begin (this, null, (obj, res) => {
                try {
                    var folder = dialog.select_folder.end (res);
                    var dest_dir = folder.get_path ();
                    move_documents_sync (selected, dest_dir);
                } catch (Error e) {
                    // User cancelled
                }
            });
        }

        private void move_documents_sync (Gee.ArrayList<Document> docs, string dest_dir) {
            int moved = 0;
            int failed = 0;
            var moved_docs = new Gee.ArrayList<Document> ();
            var lib_dir = get_library_dir ();

            foreach (var doc in docs) {
                var src_path = doc.get_resolved_path (lib_dir);
                var src_file = File.new_for_path (src_path);

                if (!src_file.query_exists ()) {
                    failed++;
                    continue;
                }

                var filename = Path.get_basename (src_path);
                var dest_path = Path.build_filename (dest_dir, filename);
                var dest_file = File.new_for_path (dest_path);

                // Skip if source and destination are the same
                if (src_path == dest_path) continue;

                try {
                    src_file.move (dest_file, FileCopyFlags.NONE, null, null);
                    doc.path = library.make_relative_path (dest_path);
                    moved_docs.add (doc);
                    moved++;
                } catch (Error e) {
                    warning ("Move failed for %s: %s", filename, e.message);
                    failed++;
                }
            }

            // Single batched update so the changed signal and save fire once
            // for the whole bulk move instead of N times.
            if (moved_docs.size > 0) {
                library.update_documents (moved_docs);
            }

            string msg;
            if (moved > 0) {
                msg = _("Moved %d file(s)").printf (moved);
                if (failed > 0) msg += _(", %d failed").printf (failed);
            } else if (failed > 0) {
                msg = _("Move failed for %d file(s)").printf (failed);
            } else {
                msg = _("No files to move");
            }
            var toast = new Adw.Toast (msg);
            toast.timeout = 3;
            toast_overlay.add_toast (toast);

            if (selected_document != null) populate_detail ();
        }

        private void on_rename_files () {
            var selected = get_selected_documents ();
            if (selected.size == 0 && selected_document != null) {
                selected.add (selected_document);
            }
            if (selected.size == 0) return;

            // Check if any document has enough metadata to rename
            int missing_metadata = 0;
            foreach (var doc in selected) {
                if (doc.authors.size == 0 && doc.year.length == 0) {
                    missing_metadata++;
                }
            }

            if (missing_metadata == selected.size) {
                var toast = new Adw.Toast (_("Cannot rename: fetch metadata first (need at least author or year)"));
                toast.timeout = 5;
                toast_overlay.add_toast (toast);
                return;
            }

            rename_documents_sync (selected);
        }

        private void on_rename_all () {
            if (library.file_path.length == 0 || library.documents.size == 0) return;

            var docs = new Gee.ArrayList<Document> ();
            foreach (var doc in library.documents) {
                docs.add (doc);
            }
            rename_documents_sync (docs);
        }

        private void rename_documents_sync (Gee.ArrayList<Document> docs) {
            int renamed = 0;
            int skipped = 0;
            int failed = 0;
            var renamed_docs = new Gee.ArrayList<Document> ();
            var lib_dir = get_library_dir ();

            // Track used names for disambiguation within this batch
            var used_names = new Gee.HashMap<string, int> ();

            foreach (var doc in docs) {
                var base_name = generate_author_year_name (doc);
                if (base_name.length == 0) {
                    skipped++;
                    continue;
                }

                var src_path = doc.get_resolved_path (lib_dir);
                var src_file = File.new_for_path (src_path);

                if (!src_file.query_exists ()) {
                    failed++;
                    continue;
                }

                // Get extension from original filename
                var original_name = Path.get_basename (src_path);
                var ext = "";
                var dot = original_name.last_index_of (".");
                if (dot >= 0) {
                    ext = original_name.substring (dot);
                }

                var dir = Path.get_dirname (src_path);

                // Disambiguation: track how many times this base name is used
                int count = used_names.has_key (base_name) ? used_names[base_name] : 0;
                count++;
                used_names[base_name] = count;

                // Build final name with suffix letter (a, b, c, ...)
                var suffix = ((char) ('a' + count - 1)).to_string ();
                var final_name = base_name + suffix + ext;
                var dest_path = Path.build_filename (dir, final_name);

                // If already named correctly, skip
                if (dest_path == src_path) continue;

                // Avoid overwriting existing files
                var dest_file = File.new_for_path (dest_path);
                while (dest_file.query_exists () && dest_path != src_path) {
                    count++;
                    used_names[base_name] = count;
                    suffix = ((char) ('a' + count - 1)).to_string ();
                    final_name = base_name + suffix + ext;
                    dest_path = Path.build_filename (dir, final_name);
                    dest_file = File.new_for_path (dest_path);
                }

                try {
                    src_file.move (dest_file, FileCopyFlags.NONE, null, null);
                    doc.path = library.make_relative_path (dest_path);
                    renamed_docs.add (doc);
                    renamed++;
                } catch (Error e) {
                    warning ("Rename failed for %s: %s", original_name, e.message);
                    failed++;
                }
            }

            // Single batched update — see move_documents_sync.
            if (renamed_docs.size > 0) {
                library.update_documents (renamed_docs);
            }

            string msg;
            if (renamed > 0) {
                msg = _("Renamed %d file(s)").printf (renamed);
                if (skipped > 0) msg += _(", %d skipped (no metadata)").printf (skipped);
                if (failed > 0) msg += _(", %d failed").printf (failed);
            } else if (skipped > 0) {
                msg = _("Skipped %d file(s): fetch metadata first").printf (skipped);
            } else if (failed > 0) {
                msg = _("Rename failed for %d file(s)").printf (failed);
            } else {
                msg = _("Files already have correct names");
            }
            var toast = new Adw.Toast (msg);
            toast.timeout = 5;
            toast_overlay.add_toast (toast);

            if (selected_document != null) populate_detail ();
            refresh_document_list ();
        }

        /**
         * Generate authoryear base name from document metadata.
         * E.g., "he2016" from author "He, Kaiming" and year "2016".
         */
        private string generate_author_year_name (Document doc) {
            var sb = new StringBuilder ();

            if (doc.authors.size > 0) {
                var author = doc.authors[0];
                string family;
                if (author.contains (",")) {
                    family = author.split (",", 2)[0].strip ();
                } else {
                    var parts = author.strip ().split (" ");
                    family = parts[parts.length - 1];
                }
                // Lowercase, keep only letters and hyphens
                var clean = new StringBuilder ();
                unichar c;
                int idx = 0;
                var lower = family.down ();
                while (lower.get_next_char (ref idx, out c)) {
                    if (c.isalpha () || c == '-') clean.append_unichar (c);
                }
                sb.append (clean.str);
            }

            if (doc.year.length > 0 && doc.year != "0") {
                sb.append (doc.year);
            }

            return sb.str;
        }

        private void refresh_view () {
            refresh_tag_list ();
            refresh_document_list ();
            update_status ();
        }

        private void refresh_tag_list () {
            Gtk.Widget? child = tag_list.get_first_child ();
            while (child != null) {
                var next = child.get_next_sibling ();
                tag_list.remove (child);
                child = next;
            }

            var tags = library.get_all_tags ();
            foreach (var tag in tags) {
                var count = 0;
                foreach (var doc in library.documents) {
                    if (doc.has_tag (tag)) count++;
                }
                var row = new TagRow (tag, count);
                tag_list.append (row);
            }
        }

        private void refresh_document_list () {
            var query = search_entry.text.strip ();

            // Reading status filter (mutually exclusive)
            ReadingStatus? reading_filter = null;
            if (filter_unread.active) reading_filter = ReadingStatus.UNREAD;
            else if (filter_read.active) reading_filter = ReadingStatus.READ;

            bool? starred_filter = null;
            if (filter_starred.active) starred_filter = true;

            var filtered = library.filter (
                query.length > 0 ? query : null,
                active_tag_filter,
                starred_filter,
                reading_filter
            );

            var sort_field = (SortField) sort_dropdown.selected;
            var sorted = library.sort_by (filtered, sort_field);

            list_store.remove_all ();
            foreach (var doc in sorted) {
                list_store.append (doc);
            }
        }

        private void update_status () {
            if (library.file_path.length == 0) {
                status_label.label = _("No library open");
                title_widget.title = "Pince";
                title_widget.subtitle = "";
            } else {
                var basename = Path.get_basename (library.file_path);
                status_label.label = _("%s — %d documents").printf (basename, library.documents.size);
                title_widget.title = basename;
                title_widget.subtitle = library.file_path;
            }
        }

        public void open_library_file (File file) {
            try {
                library.load (file.get_path ());
                save_last_library_path (file.get_path ());
            } catch (Error e) {
                var dialog = new Adw.AlertDialog (
                    _("Error Opening Library"),
                    e.message
                );
                dialog.add_response ("ok", _("OK"));
                dialog.present (this);
            }
        }

        private void save_last_library_path (string path) {
            RecentLibraries.add (path);
            var settings = get_settings ();
            if (settings != null) {
                settings.set_string ("last-library-path", path);
            }
        }

        public void show_open_library_dialog () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Open Library");

            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            var lib_filter = new Gtk.FileFilter ();
            lib_filter.name = _("Library Files");
            lib_filter.add_pattern ("*.json");
            lib_filter.add_pattern ("*.bib");
            filters.append (lib_filter);
            dialog.filters = filters;

            dialog.open.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    open_library_file (file);
                } catch (Error e) {}
            });
        }

        public void show_new_library_dialog () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("New Library");

            var filters = new GLib.ListStore (typeof (Gtk.FileFilter));
            var json_filter = new Gtk.FileFilter ();
            json_filter.name = _("CSL JSON (.json)");
            json_filter.add_pattern ("*.json");
            filters.append (json_filter);
            var bib_filter = new Gtk.FileFilter ();
            bib_filter.name = _("BibTeX (.bib)");
            bib_filter.add_pattern ("*.bib");
            filters.append (bib_filter);
            dialog.filters = filters;
            dialog.initial_name = "library.json";

            dialog.save.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.save.end (res);
                    setup_new_library (file.get_path ());
                } catch (Error e) {}
            });
        }

        // --- Watch Folder feature ---

        private void on_watch_folder () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = _("Select Folder to Watch");

            dialog.select_folder.begin (this, null, (obj, res) => {
                try {
                    var file = dialog.select_folder.end (res);
                    var folder_path = file.get_path ();
                    start_watching_folder (folder_path);
                    var settings = get_settings ();
                    if (settings != null) {
                        settings.set_string ("watch-folder-path", folder_path);
                    }
                    var toast = new Adw.Toast (_("Watching folder: %s").printf (Path.get_basename (folder_path)));
                    toast.timeout = 3;
                    toast_overlay.add_toast (toast);
                } catch (Error e) {
                    // User cancelled the dialog
                }
            });
        }

        private void on_stop_watching () {
            if (folder_monitor != null) {
                folder_monitor.cancel ();
                folder_monitor = null;
                var settings = get_settings ();
                if (settings != null) {
                    settings.set_string ("watch-folder-path", "");
                }
                var toast = new Adw.Toast (_("Stopped watching folder"));
                toast.timeout = 3;
                toast_overlay.add_toast (toast);
            }
        }

        private void restore_watched_folder () {
            var settings = get_settings ();
            if (settings == null) return;
            var path = settings.get_string ("watch-folder-path");
            if (path.length > 0 && FileUtils.test (path, FileTest.IS_DIR)) {
                start_watching_folder (path);
            }
        }

        private void start_watching_folder (string folder_path) {
            // Stop any existing monitor
            if (folder_monitor != null) {
                folder_monitor.cancel ();
                folder_monitor = null;
            }

            try {
                var folder = File.new_for_path (folder_path);
                folder_monitor = folder.monitor_directory (FileMonitorFlags.NONE, null);
                folder_monitor.changed.connect (on_folder_changed);
            } catch (Error e) {
                warning ("Failed to watch folder: %s", e.message);
            }
        }

        private bool is_supported_document (string filename) {
            var lower = filename.down ();
            return lower.has_suffix (".pdf") ||
                   lower.has_suffix (".docx") ||
                   lower.has_suffix (".odt") ||
                   lower.has_suffix (".txt") ||
                   lower.has_suffix (".epub") ||
                   lower.has_suffix (".md");
        }

        private void on_folder_changed (File file, File? other_file, FileMonitorEvent event_type) {
            if (event_type != FileMonitorEvent.CREATED &&
                event_type != FileMonitorEvent.MOVED_IN) return;

            var filename = file.get_basename ();
            if (!is_supported_document (filename)) return;

            // Skip files already in the library (e.g. after rename via Pince)
            var file_path = file.get_path ();
            var lib_dir = get_library_dir ();
            foreach (var doc in library.documents) {
                if (doc.get_resolved_path (lib_dir) == file_path) return;
            }

            var toast = new Adw.Toast (_("New file detected: %s").printf (filename));
            toast.button_label = _("Import");
            toast.timeout = 10;
            toast.button_clicked.connect (() => {
                import_watched_file.begin (file_path);
            });
            toast_overlay.add_toast (toast);
        }

        private async void import_watched_file (string file_path) {
            if (library.file_path.length == 0) {
                var toast = new Adw.Toast (_("Open a library before importing"));
                toast.timeout = 3;
                toast_overlay.add_toast (toast);
                return;
            }

            var doc = yield MetadataExtractor.extract (file_path);
            library.add_document (doc);
            var toast = new Adw.Toast (_("Imported: %s").printf (
                doc.title.length > 0 ? doc.title : Path.get_basename (file_path)
            ));
            toast.timeout = 3;
            toast_overlay.add_toast (toast);
        }

        // --- Linked Notes feature ---

        private void on_open_notes () {
            if (selected_document == null) return;
            if (library.file_path.length == 0) return;

            var lib_dir = get_library_dir ();
            var notes_dir = Path.build_filename (lib_dir, ".pince-notes");
            var notes_path = selected_document.get_notes_path (lib_dir);

            // Create .pince-notes directory if needed
            var dir = File.new_for_path (notes_dir);
            if (!dir.query_exists ()) {
                try {
                    dir.make_directory_with_parents ();
                } catch (Error e) {
                    warning ("Failed to create notes directory: %s", e.message);
                    return;
                }
            }

            // Create the .md file with a header if it doesn't exist
            var notes_file = File.new_for_path (notes_path);
            if (!notes_file.query_exists ()) {
                try {
                    var header = "# %s\n\n".printf (selected_document.title);
                    FileUtils.set_contents (notes_path, header);
                } catch (Error e) {
                    warning ("Failed to create notes file: %s", e.message);
                    return;
                }
            }

            // Open with the user's preferred editor via FileLauncher
            var launcher = new Gtk.FileLauncher (notes_file);
            launcher.launch.begin (this, null, (obj, res) => {
                try {
                    launcher.launch.end (res);
                } catch (Error e) {
                    warning ("Failed to open notes file: %s", e.message);
                }
            });
        }
    }
}
