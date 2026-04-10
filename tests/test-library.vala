/**
 * Unit tests for Pince's data layer.
 */

const string FIXTURES_DIR = "tests/fixtures";

void test_csl_json_load () {
    var lib = new Pince.Library ();
    try {
        lib.load (Path.build_filename (FIXTURES_DIR, "sample.json"));
    } catch (Error e) {
        Test.fail_printf ("Failed to load CSL JSON: %s", e.message);
        return;
    }

    assert_true (lib.documents.size == 4);

    var doc0 = lib.documents[0];
    assert_true (doc0.title == "Deep Residual Learning for Image Recognition");
    assert_true (doc0.authors.size == 4);
    assert_true (doc0.authors[0] == "He, Kaiming");
    assert_true (doc0.authors[3] == "Sun, Jian");
    assert_true (doc0.year == "2016");
    assert_true (doc0.doi == "10.1109/CVPR.2016.90");
    assert_true (doc0.tags.contains ("deep learning"));
    assert_true (doc0.tags.contains ("computer vision"));
    assert_true (doc0.filetype == "pdf");
}

void test_csl_json_roundtrip () {
    var lib = new Pince.Library ();
    try {
        // sample.json is old plain-array format — tests backward compat
        lib.load (Path.build_filename (FIXTURES_DIR, "sample.json"));
    } catch (Error e) {
        Test.fail_printf ("Load failed: %s", e.message);
        return;
    }

    var tmp_path = Path.build_filename (Environment.get_tmp_dir (), "pince-test-roundtrip.json");
    try {
        // Saves in new {pince: {...}, items: [...]} format
        lib.save_as (tmp_path, Pince.LibraryFormat.CSL_JSON);
    } catch (Error e) {
        Test.fail_printf ("Save failed: %s", e.message);
        return;
    }

    var lib2 = new Pince.Library ();
    try {
        lib2.load (tmp_path);
    } catch (Error e) {
        Test.fail_printf ("Reload failed: %s", e.message);
        return;
    }

    // Verify metadata survived roundtrip
    assert_true (lib2.pince_version == "0.1.0");
    assert_true (lib2.library_author.length > 0);
    assert_true (lib2.created.length > 0);
    assert_true (lib2.updated.length > 0);

    assert_true (lib2.documents.size == 4);
    assert_true (lib2.documents[0].title == "Deep Residual Learning for Image Recognition");
    assert_true (lib2.documents[0].authors.size == 4);
    assert_true (lib2.documents[1].authors.size > 0);
    assert_true (lib2.documents[2].note == "Classic reference, volume 1 covers fundamental algorithms.");

    FileUtils.remove (tmp_path);
}

void test_bibtex_load () {
    var lib = new Pince.Library ();
    try {
        lib.load (Path.build_filename (FIXTURES_DIR, "sample.bib"));
    } catch (Error e) {
        Test.fail_printf ("Failed to load BibTeX: %s", e.message);
        return;
    }

    assert_true (lib.documents.size == 3);
    assert_true (lib.documents[0].id == "he2016deep");
    assert_true (lib.documents[0].entry_type == "article");
    assert_true (lib.documents[0].title == "Deep Residual Learning for Image Recognition");
    assert_true (lib.documents[0].authors.size == 4);
    assert_true (lib.documents[0].authors[0] == "He, Kaiming");
}

void test_bibtex_roundtrip () {
    var lib = new Pince.Library ();
    try {
        lib.load (Path.build_filename (FIXTURES_DIR, "sample.bib"));
    } catch (Error e) {
        Test.fail_printf ("Load failed: %s", e.message);
        return;
    }

    var tmp_path = Path.build_filename (Environment.get_tmp_dir (), "pince-test-roundtrip.bib");
    try {
        lib.save_as (tmp_path, Pince.LibraryFormat.BIBTEX);
    } catch (Error e) {
        Test.fail_printf ("Save failed: %s", e.message);
        return;
    }

    var lib2 = new Pince.Library ();
    try {
        lib2.load (tmp_path);
    } catch (Error e) {
        Test.fail_printf ("Reload failed: %s", e.message);
        return;
    }

    assert_true (lib2.documents.size == 3);
    assert_true (lib2.documents[0].title == "Deep Residual Learning for Image Recognition");
    assert_true (lib2.documents[2].note == "Classic reference, volume 1 covers fundamental algorithms.");

    FileUtils.remove (tmp_path);
}

