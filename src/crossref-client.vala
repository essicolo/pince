namespace Pince {
    /**
     * CrossRef API client for DOI metadata lookup.
     *
     * Security and privacy:
     * - Only makes HTTPS GET requests to api.crossref.org
     * - Only sends the DOI string (e.g. "10.1038/nature12373")
     * - Never called automatically — only on explicit user action
     * - No authentication, no cookies, no tracking
     * - DOI format is validated before any network request
     *
     * CrossRef is a non-profit DOI registration agency.
     * Their API is free and public: https://api.crossref.org
     */
    public class CrossRefClient {
        private const string API_HOST = "api.crossref.org";
        private const string BASE_URL = "https://api.crossref.org/works/";
        private const string USER_AGENT = "Pince/0.1.0 (https://github.com/essicolo/pince; mailto:pince@example.com)";

        /**
         * Validate that a string looks like a DOI before making any request.
         * DOIs start with "10." followed by a registrant code and a suffix.
         */
        public static bool is_valid_doi (string doi) {
            if (doi.length < 7) return false;
            if (!doi.has_prefix ("10.")) return false;

            // Must have a slash separating registrant from suffix
            if (!doi.contains ("/")) return false;

            // Check for obviously invalid characters (injection attempts)
            if (doi.contains ("..") || doi.contains ("\\") ||
                doi.contains ("<") || doi.contains (">") ||
                doi.contains ("'") || doi.contains ("\"") ||
                doi.contains ("\n") || doi.contains ("\r")) {
                return false;
            }

            return true;
        }

        /**
         * Fetch metadata from CrossRef for a document's DOI.
         * Populates title, authors, year, abstract, journal, etc.
         *
         * Only sends an HTTPS GET to api.crossref.org with the DOI.
         * No other data from the document or system is transmitted.
         */
        public static async void fetch_metadata (Document doc) throws Error {
            if (doc.doi.length == 0) {
                throw new IOError.INVALID_ARGUMENT ("No DOI provided");
            }

            if (!is_valid_doi (doc.doi)) {
                throw new IOError.INVALID_ARGUMENT (
                    "Invalid DOI format: must start with '10.' and contain '/'"
                );
            }

            var session = new Soup.Session ();
            session.timeout = 15;

            var encoded_doi = Uri.escape_string (doc.doi, "/", false);
            var url = BASE_URL + encoded_doi;

            // Verify the URL actually points to CrossRef (defense in depth)
            var uri = Uri.parse (url, UriFlags.NONE);
            if (uri.get_host () != API_HOST) {
                throw new IOError.INVALID_ARGUMENT ("URL does not point to CrossRef API");
            }

            var message = new Soup.Message ("GET", url);
            message.request_headers.append ("User-Agent", USER_AGENT);

            var input_stream = yield session.send_async (message, Priority.DEFAULT, null);

            if (message.status_code != 200) {
                throw new IOError.FAILED ("CrossRef returned status %u", message.status_code);
            }

            var data = yield Utils.read_stream_to_string (input_stream);
            parse_crossref_response (data, doc);
        }

        /**
         * Search CrossRef by title to find a DOI.
         * Sends only the title string to api.crossref.org.
         * Returns true if a match was found and the document was updated.
         */
        public static async bool search_by_title (Document doc) throws Error {
            if (doc.title.length < 5) {
                throw new IOError.INVALID_ARGUMENT ("Title too short to search");
            }

            var session = new Soup.Session ();
            session.timeout = 15;

            var encoded_title = Uri.escape_string (doc.title, null, false);
            var url = "https://%s/works?query.bibliographic=%s&rows=3".printf (API_HOST, encoded_title);

            var message = new Soup.Message ("GET", url);
            message.request_headers.append ("User-Agent", USER_AGENT);

            var input_stream = yield session.send_async (message, Priority.DEFAULT, null);

            if (message.status_code != 200) {
                throw new IOError.FAILED ("CrossRef returned status %u", message.status_code);
            }

            var data = yield Utils.read_stream_to_string (input_stream);

            var parser = new Json.Parser ();
            parser.load_from_data (data);

            var root = parser.get_root ().get_object ();
            var msg = root.get_object_member ("message");
            var items = msg.get_array_member ("items");

            if (items.get_length () == 0) return false;

            // Check if the first result is a close title match
            var first = items.get_object_element (0);
            if (first.has_member ("title")) {
                var titles = first.get_array_member ("title");
                if (titles.get_length () > 0) {
                    var result_title = titles.get_string_element (0).down ();
                    var search_title = doc.title.down ();
                    // Accept if the result title contains most of the search words
                    var words = search_title.split (" ");
                    int matched = 0;
                    foreach (var word in words) {
                        if (word.length > 2 && result_title.contains (word)) {
                            matched++;
                        }
                    }
                    if (words.length > 0 && matched < words.length / 2) {
                        return false;  // Not a close enough match
                    }
                }
            }

            parse_work_object (first, doc);
            return true;
        }

        private static void parse_crossref_response (string data, Document doc) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (data);

            var root = parser.get_root ().get_object ();
            var message = root.get_object_member ("message");
            parse_work_object (message, doc);
        }

        private static void parse_work_object (Json.Object work, Document doc) {
            // Title
            if (work.has_member ("title")) {
                var titles = work.get_array_member ("title");
                if (titles.get_length () > 0) {
                    doc.title = titles.get_string_element (0);
                }
            }

            // Authors
            if (work.has_member ("author")) {
                doc.authors.clear ();
                var authors = work.get_array_member ("author");
                for (uint i = 0; i < authors.get_length (); i++) {
                    var author = authors.get_object_element (i);
                    var name = "";
                    if (author.has_member ("family") && author.has_member ("given")) {
                        name = "%s, %s".printf (
                            author.get_string_member ("family"),
                            author.get_string_member ("given")
                        );
                    } else if (author.has_member ("family")) {
                        name = author.get_string_member ("family");
                    } else if (author.has_member ("name")) {
                        name = author.get_string_member ("name");
                    }
                    if (name.length > 0) {
                        doc.authors.add (name);
                    }
                }
            }

            // Year
            if (work.has_member ("published-print")) {
                extract_year_from_date (work.get_object_member ("published-print"), doc);
            } else if (work.has_member ("published-online")) {
                extract_year_from_date (work.get_object_member ("published-online"), doc);
            } else if (work.has_member ("issued")) {
                extract_year_from_date (work.get_object_member ("issued"), doc);
            }

            // DOI
            if (work.has_member ("DOI") && doc.doi.length == 0) {
                doc.doi = work.get_string_member ("DOI");
            }

            // Abstract
            if (work.has_member ("abstract")) {
                doc.abstract_text = work.get_string_member ("abstract");
                try {
                    var tag_regex = new Regex ("<[^>]+>");
                    doc.abstract_text = tag_regex.replace (doc.abstract_text, -1, 0, "");
                } catch (RegexError e) {}
                doc.abstract_text = doc.abstract_text.strip ();
            }

            // Entry type
            if (work.has_member ("type")) {
                doc.entry_type = work.get_string_member ("type");
            }

            // Journal / container title
            if (work.has_member ("container-title")) {
                var ct = work.get_array_member ("container-title");
                if (ct.get_length () > 0) {
                    doc.journal = ct.get_string_element (0);
                }
            }

            if (work.has_member ("volume")) {
                doc.volume = work.get_string_member ("volume");
            }

            if (work.has_member ("page")) {
                doc.pages = work.get_string_member ("page");
            }

            if (work.has_member ("publisher")) {
                doc.publisher = work.get_string_member ("publisher");
            }

            if (work.has_member ("URL")) {
                doc.url = work.get_string_member ("URL");
            }
        }

        private static void extract_year_from_date (Json.Object date_obj, Document doc) {
            if (date_obj.has_member ("date-parts")) {
                var parts = date_obj.get_array_member ("date-parts");
                if (parts.get_length () > 0) {
                    var first = parts.get_array_element (0);
                    if (first.get_length () > 0) {
                        doc.year = first.get_int_element (0).to_string ();
                    }
                }
            }
        }
    }
}
