namespace Pince {

    public enum LibraryFormat {
        CSL_JSON,
        BIBTEX;

        public string to_extension () {
            switch (this) {
                case CSL_JSON: return ".json";
                case BIBTEX: return ".bib";
                default: return ".json";
            }
        }

        public static LibraryFormat from_filename (string filename) {
            if (filename.has_suffix (".bib")) return BIBTEX;
            return CSL_JSON;
        }
    }

    public class Library : Object {
        public string file_path { get; set; default = ""; }
        public LibraryFormat format { get; set; default = LibraryFormat.CSL_JSON; }
        public bool modified { get; set; default = false; }

        // Library metadata
        public string library_author { get; set; default = ""; }
        public string created { get; set; default = ""; }
        public string updated { get; set; default = ""; }
        public string pince_version { get; set; default = "0.1.0"; }

        private Gee.ArrayList<Document> _documents;
        public Gee.ArrayList<Document> documents {
            get { return _documents; }
        }

        private uint save_timeout_id = 0;

        public signal void changed ();
        public signal void document_added (Document doc);
        public signal void document_removed (Document doc);

        public Library () {
            _documents = new Gee.ArrayList<Document> ();
            created = new DateTime.now_utc ().format_iso8601 ();
            library_author = Environment.get_real_name ();
            if (library_author == "Unknown") {
                library_author = Environment.get_user_name ();
            }
        }

        public void add_document (Document doc) {
            // Store path relative to library file location
            if (file_path.length > 0 && Path.is_absolute (doc.path)) {
                doc.path = make_relative_path (doc.path);
            }
            _documents.add (doc);
            modified = true;
            document_added (doc);
            changed ();
            schedule_save ();
        }

        public void remove_document (Document doc) {
            _documents.remove (doc);
            modified = true;
            document_removed (doc);
            changed ();
            schedule_save ();
        }

        public void update_document (Document doc) {
            modified = true;
            changed ();
            schedule_save ();
        }

        // Batch variant: callers mutate every document first, then call this
        // once so the expensive changed signal and save fire a single time
        // instead of N times. Bulk actions on large selections would otherwise
        // rebuild the full list/tag views per document (O(N^2)) and freeze
        // the UI long enough to trigger the compositor's force-quit dialog.
        public void update_documents (Gee.Collection<Document> docs) {
            if (docs.size == 0) return;
            modified = true;
            changed ();
            schedule_save ();
        }

        public Gee.Set<string> get_all_tags () {
            var tags = new Gee.TreeSet<string> ();
            foreach (var doc in _documents) {
                foreach (var tag in doc.tags) {
                    tags.add (tag);
                }
            }
            return tags;
        }

        public Gee.ArrayList<Document> sort_by (Gee.ArrayList<Document> docs, SortField field) {
            var sorted = new Gee.ArrayList<Document> ();
            sorted.add_all (docs);
            sorted.sort ((a, b) => {
                switch (field) {
                    case SortField.TITLE:
                        return a.title.collate (b.title);
                    case SortField.YEAR:
                        // Descending: newest first
                        return b.year.collate (a.year);
                    case SortField.AUTHOR:
                        var a_author = a.authors.size > 0 ? a.authors[0] : "";
                        var b_author = b.authors.size > 0 ? b.authors[0] : "";
                        return a_author.collate (b_author);
                    case SortField.DATE_ADDED:
                        // Descending: most recent first
                        return b.date_added.collate (a.date_added);
                    default:
                        return 0;
                }
            });
            return sorted;
        }

        public Gee.ArrayList<Document> filter (string? search_query, string? tag_filter,
                                               bool? starred_filter = null,
                                               ReadingStatus? reading_filter = null) {
            var results = new Gee.ArrayList<Document> ();
            foreach (var doc in _documents) {
                bool matches = true;
                if (tag_filter != null && tag_filter.length > 0) {
                    if (!doc.has_tag (tag_filter)) {
                        matches = false;
                    }
                }
                if (matches && search_query != null && search_query.length > 0) {
                    if (!doc.matches_search (search_query)) {
                        matches = false;
                    }
                }
                if (matches && starred_filter != null && starred_filter == true) {
                    if (!doc.starred) {
                        matches = false;
                    }
                }
                if (matches && reading_filter != null) {
                    if (doc.reading_status != reading_filter) {
                        matches = false;
                    }
                }
                if (matches) {
                    results.add (doc);
                }
            }
            return results;
        }

        /**
         * Check if a document is a duplicate of something already in the library.
         * Returns the existing document if found, null otherwise.
         * Checks: exact DOI, exact path, fuzzy title match.
         */
        public Document? find_duplicate (Document candidate) {
            foreach (var doc in _documents) {
                // Exact DOI match
                if (candidate.doi.length > 0 && doc.doi.length > 0 &&
                    candidate.doi.down () == doc.doi.down ()) {
                    return doc;
                }
                // Exact path match
                if (candidate.path.length > 0 && doc.path.length > 0 &&
                    candidate.path == doc.path) {
                    return doc;
                }
                // Fuzzy title match (normalized)
                if (candidate.title.length > 10 && doc.title.length > 10) {
                    if (titles_match (candidate.title, doc.title)) {
                        return doc;
                    }
                }
            }
            return null;
        }