void test_document_search () {
    var doc = new Pince.Document ();
    doc.title = "Attention Is All You Need";
    doc.authors.add ("Vaswani, Ashish");
    doc.tags.add ("transformers");
    doc.year = "2017";

    assert_true (doc.matches_search ("attention"));
    assert_true (doc.matches_search ("Vaswani"));
    assert_true (doc.matches_search ("transformers"));
    assert_true (doc.matches_search ("2017"));
    assert_false (doc.matches_search ("convolutional"));
}

void test_library_filter () {
    var lib = new Pince.Library ();
    try {
        lib.load (Path.build_filename (FIXTURES_DIR, "sample.json"));
    } catch (Error e) {
        Test.fail_printf ("Load failed: %s", e.message);
        return;
    }

    var deep = lib.filter (null, "deep learning");
    assert_true (deep.size == 2);

    var knuth = lib.filter ("Knuth", null);
    assert_true (knuth.size == 1);
    assert_true (knuth[0].title == "The Art of Computer Programming");

    var dl_attention = lib.filter ("attention", "deep learning");
    assert_true (dl_attention.size == 1);

    var none = lib.filter ("nonexistent_query_xyz", null);
    assert_true (none.size == 0);
}

void test_library_tags () {
    var lib = new Pince.Library ();
    try {
        lib.load (Path.build_filename (FIXTURES_DIR, "sample.json"));
    } catch (Error e) {
        Test.fail_printf ("Load failed: %s", e.message);
        return;
    }

    var tags = lib.get_all_tags ();
    assert_true (tags.contains ("deep learning"));
    assert_true (tags.contains ("computer vision"));
    assert_true (tags.contains ("transformers"));
    assert_true (tags.contains ("algorithms"));
    assert_true (tags.contains ("agriculture"));
}

void test_document_authors_string () {
    var doc = new Pince.Document ();

    // set_authors_from_string splits on " and " — each part is one author
    doc.set_authors_from_string ("He, Kaiming and Zhang, Xiangyu and Ren, Shaoqing");
    assert_true (doc.authors.size == 3);
    assert_true (doc.authors[0] == "He, Kaiming");
    assert_true (doc.authors[1] == "Zhang, Xiangyu");
    assert_true (doc.authors[2] == "Ren, Shaoqing");

    // Single author
    doc.set_authors_from_string ("Knuth, Donald E.");
    assert_true (doc.authors.size == 1);
    assert_true (doc.authors[0] == "Knuth, Donald E.");

    // Empty input
    doc.set_authors_from_string ("");
    assert_true (doc.authors.size == 0);

    // get_authors_display re-joins with " and "
    doc.set_authors_from_string ("Smith, John and Doe, Jane");
    assert_true (doc.get_authors_display () == "Smith, John and Doe, Jane");
}

void test_author_plausibility () {
    // Usernames should be rejected
    assert_false (Pince.MetadataExtractor.is_plausible_author ("olgav"));
    assert_false (Pince.MetadataExtractor.is_plausible_author ("admin"));
    assert_false (Pince.MetadataExtractor.is_plausible_author ("user123"));
    assert_false (Pince.MetadataExtractor.is_plausible_author ("root"));
    assert_false (Pince.MetadataExtractor.is_plausible_author ("a"));

    // Emails should be rejected
    assert_false (Pince.MetadataExtractor.is_plausible_author ("john@example.com"));

    // Real names should pass
    assert_true (Pince.MetadataExtractor.is_plausible_author ("Smith, John"));
    assert_true (Pince.MetadataExtractor.is_plausible_author ("John Smith"));
    assert_true (Pince.MetadataExtractor.is_plausible_author ("Jean-Pierre Dupont"));
    assert_true (Pince.MetadataExtractor.is_plausible_author ("O'Brien, Mary"));

    // Single capitalized names (mononyms) should pass
    assert_true (Pince.MetadataExtractor.is_plausible_author ("Aristotle"));
    assert_true (Pince.MetadataExtractor.is_plausible_author ("Madonna"));
}

