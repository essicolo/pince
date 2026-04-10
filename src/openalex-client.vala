namespace Pince {
    /**
     * OpenAlex API client for metadata lookup.
     *
     * OpenAlex is a free, open catalog of scholarly works that indexes
     * CrossRef, arXiv, PubMed, and other sources. Broader coverage than
     * CrossRef alone.
     *
     * API docs: https://docs.openalex.org
     */
    public class OpenAlexClient {
        private const string BASE_URL = "https://api.openalex.org/works/";
        private const string USER_AGENT = "Pince/0.1.0 (mailto:pince@example.com)";

        private static Soup.Session? _session = null;
        private static Soup.Session get_session () {
            if (_session == null) {
                _session = new Soup.Session ();
                _session.timeout = 15;
            }
            return _session;
        }

        /**
         * Fetch metadata by DOI from OpenAlex.
         */
        public static async void fetch_metadata (Document doc) throws Error {
            if (doc.doi.length == 0) {
                throw new IOError.INVALID_ARGUMENT ("No DOI provided");
            }

            var session = get_session ();

            var encoded_doi = Uri.escape_string (doc.doi, "/", false);
            var url = BASE_URL + "doi:" + encoded_doi;

            var message = new Soup.Message ("GET", url);
            message.request_headers.append ("User-Agent", USER_AGENT);

            var input_stream = yield session.send_async (message, Priority.DEFAULT, null);

            if (message.status_code != 200) {
                throw new IOError.FAILED ("OpenAlex returned status %u", message.status_code);
            }

            var data = yield Utils.read_stream_to_string (input_stream);
            parse_work (data, doc);
        }

        /**
         * Search by title on OpenAlex.
         * Returns true if a match was found and the document was updated.
         */
        public static async bool search_by_title (Document doc) throws Error {
            if (doc.title.length < 5) {
                throw new IOError.INVALID_ARGUMENT ("Title too short to search");
            }

            var session = get_session ();

            var encoded_title = Uri.escape_string (doc.title, null, false);
            var url = "https://api.openalex.org/works?search=%s&per_page=3".printf (encoded_title);

            var message = new Soup.Message ("GET", url);
            message.request_headers.append ("User-Agent", USER_AGENT);

            var input_stream = yield session.send_async (message, Priority.DEFAULT, null);

            if (message.status_code != 200) {
                throw new IOError.FAILED ("OpenAlex returned status %u", message.status_code);
            }

            var data = yield Utils.read_stream_to_string (input_stream);

            var parser = new Json.Parser ();
            parser.load_from_data (data);

            var root = parser.get_root ().get_object ();
            var results = root.get_array_member ("results");

            if (results.get_length () == 0) return false;

            var first = results.get_object_element (0);

            // Check title match quality
            if (first.has_member ("title") && !first.get_null_member ("title")) {
                var result_title = first.get_string_member ("title").down ();
                var search_title = doc.title.down ();
                var words = search_title.split (" ");
                int matched = 0;
                foreach (var word in words) {
                    if (word.length > 2 && result_title.contains (word)) {
                        matched++;
                    }
                }
                if (words.length > 0 && matched < words.length / 2) {
                    return false;
                }
            }

            parse_work_object (first, doc);
            return true;
        }

        public static void parse_work (string data, Document doc) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (data);
            var root = parser.get_root ().get_object ();
            parse_work_object (root, doc);
        }

        private static void parse_work_object (Json.Object work, Document doc) {
            // Title
            if (work.has_member ("title") && !work.get_null_member ("title")) {
                doc.title = work.get_string_member ("title");
            }

            // Year — simple integer, no date-parts mess
            if (work.has_member ("publication_year") && !work.get_null_member ("publication_year")) {
                var year = (int) work.get_int_member ("publication_year");
                if (year > 0) {
                    doc.year = year.to_string ();
                }
            }

            // DOI
            if (work.has_member ("doi") && !work.get_null_member ("doi") && doc.doi.length == 0) {
                var doi_url = work.get_string_member ("doi");
                if (doi_url.has_prefix ("https://doi.org/")) {
                    doc.doi = doi_url.substring ("https://doi.org/".length);
                } else {
                    doc.doi = doi_url;
                }
            }

            // Authors
            if (work.has_member ("authorships") && !work.get_null_member ("authorships")) {
                var authorships = work.get_array_member ("authorships");
                if (authorships.get_length () > 0) {
                    doc.authors.clear ();
                    for (uint i = 0; i < authorships.get_length (); i++) {
                        var authorship = authorships.get_object_element (i);
                        if (authorship.has_member ("author") && !authorship.get_null_member ("author")) {
                            var author = authorship.get_object_member ("author");
                            if (author.has_member ("display_name") && !author.get_null_member ("display_name")) {
                                var name = author.get_string_member ("display_name");
                                var converted = convert_author_name (name);
                                if (converted.length > 0) {
                                    doc.authors.add (converted);
                                }
                            }
                        }
                    }
                }
            }

            // Entry type
            if (work.has_member ("type") && !work.get_null_member ("type")) {
                doc.entry_type = work.get_string_member ("type");
            }

            // Journal / source
            if (work.has_member ("primary_location") && !work.get_null_member ("primary_location")) {
                var location = work.get_object_member ("primary_location");
                if (location.has_member ("source") && !location.get_null_member ("source")) {
                    var source = location.get_object_member ("source");
                    if (source.has_member ("display_name") && !source.get_null_member ("display_name")) {
                        doc.journal = source.get_string_member ("display_name");
                    }
                }
            }

            // Publisher
            if (work.has_member ("host_venue") && !work.get_null_member ("host_venue")) {
                var venue = work.get_object_member ("host_venue");
                if (venue.has_member ("publisher") && !venue.get_null_member ("publisher")) {
                    doc.publisher = venue.get_string_member ("publisher");
                }
            }

            // Biblio: volume, pages
            if (work.has_member ("biblio") && !work.get_null_member ("biblio")) {
                var biblio = work.get_object_member ("biblio");
                if (biblio.has_member ("volume") && !biblio.get_null_member ("volume")) {
                    doc.volume = biblio.get_string_member ("volume");
                }
                if (biblio.has_member ("first_page") && !biblio.get_null_member ("first_page")) {
                    var first_page = biblio.get_string_member ("first_page");
                    if (biblio.has_member ("last_page") && !biblio.get_null_member ("last_page")) {
                        doc.pages = "%s-%s".printf (first_page, biblio.get_string_member ("last_page"));
                    } else {
                        doc.pages = first_page;
                    }
                }
            }

            // Abstract from inverted index
            if (work.has_member ("abstract_inverted_index") && !work.get_null_member ("abstract_inverted_index")) {
                var abstract_text = reconstruct_abstract (work.get_object_member ("abstract_inverted_index"));
                if (abstract_text.length > 0) {
                    doc.abstract_text = abstract_text;
                }
            }

            // URL
            if (doc.url.length == 0 && work.has_member ("id") && !work.get_null_member ("id")) {
                doc.url = work.get_string_member ("id");
            }
        }

        /**
         * Convert "Given Family" to "Family, Given" format.
         */
        private static string convert_author_name (string display_name) {
            var trimmed = display_name.strip ();
            if (trimmed.length == 0) return "";

            var parts = trimmed.split (" ");
            if (parts.length < 2) return trimmed;

            var family = parts[parts.length - 1];
            var given_parts = new string[parts.length - 1];
            for (int i = 0; i < parts.length - 1; i++) {
                given_parts[i] = parts[i];
            }
            return "%s, %s".printf (family, string.joinv (" ", given_parts));
        }

        /**
         * Reconstruct abstract text from OpenAlex inverted index format.
         * Input: { "word1": [0, 5], "word2": [1, 3], ... }
         * Output: "word1 word2 ..." ordered by position
         */
        private static string reconstruct_abstract (Json.Object inverted_index) {
            var positions = new Gee.TreeMap<int, string> ();

            foreach (var word in inverted_index.get_members ()) {
                var pos_array = inverted_index.get_array_member (word);
                for (uint i = 0; i < pos_array.get_length (); i++) {
                    var pos = (int) pos_array.get_int_element (i);
                    positions[pos] = word;
                }
            }

            var sb = new StringBuilder ();
            foreach (var entry in positions.entries) {
                if (sb.len > 0) sb.append (" ");
                sb.append (entry.value);
            }
            return sb.str;
        }
    }
}
