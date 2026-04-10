/**
 * Test PDF title extraction with a real PDF file.
 * Run: ./build/pince-pdf-title-test
 */

void test_pdf_title_extraction () {
    var path = "example_library_test/bfcd8a2ea73c_Williams-Jones-2022a.pdf";

    if (!FileUtils.test (path, FileTest.EXISTS)) {
        Test.skip ("PDF test file not found: %s".printf (path));
        return;
    }

    try {
        var file_uri = File.new_for_path (path).get_uri ();
        var pdf_doc = new Poppler.Document.from_file (file_uri, null);
        var title = Pince.MetadataExtractor.extract_title_from_pdf_text (pdf_doc);

        print ("Extracted title: %s\n", title ?? "(null)");

        assert_nonnull (title);
        // The real title should contain "Cobalt" and "Constraints"
        assert_true (title.down ().contains ("cobalt") || title.down ().contains ("constraints"));
        assert_true (title.length > 20);
    } catch (Error e) {
        Test.fail_printf ("PDF title extraction failed: %s", e.message);
    }
}

void test_other_pdfs () {
    // Test with the Shawwa thesis
    var path = "example_library_test/shawwa--nabil-allam--dynamic-environmental-change-at-the-cusp-of-the-great-oxidation-event-the-gowgandalorrain-formation-transition-cobalt.pdf";

    if (!FileUtils.test (path, FileTest.EXISTS)) {
        Test.skip ("PDF test file not found");
        return;
    }

    try {
        var file_uri = File.new_for_path (path).get_uri ();
        var pdf_doc = new Poppler.Document.from_file (file_uri, null);
        var title = Pince.MetadataExtractor.extract_title_from_pdf_text (pdf_doc);

        print ("Shawwa thesis title: %s\n", title ?? "(null)");

        if (title != null) {
            assert_true (title.length > 10);
        }
    } catch (Error e) {
        Test.fail_printf ("PDF title extraction failed: %s", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/pince/pdf/title-extraction", test_pdf_title_extraction);
    Test.add_func ("/pince/pdf/other-pdfs", test_other_pdfs);
    return Test.run ();
}