void test_clean_author_string () {
    // Single username -> empty
    assert_true (Pince.MetadataExtractor.clean_author_string ("olgav") == "");

    // Real author string -> preserved
    var result1 = Pince.MetadataExtractor.clean_author_string ("Smith, John");
    assert_true (result1 == "Smith, John");

    // Semicolon-separated (common in PDF metadata)
    var result2 = Pince.MetadataExtractor.clean_author_string ("Smith, John; Doe, Jane");
    assert_true (result2.contains ("Smith, John"));
    assert_true (result2.contains ("Doe, Jane"));

    // Filter garbage from mixed list
    var result3 = Pince.MetadataExtractor.clean_author_string ("admin; Smith, John");
    assert_true (result3 == "Smith, John");
}

void test_title_plausibility () {
    assert_true (Pince.MetadataExtractor.is_plausible_title ("Attention Is All You Need"));
    assert_true (Pince.MetadataExtractor.is_plausible_title ("Deep Learning for Computer Vision"));

    assert_false (Pince.MetadataExtractor.is_plausible_title (""));
    assert_false (Pince.MetadataExtractor.is_plausible_title ("ab"));
    assert_false (Pince.MetadataExtractor.is_plausible_title ("document.pdf"));
    assert_false (Pince.MetadataExtractor.is_plausible_title ("Microsoft Word - Document1.doc"));
    assert_false (Pince.MetadataExtractor.is_plausible_title ("Untitled"));
}

void test_filename_parsing () {
    // "Author Year Title" pattern
    var doc1 = new Pince.Document.from_file ("/tmp/Smith 2020 Deep learning in ecology.pdf");
    Pince.MetadataExtractor.extract_from_filename (doc1);
    assert_true (doc1.title == "Deep learning in ecology");
    assert_true (doc1.year == "2020");
    assert_true (doc1.authors.size > 0);

    // "Author_et_Year_Title" pattern — "et" should become "and"
    var doc2 = new Pince.Document.from_file ("/tmp/Williams_et_Jones_2022_Constraints_on_things.pdf");
    Pince.MetadataExtractor.extract_from_filename (doc2);
    assert_true (doc2.year == "2022");
    assert_true (doc2.title == "Constraints on things");

    // Plain filename (no year pattern)
    var doc3 = new Pince.Document.from_file ("/tmp/some_random_document.pdf");
    Pince.MetadataExtractor.extract_from_filename (doc3);
    assert_true (doc3.title == "some random document");
}

void test_csl_json_null_date_parts () {
    // CrossRef API can return null or 0 in date-parts, e.g. [[null]] or [[0]]
    // This must not crash (was causing json_array_get_int_element assertion failure)
    var json = """
    {
      "pince": { "version": "0.1.0", "author": "", "created": "", "updated": "" },
      "items": [
        {
          "id": "null-year",
          "type": "article-journal",
          "title": "Paper with null date",
          "issued": { "date-parts": [[null]] },
          "pince-path": "",
          "pince-starred": false,
          "pince-reading-status": "unread"
        },
        {
          "id": "string-year",
          "type": "article-journal",
          "title": "Paper with string date",
          "issued": { "date-parts": [["2021"]] },
          "pince-path": "",
          "pince-starred": false,
          "pince-reading-status": "unread"
        },
        {
          "id": "zero-year",
          "type": "article-journal",
          "title": "Paper with year 0",
          "issued": { "date-parts": [[0]] },
          "pince-path": "",
          "pince-starred": false,
          "pince-reading-status": "unread"
        }
      ]
    }
    """;

    var tmp_path = Path.build_filename (Environment.get_tmp_dir (), "pince-test-null-date.json");
    try {
        FileUtils.set_contents (tmp_path, json);
    } catch (Error e) {
        Test.fail_printf ("Write failed: %s", e.message);
        return;
    }

    var lib = new Pince.Library ();
    try {
        lib.load (tmp_path);
    } catch (Error e) {
        Test.fail_printf ("Load failed: %s", e.message);
        FileUtils.remove (tmp_path);
        return;
    }

    assert_true (lib.documents.size == 3);
    // Null date-parts should result in empty year, not a crash
    assert_true (lib.documents[0].year == "");
    // String year should be parsed
    assert_true (lib.documents[1].year == "2021");
    // Year 0 should be treated as unknown (empty)
    assert_true (lib.documents[2].year == "");

    FileUtils.remove (tmp_path);
}

