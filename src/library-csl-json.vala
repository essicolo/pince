namespace Pince {
    public class CslJsonIO {
        public static void load (Library library, string path) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_file (path);

            var root = parser.get_root ();
            if (root == null) {
                throw new IOError.INVALID_DATA ("Empty JSON file");
            }

            Json.Array array;

            if (root.get_node_type () == Json.NodeType.ARRAY) {
                // Old format: plain array of items
                array = root.get_array ();
            } else if (root.get_node_type () == Json.NodeType.OBJECT) {
                // New format: { pince: {...}, items: [...] }
                var obj = root.get_object ();

                // Read library metadata
                if (obj.has_member ("pince")) {
                    var meta = obj.get_object_member ("pince");
                    if (meta.has_member ("version")) {
                        library.pince_version = meta.get_string_member ("version");
                    }
                    if (meta.has_member ("author")) {
                        library.library_author = meta.get_string_member ("author");
                    }
                    if (meta.has_member ("created")) {
                        library.created = meta.get_string_member ("created");
                    }
                    if (meta.has_member ("updated")) {
                        library.updated = meta.get_string_member ("updated");
                    }
                }

                if (obj.has_member ("items")) {
                    var items_node = obj.get_member ("items");
                    if (items_node.get_node_type () != Json.NodeType.ARRAY) {
                        throw new IOError.INVALID_DATA ("'items' must be an array");
                    }
                    array = items_node.get_array ();
                } else {
                    // Empty library with metadata only
                    array = new Json.Array ();
                }
            } else {
                throw new IOError.INVALID_DATA ("JSON file must contain an array or object");
            }

            for (uint i = 0; i < array.get_length (); i++) {
                var obj = array.get_object_element (i);
                var doc = parse_csl_object (obj);
                library.documents.add (doc);
            }
        }

        public static void save (Library library, string path) throws Error {
            var builder = new Json.Builder ();
            builder.begin_object ();

            // Library metadata
            builder.set_member_name ("pince");
            builder.begin_object ();
            builder.set_member_name ("version");
            builder.add_string_value (library.pince_version);
            builder.set_member_name ("author");
            builder.add_string_value (library.library_author);
            builder.set_member_name ("created");
            builder.add_string_value (library.created);
            builder.set_member_name ("updated");
            builder.add_string_value (library.updated);
            builder.end_object ();

            // Items
            builder.set_member_name ("items");
            builder.begin_array ();
            foreach (var doc in library.documents) {
                build_csl_object (builder, doc);
            }
            builder.end_array ();

            builder.end_object ();

            var generator = new Json.Generator ();
            generator.set_root (builder.get_root ());
            generator.pretty = true;
            generator.indent = 2;
            generator.to_file (path);
        }

        private static Document parse_csl_object (Json.Object obj) {
            var doc = new Document ();

            if (obj.has_member ("id")) {
                doc.id = obj.get_string_member ("id");
            }

            if (obj.has_member ("title")) {
                doc.title = obj.get_string_member ("title");
            }

            if (obj.has_member ("DOI")) {
                doc.doi = obj.get_string_member ("DOI");
            }

            if (obj.has_member ("abstract")) {
                doc.abstract_text = obj.get_string_member ("abstract");
            }

            if (obj.has_member ("note")) {
                doc.note = obj.get_string_member ("note");
            }

            if (obj.has_member ("type")) {
                doc.entry_type = obj.get_string_member ("type");
            }

            // Journal / container-title
            if (obj.has_member ("container-title")) {
                var ct = obj.get_array_member ("container-title");
                if (ct.get_length () > 0) {
                    doc.journal = ct.get_string_element (0);
                }
            }

            if (obj.has_member ("volume")) {
                doc.volume = obj.get_string_member ("volume");
            }

            if (obj.has_member ("page")) {
                doc.pages = obj.get_string_member ("page");
            }

            if (obj.has_member ("publisher")) {
                doc.publisher = obj.get_string_member ("publisher");
            }

            if (obj.has_member ("URL")) {
                doc.url = obj.get_string_member ("URL");
            }

            // Pince extension fields
            if (obj.has_member ("pince-path")) {
                doc.path = obj.get_string_member ("pince-path");
            }

            if (obj.has_member ("pince-filetype")) {
                doc.filetype = obj.get_string_member ("pince-filetype");
            }

            if (obj.has_member ("pince-date-added")) {
                doc.date_added = obj.get_string_member ("pince-date-added");
            }

            if (obj.has_member ("pince-starred")) {
                doc.starred = obj.get_boolean_member ("pince-starred");
            }

            if (obj.has_member ("pince-reading-status")) {
                doc.reading_status = ReadingStatus.from_string (obj.get_string_member ("pince-reading-status"));
            }

            // Authors
            if (obj.has_member ("author")) {
                var authors_array = obj.get_array_member ("author");
                for (uint i = 0; i < authors_array.get_length (); i++) {
                    var author_obj = authors_array.get_object_element (i);
                    var name = "";
                    if (author_obj.has_member ("family") && author_obj.has_member ("given")) {
                        name = "%s, %s".printf (
                            author_obj.get_string_member ("family"),
                            author_obj.get_string_member ("given")
                        );
                    } else if (author_obj.has_member ("literal")) {
                        name = author_obj.get_string_member ("literal");
                    } else if (author_obj.has_member ("family")) {
                        name = author_obj.get_string_member ("family");
                    }
                    if (name.length > 0) {
                        doc.authors.add (name);
                    }
                }
            }

            // Year from issued date-parts
            if (obj.has_member ("issued")) {
                var issued = obj.get_object_member ("issued");
                if (issued.has_member ("date-parts")) {
                    var parts = issued.get_array_member ("date-parts");
                    if (parts.get_length () > 0) {
                        var first = parts.get_array_element (0);
                        if (first.get_length () > 0) {
                            doc.year = first.get_int_element (0).to_string ();
                        }
                    }
                }
            }

            // Tags from keyword field (CSL extension)
            if (obj.has_member ("keyword")) {
                var kw = obj.get_string_member ("keyword");
                doc.set_tags_from_string (kw);
            }

            // Tags from pince-tags array
            var tags_key = obj.has_member ("pince-tags") ? "pince-tags" : null;
            if (tags_key != null) {
                var tags_array = obj.get_array_member (tags_key);
                for (uint i = 0; i < tags_array.get_length (); i++) {
                    var tag = tags_array.get_string_element (i);
                    if (!doc.tags.contains (tag)) {
                        doc.tags.add (tag);
                    }
                }
            }

            return doc;
        }

        private static void build_csl_object (Json.Builder builder, Document doc) {
            builder.begin_object ();

            builder.set_member_name ("id");
            builder.add_string_value (doc.id);

            builder.set_member_name ("type");
            builder.add_string_value (doc.entry_type);

            builder.set_member_name ("title");
            builder.add_string_value (doc.title);

            if (doc.doi.length > 0) {
                builder.set_member_name ("DOI");
                builder.add_string_value (doc.doi);
            }

            if (doc.abstract_text.length > 0) {
                builder.set_member_name ("abstract");
                builder.add_string_value (doc.abstract_text);
            }

            if (doc.note.length > 0) {
                builder.set_member_name ("note");
                builder.add_string_value (doc.note);
            }

            // Authors
            if (doc.authors.size > 0) {
                builder.set_member_name ("author");
                builder.begin_array ();
                foreach (var author in doc.authors) {
                    builder.begin_object ();
                    // Try to parse "Family, Given" format
                    if (author.contains (",")) {
                        var parts = author.split (",", 2);
                        builder.set_member_name ("family");
                        builder.add_string_value (parts[0].strip ());
                        builder.set_member_name ("given");
                        builder.add_string_value (parts[1].strip ());
                    } else {
                        builder.set_member_name ("literal");
                        builder.add_string_value (author);
                    }
                    builder.end_object ();
                }
                builder.end_array ();
            }

            // Year
            if (doc.year.length > 0) {
                builder.set_member_name ("issued");
                builder.begin_object ();
                builder.set_member_name ("date-parts");
                builder.begin_array ();
                builder.begin_array ();
                builder.add_int_value (int64.parse (doc.year));
                builder.end_array ();
                builder.end_array ();
                builder.end_object ();
            }

            // Journal
            if (doc.journal.length > 0) {
                builder.set_member_name ("container-title");
                builder.begin_array ();
                builder.add_string_value (doc.journal);
                builder.end_array ();
            }

            if (doc.volume.length > 0) {
                builder.set_member_name ("volume");
                builder.add_string_value (doc.volume);
            }

            if (doc.pages.length > 0) {
                builder.set_member_name ("page");
                builder.add_string_value (doc.pages);
            }

            if (doc.publisher.length > 0) {
                builder.set_member_name ("publisher");
                builder.add_string_value (doc.publisher);
            }

            if (doc.url.length > 0) {
                builder.set_member_name ("URL");
                builder.add_string_value (doc.url);
            }

            // Tags as keyword (CSL standard)
            if (doc.tags.size > 0) {
                builder.set_member_name ("keyword");
                builder.add_string_value (doc.get_tags_display ());

                builder.set_member_name ("pince-tags");
                builder.begin_array ();
                foreach (var tag in doc.tags) {
                    builder.add_string_value (tag);
                }
                builder.end_array ();
            }

            // Pince extension fields
            builder.set_member_name ("pince-path");
            builder.add_string_value (doc.path);

            if (doc.filetype.length > 0) {
                builder.set_member_name ("pince-filetype");
                builder.add_string_value (doc.filetype);
            }

            if (doc.date_added.length > 0) {
                builder.set_member_name ("pince-date-added");
                builder.add_string_value (doc.date_added);
            }

            builder.set_member_name ("pince-starred");
            builder.add_boolean_value (doc.starred);

            builder.set_member_name ("pince-reading-status");
            builder.add_string_value (doc.reading_status.to_string_value ());

            builder.end_object ();
        }
    }
}
