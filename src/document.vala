namespace Pince {

    public enum ReadingStatus {
        UNREAD,
        READ;

        public string to_string_value () {
            switch (this) {
                case READ: return "read";
                default: return "unread";
            }
        }

        public static ReadingStatus from_string (string val) {
            switch (val.down ()) {
                case "read": return READ;
                case "reading": return READ;  // migrate old "reading" to "read"
                default: return UNREAD;
            }
        }
    }

    public enum SortField {
        TITLE,
        YEAR,
        AUTHOR,
        DATE_ADDED;
    }

    public class Document : Object {
        public string id { get; set; default = ""; }
        public string path { get; set; default = ""; }
        public string title { get; set; default = ""; }
        public string year { get; set; default = ""; }
        public string doi { get; set; default = ""; }
        public string abstract_text { get; set; default = ""; }
        public string note { get; set; default = ""; }
        public string filetype { get; set; default = ""; }
        public string entry_type { get; set; default = "article"; }
        public string journal { get; set; default = ""; }
        public string volume { get; set; default = ""; }
        public string pages { get; set; default = ""; }
        public string publisher { get; set; default = ""; }
        public string url { get; set; default = ""; }
        public string date_added { get; set; default = ""; }
        public bool starred { get; set; default = false; }
        public ReadingStatus reading_status { get; set; default = ReadingStatus.UNREAD; }

        private Gee.ArrayList<string> _authors;
        public Gee.ArrayList<string> authors {
            get { return _authors; }
            set { _authors = value; }
        }

        private Gee.ArrayList<string> _tags;
        public Gee.ArrayList<string> tags {
            get { return _tags; }
            set { _tags = value; }
        }

        public Document () {
            _authors = new Gee.ArrayList<string> ();
            _tags = new Gee.ArrayList<string> ();
        }

        public Document.from_file (string file_path) {
            _authors = new Gee.ArrayList<string> ();
            _tags = new Gee.ArrayList<string> ();
            this.path = file_path;
            this.filetype = detect_filetype (file_path);
            this.date_added = new DateTime.now_utc ().format_iso8601 ();
            this.id = generate_id ();
        }

        /**
         * Each author is stored as "Family, Given" in the list.
         * Display joins them with " and " (standard academic separator).
         */
        public string get_authors_display () {
            if (_authors.size == 0) return "";
            var parts = new string[_authors.size];
            for (int i = 0; i < _authors.size; i++) {
                parts[i] = _authors[i];
            }
            return string.joinv (" and ", parts);
        }

        public string get_tags_display () {
            if (_tags.size == 0) return "";
            var parts = new string[_tags.size];
            for (int i = 0; i < _tags.size; i++) {
                parts[i] = _tags[i];
            }
            return string.joinv (", ", parts);
        }

        /**
         * Parse an author display string back into the authors list.
         * Accepts " and " as separator between authors.
         * Each author should be "Family, Given" or just a name.
         */
        public void set_authors_from_string (string text) {
            _authors.clear ();
            // Split on " and " first (academic standard)
            foreach (var author in text.split (" and ")) {
                var trimmed = author.strip ();
                if (trimmed.length > 0) {
                    _authors.add (trimmed);
                }
            }
        }

        public void set_tags_from_string (string text) {
            _tags.clear ();
            foreach (var tag in text.split (",")) {
                var trimmed = tag.strip ();
                if (trimmed.length > 0) {
                    _tags.add (trimmed);
                }
            }
        }

        public bool matches_search (string query) {
            var lower_query = query.down ();
            if (title.down ().contains (lower_query)) return true;
            foreach (var author in _authors) {
                if (author.down ().contains (lower_query)) return true;
            }
            foreach (var tag in _tags) {
                if (tag.down ().contains (lower_query)) return true;
            }
            if (doi.down ().contains (lower_query)) return true;
            if (year.contains (lower_query)) return true;
            return false;
        }

        public bool has_tag (string tag) {
            return _tags.contains (tag);
        }

        public string get_resolved_path (string library_dir) {
            if (Path.is_absolute (path)) return path;
            return Path.build_filename (library_dir, path);
        }

        public string get_folder_path (string library_dir) {
            var resolved = get_resolved_path (library_dir);
            return Path.get_dirname (resolved);
        }

        private string detect_filetype (string file_path) {
            var lower = file_path.down ();
            if (lower.has_suffix (".pdf")) return "pdf";
            if (lower.has_suffix (".docx")) return "docx";
            if (lower.has_suffix (".odt")) return "odt";
            if (lower.has_suffix (".txt")) return "txt";
            if (lower.has_suffix (".epub")) return "epub";
            if (lower.has_suffix (".djvu")) return "djvu";
            if (lower.has_suffix (".md")) return "md";
            if (lower.has_suffix (".tex")) return "tex";
            if (lower.has_suffix (".html") || lower.has_suffix (".htm")) return "html";
            return "unknown";
        }

        private string generate_id () {
            var checksum = new GLib.Checksum (GLib.ChecksumType.SHA256);
            checksum.update (path.data, path.data.length);
            var now = new DateTime.now_utc ().to_unix ().to_string ();
            checksum.update (now.data, now.data.length);
            return checksum.get_string ().substring (0, 12);
        }

        /**
         * Get the path to the linked markdown notes file for this document.
         * Returns {library_dir}/.pince-notes/{doc.id}.md
         */
        public string get_notes_path (string library_dir) {
            return Path.build_filename (library_dir, ".pince-notes", "%s.md".printf (id));
        }

        /**
         * Generate a cite key in author2024keyword format.
         * Uses the first author's family name + year + first significant title word.
         */
        public void generate_cite_key () {
            var sb = new StringBuilder ();

            // First author family name
            if (_authors.size > 0) {
                var author = _authors[0];
                string family;
                if (author.contains (",")) {
                    family = author.split (",", 2)[0].strip ();
                } else {
                    // Take last word as family name
                    var parts = author.strip ().split (" ");
                    family = parts[parts.length - 1];
                }
                sb.append (family.down ());
            }

            // Year
            if (year.length > 0) {
                sb.append (year);
            }

            // First significant word from title
            if (title.length > 0) {
                var stop_words = new Gee.HashSet<string> ();
                string[] stops = { "a", "an", "the", "of", "and", "in", "on", "for",
                                   "to", "with", "is", "are", "was", "were", "by",
                                   "from", "at", "as", "or", "its", "it", "all" };
                foreach (var s in stops) {
                    stop_words.add (s);
                }
                foreach (var word_raw in title.split (" ")) {
                    var word = word_raw.down ().strip ();
                    // Remove non-alphanumeric chars
                    var clean = new StringBuilder ();
                    unichar c;
                    int idx = 0;
                    while (word.get_next_char (ref idx, out c)) {
                        if (c.isalnum ()) clean.append_unichar (c);
                    }
                    var w = clean.str;
                    if (w.length > 0 && !stop_words.contains (w)) {
                        sb.append (w);
                        break;
                    }
                }
            }

            if (sb.len > 0) {
                this.id = sb.str;
            }
        }
    }
}