void test_openalex_parse () {
    // Real OpenAlex response for thesis DOI 10.22215/etd/2024-16003
    var json = """{"id":"https://openalex.org/W4401632393","doi":"https://doi.org/10.22215/etd/2024-16003","title":"Dynamic Environmental Change at the Cusp of the Great Oxidation Event: The Gowganda-Lorrain Formation Transition, Cobalt Basin, Ontario and Quebec","display_name":"Dynamic Environmental Change at the Cusp of the Great Oxidation Event: The Gowganda-Lorrain Formation Transition, Cobalt Basin, Ontario and Quebec","publication_year":2024,"publication_date":"2024-01-01","type":"dissertation","authorships":[{"author_position":"first","author":{"id":"https://openalex.org/A5089161250","display_name":"Nabil A. Shawwa","orcid":"https://orcid.org/0000-0002-9854-0886"},"institutions":[],"countries":[],"is_corresponding":true,"raw_author_name":"Nabil Allam Shawwa","raw_affiliation_strings":[],"affiliations":[]}],"primary_location":{"id":"doi:10.22215/etd/2024-16003","is_oa":true,"landing_page_url":"https://doi.org/10.22215/etd/2024-16003","pdf_url":null,"source":null,"license":null,"license_id":null,"version":"publishedVersion","is_accepted":true,"is_published":true,"raw_source_name":"Carleton University","raw_type":"dissertation"},"biblio":{"volume":null,"issue":null,"first_page":null,"last_page":null},"abstract_inverted_index":{"The":[0,3],"Huronian":[1],"Supergroup,":[2],"early":[4],"one":[5]}}""";

    var doc = new Pince.Document ();
    doc.doi = "10.22215/etd/2024-16003";

    try {
        Pince.OpenAlexClient.parse_work (json, doc);
    } catch (Error e) {
        Test.fail_printf ("OpenAlex parse failed: %s", e.message);
        return;
    }

    assert_true (doc.title == "Dynamic Environmental Change at the Cusp of the Great Oxidation Event: The Gowganda-Lorrain Formation Transition, Cobalt Basin, Ontario and Quebec");
    assert_true (doc.year == "2024");
    assert_true (doc.authors.size == 1);
    assert_true (doc.authors[0] == "Shawwa, Nabil A.");
    assert_true (doc.entry_type == "dissertation");
    // Abstract reconstructed from inverted index
    assert_true (doc.abstract_text.contains ("The"));
    assert_true (doc.abstract_text.contains ("Huronian"));
}

void test_crossref_parse_null_date () {
    // Real CrossRef response for thesis DOI — date-parts is [[null]]
    var json = """{"status":"ok","message-type":"work","message":{"DOI":"10.22215/etd/2024-16003","type":"dissertation","title":["Dynamic Environmental Change"],"author":[{"given":"Nabil Allam","family":"Shawwa","sequence":"first"}],"issued":{"date-parts":[[null]]},"publisher":"Carleton University","URL":"https://doi.org/10.22215/etd/2024-16003"}}""";

    var doc = new Pince.Document ();
    doc.doi = "10.22215/etd/2024-16003";

    try {
        Pince.CrossRefClient.parse_crossref_response (json, doc);
    } catch (Error e) {
        Test.fail_printf ("CrossRef parse failed: %s", e.message);
        return;
    }

    assert_true (doc.title == "Dynamic Environmental Change");
    assert_true (doc.year == "");  // null date-parts → empty year, no crash
    assert_true (doc.authors.size == 1);
    assert_true (doc.authors[0] == "Shawwa, Nabil Allam");
    assert_true (doc.publisher == "Carleton University");
}

void test_doi_extraction () {
    var doi1 = Pince.MetadataExtractor.extract_doi_from_text (
        "This is a paper. https://doi.org/10.1038/nature12373 is the reference."
    );
    assert_nonnull (doi1);
    assert_true (doi1 == "10.1038/nature12373");

    var doi2 = Pince.MetadataExtractor.extract_doi_from_text (
        "See 10.1109/CVPR.2016.90."
    );
    assert_nonnull (doi2);
    assert_true (doi2 == "10.1109/CVPR.2016.90");

    var doi3 = Pince.MetadataExtractor.extract_doi_from_text (
        "This text has no DOI in it at all."
    );
    assert_true (doi3 == null);
}