        /**
         * Find all groups of duplicate documents in the library.
         * Returns a list of groups, where each group contains 2+ documents
         * that are duplicates of each other.
         */
        public Gee.ArrayList<Gee.ArrayList<Document>> find_all_duplicates () {
            var groups = new Gee.ArrayList<Gee.ArrayList<Document>> ();
            var seen = new Gee.HashSet<int> ();

            for (int i = 0; i < _documents.size; i++) {
                if (seen.contains (i)) continue;

                var group = new Gee.ArrayList<Document> ();
                group.add (_documents[i]);

                for (int j = i + 1; j < _documents.size; j++) {
                    if (seen.contains (j)) continue;

                    bool is_dup = false;
                    var a = _documents[i];
                    var b = _documents[j];

                    // DOI match
                    if (a.doi.length > 0 && b.doi.length > 0 &&
                        a.doi.down () == b.doi.down ()) {
                        is_dup = true;
                    }
                    // Path match
                    if (a.path.length > 0 && b.path.length > 0 &&
                        a.path == b.path) {
                        is_dup = true;
                    }
                    // Title match
                    if (a.title.length > 10 && b.title.length > 10 &&
                        titles_match (a.title, b.title)) {
                        is_dup = true;
                    }

                    if (is_dup) {
                        group.add (b);
                        seen.add (j);
                    }
                }

                if (group.size > 1) {
                    seen.add (i);
                    groups.add (group);
                }
            }

            return groups;
        }

        private static bool titles_match (string a, string b) {
            var na = normalize_title (a);
            var nb = normalize_title (b);

            // Only exact normalized match counts
            return na == nb;
        }

        private static string normalize_title (string title) {
            var lower = title.down ().strip ();
            // Remove common punctuation and extra whitespace
            var result = new StringBuilder ();
            unichar c;
            int i = 0;
            bool last_was_space = false;
            while (lower.get_next_char (ref i, out c)) {
                if (c.isalnum ()) {
                    result.append_unichar (c);
                    last_was_space = false;
                } else if (!last_was_space && result.len > 0) {
                    result.append_c (' ');
                    last_was_space = true;
                }
            }
            return result.str.strip ();
        }

        public void load (string path) throws Error {
            this.file_path = path;
            this.format = LibraryFormat.from_filename (path);
            _documents.clear ();

            // Save constructor defaults — will be overwritten if file has metadata
            var default_created = created;
            var default_author = library_author;

            var file = File.new_for_path (path);
            if (!file.query_exists ()) {
                return;
            }

            switch (format) {
                case LibraryFormat.CSL_JSON:
                    CslJsonIO.load (this, path);
                    break;
                case LibraryFormat.BIBTEX:
                    BibtexIO.load (this, path);
                    break;
            }

            modified = false;
            changed ();

            // If loaded from old format without metadata, save to migrate
            if (updated.length == 0) {
                try {
                    save ();
                } catch (Error e) {
                    warning ("Metadata migration save failed: %s", e.message);
                }
            }
        }

        public void save () throws Error {
            if (file_path.length == 0) return;

            updated = new DateTime.now_utc ().format_iso8601 ();

            switch (format) {
                case LibraryFormat.CSL_JSON:
                    CslJsonIO.save (this, file_path);
                    break;
                case LibraryFormat.BIBTEX:
                    BibtexIO.save (this, file_path);
                    break;
            }

            modified = false;
        }

        public void save_as (string path, LibraryFormat fmt) throws Error {
            this.file_path = path;
            this.format = fmt;
            save ();
        }

        public string get_library_dir () {
            if (file_path.length == 0) return "";
            return Path.get_dirname (file_path);
        }

        /**
         * Convert an absolute file path to a path relative to the library file.
         * If the file is not under the same tree, returns the absolute path unchanged.
         */
        public string make_relative_path (string abs_path) {
            var lib_dir = get_library_dir ();
            if (lib_dir.length == 0) return abs_path;

            var lib_file = File.new_for_path (lib_dir);
            var doc_file = File.new_for_path (abs_path);

            var relative = lib_file.get_relative_path (doc_file);
            if (relative != null) {
                return relative;
            }

            // Not a descendant — return absolute
            return abs_path;
        }

        private void schedule_save () {
            if (save_timeout_id != 0) {
                Source.remove (save_timeout_id);
            }
            save_timeout_id = Timeout.add (2000, () => {
                save_timeout_id = 0;
                try {
                    save ();
                } catch (Error e) {
                    warning ("Auto-save failed: %s", e.message);
                }
                return false;
            });
        }
    }
}
