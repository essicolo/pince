namespace Pince {
    public class MetadataExtractor {
        /**
         * Run the full metadata extraction pipeline for a file.
         * Priority:
         *   1. Extract DOI from PDF text (first 2 pages)
         *   2. If DOI found: query CrossRef API and populate fields
         *   3. Fallback: extract title/author from PDF metadata (XMP/Info dict)
         *   4. Fallback: parse filename for author/year/title pattern
         *   5. For DOCX/ODT: read document properties
         */
        public static async Document extract (string file_path) {
            var doc = new Document.from_file (file_path);

            switch (doc.filetype) {
                case "pdf":
                    yield extract_pdf (doc);
                    break;
                case "docx":
                    extract_docx (doc);
                    break;
                case "odt":
                    extract_odt (doc);
                    break;
                default:
                    extract_from_filename (doc);
                    break;
            }

            return doc;
        }

        private static async void extract_pdf (Document doc) {
            try {
                var file_uri = File.new_for_path (doc.path).get_uri ();
                var pdf_doc = new Poppler.Document.from_file (file_uri, null);

                // Step 1: Try to extract DOI from text — scan up to 5 pages
                string? doi = null;
                int max_pages = int.min (5, pdf_doc.get_n_pages ());
                for (int i = 0; i < max_pages; i++) {
                    var page = pdf_doc.get_page (i);
                    if (page != null) {
                        var text = page.get_text ();
                        if (text != null) {
                            doi = extract_doi_from_text (text);
                            if (doi != null) break;
                        }
                    }
                }

                // Step 2: Store DOI if found (but don't fetch from web —
                // that only happens on explicit user action)
                if (doi != null) {
                    doc.doi = doi;
                }

                // Step 3: Extract what we can from PDF metadata
                extract_pdf_metadata (pdf_doc, doc);

            } catch (Error e) {
                warning ("PDF extraction failed for %s: %s", doc.path, e.message);
            }

            // Step 4: Fallback to filename
            if (doc.title.length == 0) {
                extract_from_filename (doc);
            }
        }

        public static string? extract_doi_from_text (string text) {
            // DOI pattern: 10.XXXX/... (standard DOI format)
            try {
                var regex = new Regex (
                    """(10\.\d{4,9}/[^\s,;"\]}>]+)""",
                    RegexCompileFlags.CASELESS
                );
                MatchInfo match;
                if (regex.match (text, 0, out match)) {
                    var doi = match.fetch (1);
                    // Clean trailing punctuation
                    while (doi.has_suffix (".") || doi.has_suffix (",") ||
                           doi.has_suffix (";") || doi.has_suffix (")")) {
                        doi = doi.substring (0, doi.length - 1);
                    }
                    return doi;
                }
            } catch (RegexError e) {
                warning ("DOI regex error: %s", e.message);
            }
            return null;
        }

        private static void extract_pdf_metadata (Poppler.Document pdf_doc, Document doc) {
            var title = pdf_doc.get_title ();
            if (title != null && is_plausible_title (title.strip ())) {
                doc.title = title.strip ();
            }

            var author = pdf_doc.get_author ();
            if (author != null && author.strip ().length > 0) {
                var cleaned = clean_author_string (author.strip ());
                if (cleaned.length > 0) {
                    doc.set_authors_from_string (cleaned);
                }
            }

            var subject = pdf_doc.get_subject ();
            if (subject != null && subject.strip ().length > 0) {
                if (doc.abstract_text.length == 0) {
                    doc.abstract_text = subject;
                }
            }

            var keywords = pdf_doc.get_keywords ();
            if (keywords != null && keywords.strip ().length > 0) {
                doc.set_tags_from_string (keywords);
            }
        }

        /**
         * Check if a title string from PDF metadata is plausible.
         * Reject things like filenames, UUIDs, or single-word garbage.
         */
        public static bool is_plausible_title (string title) {
            if (title.length == 0) return false;
            if (title.length < 3) return false;

            // Reject if it looks like a filename with extension
            if (title.has_suffix (".pdf") || title.has_suffix (".doc") ||
                title.has_suffix (".docx") || title.has_suffix (".tex")) {
                return false;
            }

            // Reject if it looks like a UUID or hash
            try {
                var uuid_regex = new Regex ("^[0-9a-f-]{20,}$", RegexCompileFlags.CASELESS);
                if (uuid_regex.match (title, 0, null)) return false;
            } catch (RegexError e) {}

            // Reject Microsoft Office default titles
            if (title == "Microsoft Word" || title.has_prefix ("Microsoft Word -") ||
                title.has_prefix ("PowerPoint") || title.has_prefix ("Untitled")) {
                return false;
            }

            return true;
        }

        /**
         * Clean a raw author string from PDF metadata.
         * Filter out usernames, email addresses, and system-generated garbage.
         * Returns cleaned string or empty if all entries are garbage.
         */
        public static string clean_author_string (string raw) {
            // If it contains semicolons, use those as separators (common in PDF metadata)
            string[] parts;
            if (raw.contains (";")) {
                parts = raw.split (";");
            } else if (raw.contains (",")) {
                parts = raw.split (",");
            } else if (raw.contains (" and ")) {
                parts = raw.split (" and ");
            } else {
                // Single author — validate it
                if (is_plausible_author (raw.strip ())) {
                    return raw.strip ();
                }
                return "";
            }

            var valid = new Gee.ArrayList<string> ();
            foreach (var part in parts) {
                var trimmed = part.strip ();
                if (trimmed.length > 0 && is_plausible_author (trimmed)) {
                    valid.add (trimmed);
                }
            }

            if (valid.size == 0) return "";

            var result = new string[valid.size];
            for (int i = 0; i < valid.size; i++) {
                result[i] = valid[i];
            }
            return string.joinv (", ", result);
        }

        /**
         * Check if an author name is plausible (not a username, email, etc.)
         */
        public static bool is_plausible_author (string name) {
            if (name.length < 2) return false;

            // Reject email addresses
            if (name.contains ("@")) return false;

            // Reject if it looks like a single lowercase username (no spaces, no uppercase)
            if (!name.contains (" ") && !name.contains (",")) {
                // Single word — check if it has any uppercase letter
                bool has_upper = false;
                for (int i = 0; i < name.length; i++) {
                    if (name[i].isupper ()) {
                        has_upper = true;
                        break;
                    }
                }
                // A single word with no uppercase and short is likely a username
                if (!has_upper && name.length < 20) return false;

                // Even with uppercase, a single short word is suspicious
                // but could be a mononym — accept if >= 3 chars with uppercase
                if (name.length < 3) return false;
            }

            return true;
        }

        private static void extract_docx (Document doc) {
            try {
                var xml = run_unzip (doc.path, "docProps/core.xml");
                if (xml == null) {
                    extract_from_filename (doc);
                    return;
                }
                var fields = parse_office_xml (xml);

                if (fields.has_key ("dc:title") && fields["dc:title"].strip ().length > 0) {
                    var title = fields["dc:title"].strip ();
                    if (is_plausible_title (title)) {
                        doc.title = title;
                    }
                }
                if (fields.has_key ("dc:creator") && fields["dc:creator"].strip ().length > 0) {
                    var author_str = clean_author_string (fields["dc:creator"].strip ());
                    if (author_str.length > 0) {
                        doc.set_authors_from_string (author_str);
                    }
                }
                if (fields.has_key ("dcterms:created") && fields["dcterms:created"].strip ().length > 0) {
                    var date_str = fields["dcterms:created"].strip ();
                    // Extract year from ISO date (e.g. "2023-05-10T00:00:00Z")
                    if (date_str.length >= 4) {
                        doc.year = date_str.substring (0, 4);
                    }
                }
                if (fields.has_key ("dc:subject") && fields["dc:subject"].strip ().length > 0) {
                    doc.set_tags_from_string (fields["dc:subject"].strip ());
                }
                if (fields.has_key ("dc:description") && fields["dc:description"].strip ().length > 0) {
                    doc.abstract_text = fields["dc:description"].strip ();
                }

                // Fallback to filename if no title extracted
                if (doc.title.length == 0) {
                    extract_from_filename (doc);
                }
            } catch (Error e) {
                warning ("DOCX extraction failed for %s: %s", doc.path, e.message);
                extract_from_filename (doc);
            }
        }

        private static void extract_odt (Document doc) {
            try {
                var xml = run_unzip (doc.path, "meta.xml");
                if (xml == null) {
                    extract_from_filename (doc);
                    return;
                }
                var fields = parse_office_xml (xml);

                if (fields.has_key ("dc:title") && fields["dc:title"].strip ().length > 0) {
                    var title = fields["dc:title"].strip ();
                    if (is_plausible_title (title)) {
                        doc.title = title;
                    }
                }
                // Try meta:initial-creator first, then dc:creator
                string? author_str = null;
                if (fields.has_key ("meta:initial-creator") && fields["meta:initial-creator"].strip ().length > 0) {
                    author_str = clean_author_string (fields["meta:initial-creator"].strip ());
                }
                if ((author_str == null || author_str.length == 0) &&
                    fields.has_key ("dc:creator") && fields["dc:creator"].strip ().length > 0) {
                    author_str = clean_author_string (fields["dc:creator"].strip ());
                }
                if (author_str != null && author_str.length > 0) {
                    doc.set_authors_from_string (author_str);
                }
                if (fields.has_key ("dc:date") && fields["dc:date"].strip ().length > 0) {
                    var date_str = fields["dc:date"].strip ();
                    if (date_str.length >= 4) {
                        doc.year = date_str.substring (0, 4);
                    }
                }
                if (fields.has_key ("dc:subject") && fields["dc:subject"].strip ().length > 0) {
                    doc.set_tags_from_string (fields["dc:subject"].strip ());
                }
                if (fields.has_key ("dc:description") && fields["dc:description"].strip ().length > 0) {
                    doc.abstract_text = fields["dc:description"].strip ();
                }

                if (doc.title.length == 0) {
                    extract_from_filename (doc);
                }
            } catch (Error e) {
                warning ("ODT extraction failed for %s: %s", doc.path, e.message);
                extract_from_filename (doc);
            }
        }

        /**
         * Run unzip to extract a file from a zip archive and return its contents.
         * Returns null if unzip fails or is not available.
         */
        private static string? run_unzip (string archive_path, string inner_path) {
            try {
                var subprocess = new GLib.Subprocess (
                    GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE,
                    "unzip", "-p", archive_path, inner_path
                );
                string stdout_buf;
                string stderr_buf;
                subprocess.communicate_utf8 (null, null, out stdout_buf, out stderr_buf);
                if (subprocess.get_exit_status () != 0) {
                    return null;
                }
                return stdout_buf;
            } catch (Error e) {
                warning ("Failed to run unzip for %s: %s", archive_path, e.message);
                return null;
            }
        }

        /**
         * Parse an Office Open XML or ODF metadata XML string.
         * Extracts known Dublin Core and ODF meta elements into a map
         * using simple regex-based extraction.
         */
        private static Gee.HashMap<string, string> parse_office_xml (string xml) {
            var fields = new Gee.HashMap<string, string> ();

            // Element names to extract (with possible namespace prefixes)
            string[] element_names = {
                "dc:title", "dc:creator", "dc:subject", "dc:description",
                "dc:date", "dcterms:created", "meta:initial-creator"
            };

            foreach (var elem in element_names) {
                // Build regex that matches the element with any namespace prefix variant
                // e.g. <dc:title>...</dc:title> or <cp:title>...</cp:title>
                var local_name = elem.split (":")[1];
                try {
                    // Match tags like <prefix:localname ...>content</prefix:localname>
                    // Also match without prefix: <localname>content</localname>
                    var pattern = new Regex (
                        """<[a-zA-Z]*:?""" + Regex.escape_string (local_name) +
                        """[^>]*>([^<]*)</[a-zA-Z]*:?""" + Regex.escape_string (local_name) + """>""",
                        RegexCompileFlags.CASELESS | RegexCompileFlags.DOTALL
                    );
                    MatchInfo match;
                    if (pattern.match (xml, 0, out match)) {
                        var content = match.fetch (1);
                        if (content != null && content.strip ().length > 0) {
                            fields[elem] = content.strip ();
                        }
                    }
                } catch (RegexError e) {
                    warning ("Regex error for element %s: %s", elem, e.message);
                }
            }

            return fields;
        }

        /**
         * Parse filename for metadata. Handles common academic patterns:
         *   - "Author Year Title.pdf"
         *   - "Author_et_al_Year_Title.pdf"
         *   - "Author-2020-Title.pdf"
         *   - Just use cleaned filename as title otherwise
         */
        public static void extract_from_filename (Document doc) {
            var basename = Path.get_basename (doc.path);
            // Remove extension
            var last_dot = basename.last_index_of (".");
            if (last_dot > 0) {
                basename = basename.substring (0, last_dot);
            }

            // Replace underscores and hyphens with spaces
            var cleaned = basename.replace ("_", " ").replace ("-", " ");

            // Try to parse "Author(s) Year Title" pattern
            try {
                // Match: one or more words (authors), then a 4-digit year, then the rest (title)
                var pattern = new Regex (
                    """^(.+?)\s+((?:19|20)\d{2})\s+(.+)$"""
                );
                MatchInfo match;
                if (pattern.match (cleaned, 0, out match)) {
                    var author_part = match.fetch (1).strip ();
                    var year_part = match.fetch (2).strip ();
                    var title_part = match.fetch (3).strip ();

                    if (title_part.length > 0) {
                        doc.title = title_part;
                        doc.year = year_part;

                        // Clean "et al" / "et" / "and" from author part
                        var author_clean = author_part
                            .replace (" et al", "")
                            .replace (" Et Al", "")
                            .replace (" et ", " and ")
                            .replace (" Et ", " and ")
                            .replace (" & ", " and ")
                            .strip ();

                        if (is_plausible_author (author_clean)) {
                            doc.set_authors_from_string (author_clean);
                        }
                        return;
                    }
                }
            } catch (RegexError e) {}

            // Fallback: just use cleaned filename as title
            doc.title = cleaned;
        }
    }
}