void test_doi_validation () {
    // Valid DOIs
    assert_true (Pince.CrossRefClient.is_valid_doi ("10.1038/nature12373"));
    assert_true (Pince.CrossRefClient.is_valid_doi ("10.1109/CVPR.2016.90"));
    assert_true (Pince.CrossRefClient.is_valid_doi ("10.48550/arXiv.1706.03762"));
    assert_true (Pince.CrossRefClient.is_valid_doi ("10.1007/978-3-030-58452-8_13"));

    // Invalid DOIs — should be rejected before any network request
    assert_false (Pince.CrossRefClient.is_valid_doi (""));
    assert_false (Pince.CrossRefClient.is_valid_doi ("hello"));
    assert_false (Pince.CrossRefClient.is_valid_doi ("11.1234/test"));
    assert_false (Pince.CrossRefClient.is_valid_doi ("10.1234"));  // no slash
    assert_false (Pince.CrossRefClient.is_valid_doi ("10.12/a<script>"));  // injection
    assert_false (Pince.CrossRefClient.is_valid_doi ("10.12/a\"b"));
    assert_false (Pince.CrossRefClient.is_valid_doi ("10.12/a\\b"));
    assert_false (Pince.CrossRefClient.is_valid_doi ("10.12/a\nb"));
}

void test_cross_format_conversion () {
    var lib = new Pince.Library ();
    try {
        lib.load (Path.build_filename (FIXTURES_DIR, "sample.json"));
    } catch (Error e) {
        Test.fail_printf ("Load failed: %s", e.message);
        return;
    }

    var tmp_path = Path.build_filename (Environment.get_tmp_dir (), "pince-test-convert.bib");
    try {
        lib.save_as (tmp_path, Pince.LibraryFormat.BIBTEX);
    } catch (Error e) {
        Test.fail_printf ("Convert-save failed: %s", e.message);
        return;
    }

    var lib2 = new Pince.Library ();
    try {
        lib2.load (tmp_path);
    } catch (Error e) {
        Test.fail_printf ("Convert-reload failed: %s", e.message);
        return;
    }

    assert_true (lib2.documents.size == 4);
    assert_true (lib2.documents[0].title == "Deep Residual Learning for Image Recognition");
    assert_true (lib2.documents[0].doi == "10.1109/CVPR.2016.90");

    FileUtils.remove (tmp_path);
}

void test_duplicate_detection () {
    var lib = new Pince.Library ();

    // Add a document
    var doc1 = new Pince.Document ();
    doc1.title = "A Closed-form Equation for Predicting the Hydraulic Conductivity";
    doc1.doi = "10.2136/sssaj1980.03615995004400050002x";
    doc1.path = "/papers/vangenuchten1980.pdf";
    lib.add_document (doc1);

    // DOI duplicate
    var dup_doi = new Pince.Document ();
    dup_doi.title = "Different title";
    dup_doi.doi = "10.2136/sssaj1980.03615995004400050002x";
    assert_nonnull (lib.find_duplicate (dup_doi));

    // Path duplicate
    var dup_path = new Pince.Document ();
    dup_path.title = "Different title";
    dup_path.path = "/papers/vangenuchten1980.pdf";
    assert_nonnull (lib.find_duplicate (dup_path));

    // Title duplicate (fuzzy)
    var dup_title = new Pince.Document ();
    dup_title.title = "A closed-form equation for predicting the hydraulic conductivity";
    assert_nonnull (lib.find_duplicate (dup_title));

    // Not a duplicate
    var not_dup = new Pince.Document ();
    not_dup.title = "Something Completely Different About Soil";
    not_dup.doi = "10.9999/other";
    not_dup.path = "/papers/other.pdf";
    assert_true (lib.find_duplicate (not_dup) == null);

    // Similar prefix but different paper (Part I vs Part II) — NOT a duplicate
    var part2 = new Pince.Document ();
    part2.title = "A Closed-form Equation for Predicting the Hydraulic Conductivity: Part II";
    assert_true (lib.find_duplicate (part2) == null);
}

void test_find_all_duplicates () {
    var lib = new Pince.Library ();

    var doc1 = new Pince.Document ();
    doc1.title = "Paper Alpha About Deep Learning";
    doc1.doi = "10.1234/alpha";
    lib.add_document (doc1);

    var doc2 = new Pince.Document ();
    doc2.title = "Paper Alpha About Deep Learning (copy)";
    doc2.doi = "10.1234/alpha";
    lib.add_document (doc2);

    var doc3 = new Pince.Document ();
    doc3.title = "Unique Paper Beta";
    lib.add_document (doc3);

    var groups = lib.find_all_duplicates ();
    assert_true (groups.size == 1);
    assert_true (groups[0].size == 2);
}

