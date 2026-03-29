namespace Pince {
    public class CitationFormatter {
        /**
         * Format a document as an APA citation.
         * Format: "Author, A. B. and Author, C. D. (Year). Title. Journal, Volume, Pages."
         */
        public static string format_apa (Document doc) {
            var sb = new StringBuilder ();

            // Authors
            if (doc.authors.size > 0) {
                var author_parts = new string[doc.authors.size];
                for (int i = 0; i < doc.authors.size; i++) {
                    author_parts[i] = format_apa_author (doc.authors[i]);
                }
                if (author_parts.length == 1) {
                    sb.append (author_parts[0]);
                } else if (author_parts.length == 2) {
                    sb.append ("%s and %s".printf (author_parts[0], author_parts[1]));
                } else {
                    for (int i = 0; i < author_parts.length; i++) {
                        if (i == author_parts.length - 1) {
                            sb.append ("and %s".printf (author_parts[i]));
                        } else {
                            sb.append ("%s, ".printf (author_parts[i]));
                        }
                    }
                }
            }

            // Year
            if (doc.year.length > 0) {
                sb.append (" (%s)".printf (doc.year));
            }
            sb.append (". ");

            // Title
            if (doc.title.length > 0) {
                sb.append (doc.title);
                if (!doc.title.has_suffix (".") && !doc.title.has_suffix ("?") &&
                    !doc.title.has_suffix ("!")) {
                    sb.append (".");
                }
            }

            // Journal, Volume, Pages
            if (doc.journal.length > 0) {
                sb.append (" ");
                sb.append (doc.journal);
                if (doc.volume.length > 0) {
                    sb.append (", %s".printf (doc.volume));
                }
                if (doc.pages.length > 0) {
                    sb.append (", %s".printf (doc.pages));
                }
                sb.append (".");
            }

            return sb.str;
        }

        /**
         * Format an author name for APA style.
         * Input is "Family, Given" or "Given Family".
         * Output is "Family, G. B." (initials for given names).
         */
        private static string format_apa_author (string author) {
            if (author.contains (",")) {
                // Already "Family, Given" format
                var parts = author.split (",", 2);
                var family = parts[0].strip ();
                if (parts.length > 1) {
                    var given = parts[1].strip ();
                    var initials = get_initials (given);
                    return "%s, %s".printf (family, initials);
                }
                return family;
            } else {
                // "Given Family" format - last word is family name
                var words = author.strip ().split (" ");
                if (words.length == 1) return author;
                var family = words[words.length - 1];
                var given_parts = new string[words.length - 1];
                for (int i = 0; i < words.length - 1; i++) {
                    given_parts[i] = words[i];
                }
                var given = string.joinv (" ", given_parts);
                var initials = get_initials (given);
                return "%s, %s".printf (family, initials);
            }
        }

        private static string get_initials (string given) {
            var words = given.strip ().split (" ");
            var sb = new StringBuilder ();
            foreach (var w in words) {
                var trimmed = w.strip ();
                if (trimmed.length > 0) {
                    if (sb.len > 0) sb.append (" ");
                    sb.append_unichar (trimmed.get_char (0).toupper ());
                    sb.append (".");
                }
            }
            return sb.str;
        }

        /**
         * Format a document as a BibTeX entry.
         * Generates @type{key, field = {value}, ...}
         */
        public static string format_bibtex (Document doc) {
            var sb = new StringBuilder ();

            var entry_type = doc.entry_type.length > 0 ? doc.entry_type : "article";
            var key = generate_bibtex_key (doc);

            sb.append_printf ("@%s{%s,\n", entry_type, key);

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
            if (doc.tags.size > 0) {
                sb.append_printf ("  keywords = {%s},\n", doc.get_tags_display ());
            }

            sb.append ("}\n");
            return sb.str;
        }

        /**
         * Generate a BibTeX citation key from the document.
         * Format: firstauthorfamily + year (e.g., "he2016")
         */
        private static string generate_bibtex_key (Document doc) {
            if (doc.id.length > 0) return doc.id;

            var sb = new StringBuilder ();

            if (doc.authors.size > 0) {
                var first = doc.authors[0];
                if (first.contains (",")) {
                    // "Family, Given"
                    sb.append (first.split (",")[0].strip ().down ());
                } else {
                    // "Given Family" — take last word
                    var words = first.strip ().split (" ");
                    sb.append (words[words.length - 1].down ());
                }
            } else {
                sb.append ("unknown");
            }

            if (doc.year.length > 0) {
                sb.append (doc.year);
            }

            // Remove non-alphanumeric chars
            var key = sb.str;
            var clean = new StringBuilder ();
            for (int i = 0; i < key.length; i++) {
                if (key[i].isalnum ()) {
                    clean.append_c (key[i]);
                }
            }
            return clean.str;
        }
    }
}
