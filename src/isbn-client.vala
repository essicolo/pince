namespace Pince {
    /**
     * OpenLibrary API client for ISBN metadata lookup.
     *
     * Security and privacy:
     * - Only makes HTTPS GET requests to openlibrary.org
     * - Only sends the ISBN (digits only, after normalization)
     * - Never called automatically — only on explicit user action
     * - No authentication, no cookies, no tracking
     * - ISBN is validated (length + check digit) before any network request
     *
     * OpenLibrary is a project of the Internet Archive.
     * The Books API is free and public: https://openlibrary.org/dev/docs/api/books
     */
    public class IsbnClient {
        private const string API_HOST = "openlibrary.org";
        private const string USER_AGENT = "Pince/0.1.0 (https://github.com/essicolo/pince; mailto:pince@example.com)";

        private static Soup.Session? _session = null;
        private static Soup.Session get_session () {
            if (_session == null) {
                _session = new Soup.Session ();
                _session.timeout = 15;
            }
            return _session;
        }

        /**
         * Strip hyphens, spaces and any other separators commonly found in
         * printed ISBNs. Returns digits (and a possible trailing 'X' for
         * ISBN-10 check digits).
         */
        public static string normalize_isbn (string raw) {
            var sb = new StringBuilder ();
            unichar c;
            int idx = 0;
            while (raw.get_next_char (ref idx, out c)) {
                if (c.isdigit ()) {
                    sb.append_unichar (c);
                } else if (c == 'X' || c == 'x') {
                    sb.append_c ('X');
                }
            }
            return sb.str;
        }

        /**
         * Validate an ISBN-10 or ISBN-13 (check digit verified).
         * The input is normalized first, so users can paste hyphenated values.
         */
        public static bool is_valid_isbn (string raw) {
            var n = normalize_isbn (raw);
            if (n.length == 10) return is_valid_isbn10 (n);
            if (n.length == 13) return is_valid_isbn13 (n);
            return false;
        }

        private static bool is_valid_isbn10 (string n) {
            int sum = 0;
            for (int i = 0; i < 9; i++) {
                var ch = n[i];
                if (ch < '0' || ch > '9') return false;
                sum += (ch - '0') * (10 - i);
            }
            var check = n[9];
            int check_val;
            if (check == 'X') {
                check_val = 10;
            } else if (check >= '0' && check <= '9') {
                check_val = check - '0';
            } else {
                return false;
            }
            sum += check_val;
            return (sum % 11) == 0;
        }

        private static bool is_valid_isbn13 (string n) {
            int sum = 0;
            for (int i = 0; i < 13; i++) {
                var ch = n[i];
                if (ch < '0' || ch > '9') return false;
                int digit = ch - '0';
                sum += (i % 2 == 0) ? digit : digit * 3;
            }
            return (sum % 10) == 0;
        }

        /**
         * Fetch metadata from OpenLibrary for a document's ISBN.
         * Populates title, authors, year, publisher.
         *
         * Sends only the ISBN to openlibrary.org. No other document or
         * system data is transmitted.
         */
        public static async void fetch_metadata (Document doc) throws Error {
            if (doc.isbn.length == 0) {
                throw new IOError.INVALID_ARGUMENT ("No ISBN provided");
            }

            var isbn = normalize_isbn (doc.isbn);
            if (!is_valid_isbn (isbn)) {
                throw new IOError.INVALID_ARGUMENT (
                    "Invalid ISBN: must be 10 or 13 digits with a valid check digit"
                );
            }

            var session = get_session ();

            // jscmd=data returns a richer payload than the default
            var url = "https://openlibrary.org/api/books?bibkeys=ISBN:%s&format=json&jscmd=data".printf (isbn);

            var uri = Uri.parse (url, UriFlags.NONE);
            if (uri.get_host () != API_HOST) {
                throw new IOError.INVALID_ARGUMENT ("URL does not point to OpenLibrary");
            }

            var message = new Soup.Message ("GET", url);
            message.request_headers.append ("User-Agent", USER_AGENT);
            message.request_headers.append ("Accept", "application/json");

            var input_stream = yield session.send_async (message, Priority.DEFAULT, null);

            if (message.status_code != 200) {
                throw new IOError.FAILED ("OpenLibrary returned status %u", message.status_code);
            }

            var data = yield Utils.read_stream_to_string (input_stream);
            parse_response (data, isbn, doc);
        }

        public static void parse_response (string data, string isbn, Document doc) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (data);

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                throw new IOError.INVALID_DATA ("OpenLibrary response is not a JSON object");
            }

            var obj = root.get_object ();
            var key = "ISBN:" + isbn;
            if (!obj.has_member (key)) {
                // OpenLibrary returns {} when the ISBN is unknown
                throw new IOError.NOT_FOUND ("No OpenLibrary entry for ISBN %s".printf (isbn));
            }

            var book = obj.get_object_member (key);

            if (book.has_member ("title")) {
                doc.title = book.get_string_member ("title");
            }

            if (book.has_member ("subtitle")) {
                var subtitle = book.get_string_member ("subtitle");
                if (subtitle.length > 0 && doc.title.length > 0) {
                    doc.title = "%s: %s".printf (doc.title, subtitle);
                }
            }

            if (book.has_member ("authors")) {
                doc.authors.clear ();
                var authors = book.get_array_member ("authors");
                for (uint i = 0; i < authors.get_length (); i++) {
                    var author = authors.get_object_element (i);
                    if (author.has_member ("name")) {
                        // OpenLibrary returns "Given Family"; convert to "Family, Given"
                        var name = author.get_string_member ("name").strip ();
                        if (name.length > 0) {
                            doc.authors.add (to_family_given (name));
                        }
                    }
                }
            }

            if (book.has_member ("publish_date")) {
                var date = book.get_string_member ("publish_date");
                doc.year = extract_year (date);
            }

            if (book.has_member ("publishers")) {
                var pubs = book.get_array_member ("publishers");
                if (pubs.get_length () > 0) {
                    var pub = pubs.get_object_element (0);
                    if (pub.has_member ("name")) {
                        doc.publisher = pub.get_string_member ("name");
                    }
                }
            }

            // Fill the canonical ISBN (normalized) back into the document
            // so downstream serialization stores a clean value.
            doc.isbn = isbn;
            doc.entry_type = "book";
        }

        private static string to_family_given (string display) {
            if (display.contains (",")) return display;  // already in target form
            var parts = display.split (" ");
            if (parts.length < 2) return display;
            var family = parts[parts.length - 1];
            var given = string.joinv (" ", parts[0:parts.length - 1]);
            return "%s, %s".printf (family, given);
        }

        private static string extract_year (string date) {
            try {
                var year_regex = new Regex ("(1[5-9]\\d{2}|20\\d{2}|21\\d{2})");
                MatchInfo info;
                if (year_regex.match (date, 0, out info)) {
                    return info.fetch (0);
                }
            } catch (RegexError e) {}
            return "";
        }
    }
}