void test_relative_path_storage () {
    var lib = new Pince.Library ();
    var tmp_path = Path.build_filename (Environment.get_tmp_dir (), "pince-test-lib", "library.json");

    // Create the directory
    var dir = File.new_for_path (Path.get_dirname (tmp_path));
    try { dir.make_directory_with_parents (null); } catch (Error e) {}

    try {
        lib.save_as (tmp_path, Pince.LibraryFormat.CSL_JSON);
    } catch (Error e) {
        Test.fail_printf ("Save failed: %s", e.message);
        return;
    }

    // Add a document with an absolute path under the library dir
    var doc = new Pince.Document ();
    doc.title = "Test";
    doc.path = Path.build_filename (Environment.get_tmp_dir (), "pince-test-lib", "papers", "test.pdf");
    lib.add_document (doc);

    // Path should be stored relative
    assert_true (doc.path == "papers/test.pdf");

    // Add a document from a completely different tree
    var doc2 = new Pince.Document ();
    doc2.title = "External";
    doc2.path = "/opt/some/other/place.pdf";
    lib.add_document (doc2);

    // Path outside the library tree stays absolute
    assert_true (doc2.path == "/opt/some/other/place.pdf");

    // Clean up
    FileUtils.remove (tmp_path);
    try { dir.delete (null); } catch (Error e) {}
}

void test_document_path_resolution () {
    var doc = new Pince.Document ();

    // Absolute path stays absolute
    doc.path = "/home/user/Documents/paper.pdf";
    assert_true (doc.get_resolved_path ("/home/user/lib") == "/home/user/Documents/paper.pdf");
    assert_true (doc.get_folder_path ("/home/user/lib") == "/home/user/Documents");

    // Relative path is resolved from library dir
    doc.path = "papers/smith2020.pdf";
    assert_true (doc.get_resolved_path ("/home/user/lib") == "/home/user/lib/papers/smith2020.pdf");
    assert_true (doc.get_folder_path ("/home/user/lib") == "/home/user/lib/papers");

    // Nested relative path
    doc.path = "biology/ecology/report.docx";
    assert_true (doc.get_resolved_path ("/data") == "/data/biology/ecology/report.docx");
    assert_true (doc.get_folder_path ("/data") == "/data/biology/ecology");
}

int main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/pince/csl-json/load", test_csl_json_load);
    Test.add_func ("/pince/csl-json/roundtrip", test_csl_json_roundtrip);
    Test.add_func ("/pince/bibtex/load", test_bibtex_load);
    Test.add_func ("/pince/bibtex/roundtrip", test_bibtex_roundtrip);
    Test.add_func ("/pince/document/search", test_document_search);
    Test.add_func ("/pince/library/filter", test_library_filter);
    Test.add_func ("/pince/library/tags", test_library_tags);
    Test.add_func ("/pince/document/authors-string", test_document_authors_string);
    Test.add_func ("/pince/library/duplicate-detection", test_duplicate_detection);
    Test.add_func ("/pince/library/find-all-duplicates", test_find_all_duplicates);
    Test.add_func ("/pince/library/relative-path-storage", test_relative_path_storage);
    Test.add_func ("/pince/document/path-resolution", test_document_path_resolution);
    Test.add_func ("/pince/csl-json/null-date-parts", test_csl_json_null_date_parts);
    Test.add_func ("/pince/fetch/openalex-parse", test_openalex_parse);
    Test.add_func ("/pince/fetch/crossref-null-date", test_crossref_parse_null_date);
    Test.add_func ("/pince/metadata/doi-validation", test_doi_validation);
    Test.add_func ("/pince/cross-format", test_cross_format_conversion);
    Test.add_func ("/pince/metadata/author-plausibility", test_author_plausibility);
    Test.add_func ("/pince/metadata/clean-author-string", test_clean_author_string);
    Test.add_func ("/pince/metadata/title-plausibility", test_title_plausibility);
    Test.add_func ("/pince/metadata/filename-parsing", test_filename_parsing);
    Test.add_func ("/pince/metadata/doi-extraction", test_doi_extraction);

    return Test.run ();
}
