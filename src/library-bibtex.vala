namespace Pince {
    public class BibtexIO {
        public static void load (Library library, string path) throws Error {
            string contents;
            FileUtils.get_contents (path, out contents);

            // Parse metadata from @comment{pince-metadata, ...}
            parse_metadata (contents, library);

            var entries = parse_bibtex (contents);
            foreach (var entry in entries) {
                library.documents.add (entry);
            }
        }

        public static void save (Library library, string path) throws Error {
            var sb = new StringBuilder ();

            // Write library metadata as @comment
            sb.append ("@comment{pince-metadata,\n");
            sb.append_printf ("  version = {%s},\n", library.pince_version);
            sb.append_printf ("  author = {%s},\n", library.library_author);
            sb.append_printf ("  created = {%s},\n", library.created);
            sb.append_printf ("  updated = {%s},\n", library.updated);
            sb.append ("}\n\n");

            foreach (var doc in library.documents) {
                write_entry (sb, doc);
                sb.append ("\n");
            }
            FileUtils.set_contents (path, sb.str);
        }

        private static void parse_metadata (string contents, Library library) {
            // Look for @comment{pince-metadata, ...}
            int idx = contents.index_of ("@comment{pince-metadata");
            if (idx < 0) return;

            int brace_start = contents.index_of ("{", idx);
            if (brace_start < 0) return;

            int brace_end = find_matching_brace (contents, brace_start);
            if (brace_end < 0) return;

            string body = contents.substring (brace_start + 1, brace_end - brace_start - 1);

            // Skip "pince-metadata," prefix
            int comma = body.index_of (",");
            if (comma < 0) return;
            body = body.substring (comma + 1);

            var fields = parse_fields (body);
            if (fields.has_key ("version")) {
                library.pince_version = clean_bibtex_value (fields["version"]);
            }
            if (fields.has_key ("author")) {
                library.library_author = clean_bibtex_value (fields["author"]);
            }
            if (fields.has_key ("created")) {
                library.created = clean_bibtex_value (fields["created"]);
            }
            if (fields.has_key ("updated")) {
                library.updated = clean_bibtex_value (fields["updated"]);
            }
        }

        private static Gee.ArrayList<Document> parse_bibtex (string contents) {
            var documents = new Gee.ArrayList<Document> ();
            int pos = 0;
            int len = contents.length;

            while (pos < len) {
                // Find next entry starting with @
                int at_pos = contents.index_of ("@", pos);
                if (at_pos < 0) break;

                // Read entry type
                int brace_start = contents.index_of ("{", at_pos);
                if (brace_start < 0) break;

                string entry_type = contents.substring (at_pos + 1, brace_start - at_pos - 1).strip ().down ();

                // Skip comments and preambles
                if (entry_type == "comment" || entry_type == "preamble" || entry_type == "string") {
                    pos = skip_braced_block (contents, brace_start);
                    continue;
                }

                // Find matching closing brace
                int brace_end = find_matching_brace (contents, brace_start);
                if (brace_end < 0) break;

                string entry_body = contents.substring (brace_start + 1, brace_end - brace_start - 1);

                var doc = parse_entry (entry_type, entry_body);
                if (doc != null) {
                    documents.add (doc);
                }

                pos = brace_end + 1;
            }

            return documents;
        }

        private static Document? parse_entry (string entry_type, string body) {
            var doc = new Document ();
            doc.entry_type = entry_type;

            // First element before the first comma is the citation key
            int first_comma = body.index_of (",");
            if (first_comma < 0) return null;

            doc.id = body.substring (0, first_comma).strip ();

            // Parse fields
            var fields = parse_fields (body.substring (first_comma + 1));

            if (fields.has_key ("title")) {
                doc.title = clean_bibtex_value (fields["title"]);
            }
            if (fields.has_key ("author")) {
                var authors_str = clean_bibtex_value (fields["author"]);
                // BibTeX uses " and " as separator
                foreach (var author in authors_str.split (" and ")) {
                    var trimmed = author.strip ();
                    if (trimmed.length > 0) {
                        doc.authors.add (trimmed);
                    }
                }
            }
            if (fields.has_key ("year")) {
                doc.year = clean_bibtex_value (fields["year"]);
            }
            if (fields.has_key ("doi")) {
                doc.doi = clean_bibtex_value (fields["doi"]);
            }
            if (fields.has_key ("isbn")) {
                doc.isbn = clean_bibtex_value (fields["isbn"]);
            }
            if (fields.has_key ("abstract")) {
                doc.abstract_text = clean_bibtex_value (fields["abstract"]);
            }
            if (fields.has_key ("note")) {
                doc.note = clean_bibtex_value (fields["note"]);
            }
            if (fields.has_key ("journal")) {
                doc.journal = clean_bibtex_value (fields["journal"]);
            }
            if (fields.has_key ("volume")) {
                doc.volume = clean_bibtex_value (fields["volume"]);
            }
            if (fields.has_key ("pages")) {
                doc.pages = clean_bibtex_value (fields["pages"]);
            }
            if (fields.has_key ("publisher")) {
                doc.publisher = clean_bibtex_value (fields["publisher"]);
            }
            if (fields.has_key ("url")) {
                doc.url = clean_bibtex_value (fields["url"]);
            }
            if (fields.has_key ("keywords")) {
                var kw = clean_bibtex_value (fields["keywords"]);
                doc.set_tags_from_string (kw);
            }
            if (fields.has_key ("file")) {
                doc.path = clean_bibtex_value (fields["file"]);
                // Handle Zotero-style file field: "description:path:type"
                if (doc.path.contains (":")) {
                    var parts = doc.path.split (":");
                    if (parts.length >= 2) {
                        doc.path = parts[1];
                    }
                }
            }
            // Read pince- fields
            if (fields.has_key ("pince-path")) {
                doc.path = clean_bibtex_value (fields["pince-path"]);
            }
            if (fields.has_key ("pince-filetype")) {
                doc.filetype = clean_bibtex_value (fields["pince-filetype"]);
            }
            if (fields.has_key ("pince-date-added")) {
                doc.date_added = clean_bibtex_value (fields["pince-date-added"]);
            }
            if (fields.has_key ("pince-starred")) {
                doc.starred = clean_bibtex_value (fields["pince-starred"]) == "true";
            }
            if (fields.has_key ("pince-reading-status")) {
                doc.reading_status = ReadingStatus.from_string (clean_bibtex_value (fields["pince-reading-status"]));
            }

            // Detect filetype from path if not set
            if (doc.filetype.length == 0 && doc.path.length > 0) {
                if (doc.path.has_suffix (".pdf")) doc.filetype = "pdf";
                else if (doc.path.has_suffix (".docx")) doc.filetype = "docx";
                else if (doc.path.has_suffix (".odt")) doc.filetype = "odt";
                else if (doc.path.has_suffix (".txt")) doc.filetype = "txt";
            }

            return doc;
        }

        private static Gee.HashMap<string, string> parse_fields (string body) {
            var fields = new Gee.HashMap<string, string> ();
            int pos = 0;
            int len = body.length;

            while (pos < len) {
                // Skip whitespace and commas
                while (pos < len && (body[pos] == ' ' || body[pos] == '\n' ||
                       body[pos] == '\r' || body[pos] == '\t' || body[pos] == ',')) {
                    pos++;
                }
                if (pos >= len) break;

                // Read field name
                int eq_pos = body.index_of ("=", pos);
                if (eq_pos < 0) break;

                string field_name = body.substring (pos, eq_pos - pos).strip ().down ();
                pos = eq_pos + 1;

                // Skip whitespace
                while (pos < len && (body[pos] == ' ' || body[pos] == '\t')) pos++;
                if (pos >= len) break;

                // Read field value
                string value;
                if (body[pos] == '{') {
                    int end = find_matching_brace (body, pos);
                    if (end < 0) break;
                    value = body.substring (pos + 1, end - pos - 1);
                    pos = end + 1;
                } else if (body[pos] == '"') {
                    int end = body.index_of ("\"", pos + 1);
                    if (end < 0) break;
                    value = body.substring (pos + 1, end - pos - 1);
                    pos = end + 1;
                } else {
                    // Bare value (number or macro)
                    int end = pos;
                    while (end < len && body[end] != ',' && body[end] != '}' &&
                           body[end] != '\n') {
                        end++;
                    }
                    value = body.substring (pos, end - pos).strip ();
                    pos = end;
                }

                if (field_name.length > 0) {
                    fields[field_name] = value;
                }
            }

            return fields;
        }

        private static int find_matching_brace (string text, int start) {
            int depth = 0;
            for (int i = start; i < text.length; i++) {
                if (text[i] == '{') depth++;
                else if (text[i] == '}') {
                    depth--;
                    if (depth == 0) return i;
                }
            }
            return -1;
        }

        private static int skip_braced_block (string text, int brace_start) {
            int end = find_matching_brace (text, brace_start);
            return (end >= 0) ? end + 1 : text.length;
        }

        private static string clean_bibtex_value (string value) {
            // Remove surrounding braces and basic LaTeX commands
            var result = value;
            // Remove outermost braces if present
            if (result.has_prefix ("{") && result.has_suffix ("}")) {
                result = result.substring (1, result.length - 2);
            }
            // Remove common LaTeX escapes
            result = result.replace ("\\&", "&");
            result = result.replace ("\\%", "%");
            result = result.replace ("\\~", "~");
            result = result.replace ("\\textit{", "");
            result = result.replace ("\\emph{", "");
            result = result.replace ("\\textbf{", "");
            result = result.replace ("}", "");
            return result.strip ();
        }

        private static void write_entry (StringBuilder sb, Document doc) {
            sb.append_printf ("@%s{%s,\n", doc.entry_type, doc.id);

            if (doc.title.length > 0) {
                sb.append_printf ("  title = {%s},\n", doc.title);
            }
            if (doc.authors.size > 0) {
                var authors_parts = new string[doc.authors.size];
                for (int i = 0; i < doc.authors.size; i++) {
                    authors_parts[i] = doc.authors[i];
                }
                sb.append_printf ("  author = {%s},\n", string.joinv (" and ", authors_parts));
            }
            if (doc.year.length > 0) {
                sb.append_printf ("  year = {%s},\n", doc.year);
            }
            if (doc.doi.length > 0) {
                sb.append_printf ("  doi = {%s},\n", doc.doi);
            }
            if (doc.isbn.length > 0) {
                sb.append_printf ("  isbn = {%s},\n", doc.isbn);
            }
            if (doc.journal.length > 0) {
                sb.append_printf ("  journal = {%s},\n", doc.journal);
            }
            if (doc.volume.length > 0) {
                sb.append_printf ("  volume = {%s},\n", doc.volume);
            }
            if (doc.pages.length > 0) {
                sb.append_printf ("  pages = {%s},\n", doc.pages);
            }
            if (doc.publisher.length > 0) {
                sb.append_printf ("  publisher = {%s},\n", doc.publisher);
            }
            if (doc.url.length > 0) {
                sb.append_printf ("  url = {%s},\n", doc.url);
            }
            if (doc.abstract_text.length > 0) {
                sb.append_printf ("  abstract = {%s},\n", doc.abstract_text);
            }
            if (doc.note.length > 0) {
                sb.append_printf ("  note = {%s},\n", doc.note);
            }
            if (doc.tags.size > 0) {
                sb.append_printf ("  keywords = {%s},\n", doc.get_tags_display ());
            }
            if (doc.path.length > 0) {
                sb.append_printf ("  pince-path = {%s},\n", doc.path);
            }
            if (doc.filetype.length > 0) {
                sb.append_printf ("  pince-filetype = {%s},\n", doc.filetype);
            }
            if (doc.date_added.length > 0) {
                sb.append_printf ("  pince-date-added = {%s},\n", doc.date_added);
            }
            sb.append_printf ("  pince-starred = {%s},\n", doc.starred ? "true" : "false");
            sb.append_printf ("  pince-reading-status = {%s},\n", doc.reading_status.to_string_value ());

            sb.append ("}\n");
        }
    }
}
