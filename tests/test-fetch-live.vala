/**
 * Live fetch test — makes real HTTP calls to verify the full pipeline.
 * Run manually: ./build/pince-fetch-test
 */

void test_openalex_doi_fetch () {
    var loop = new MainLoop ();
    var doc = new Pince.Document ();
    doc.doi = "10.22215/etd/2024-16003";

    Pince.OpenAlexClient.fetch_metadata.begin (doc, (obj, res) => {
        try {
            Pince.OpenAlexClient.fetch_metadata.end (res);
            print ("OpenAlex DOI fetch OK:\n");
            print ("  title: %s\n", doc.title);
            print ("  year: %s\n", doc.year);
            print ("  authors: %d\n", doc.authors.size);
            if (doc.authors.size > 0) print ("  first: %s\n", doc.authors[0]);
            print ("  type: %s\n", doc.entry_type);
            print ("  abstract length: %d\n", doc.abstract_text.length);
            assert_true (doc.title.length > 0);
            assert_true (doc.year == "2024");
            assert_true (doc.authors.size > 0);
        } catch (Error e) {
            Test.fail_printf ("OpenAlex DOI fetch failed: %s", e.message);
        }
        loop.quit ();
    });

    // Timeout after 20 seconds
    Timeout.add_seconds (20, () => {
        Test.fail_printf ("Timeout waiting for OpenAlex response");
        loop.quit ();
        return false;
    });

    loop.run ();
}

void test_openalex_doi_404 () {
    var loop = new MainLoop ();
    var doc = new Pince.Document ();
    doc.doi = "10.7717/peerj-cs.1092/supp-6";  // supplementary figure, not indexed

    Pince.OpenAlexClient.fetch_metadata.begin (doc, (obj, res) => {
        try {
            Pince.OpenAlexClient.fetch_metadata.end (res);
            Test.fail_printf ("Expected error for supplementary DOI, got success");
        } catch (Error e) {
            print ("OpenAlex 404 handled correctly: %s\n", e.message);
            assert_true (e.message.contains ("404") || e.message.contains ("status"));
        }
        loop.quit ();
    });

    Timeout.add_seconds (20, () => {
        Test.fail_printf ("Timeout");
        loop.quit ();
        return false;
    });

    loop.run ();
}

void test_crossref_doi_fetch () {
    var loop = new MainLoop ();
    var doc = new Pince.Document ();
    doc.doi = "10.22215/etd/2024-16003";

    Pince.CrossRefClient.fetch_metadata.begin (doc, (obj, res) => {
        try {
            Pince.CrossRefClient.fetch_metadata.end (res);
            print ("CrossRef DOI fetch OK:\n");
            print ("  title: %s\n", doc.title);
            print ("  year: '%s'\n", doc.year);
            print ("  authors: %d\n", doc.authors.size);
            if (doc.authors.size > 0) print ("  first: %s\n", doc.authors[0]);
            print ("  publisher: %s\n", doc.publisher);
            assert_true (doc.title.length > 0);
            assert_true (doc.year == "");  // CrossRef returns null date for this DOI
            assert_true (doc.authors.size > 0);
        } catch (Error e) {
            Test.fail_printf ("CrossRef DOI fetch failed: %s", e.message);
        }
        loop.quit ();
    });

    Timeout.add_seconds (20, () => {
        Test.fail_printf ("Timeout");
        loop.quit ();
        return false;
    });

    loop.run ();
}

void test_openalex_title_search () {
    var loop = new MainLoop ();
    var doc = new Pince.Document ();
    doc.title = "Deep Residual Learning for Image Recognition";

    Pince.OpenAlexClient.search_by_title.begin (doc, (obj, res) => {
        try {
            bool found = Pince.OpenAlexClient.search_by_title.end (res);
            print ("OpenAlex title search: found=%s\n", found.to_string ());
            print ("  title: %s\n", doc.title);
            print ("  year: %s\n", doc.year);
            print ("  doi: %s\n", doc.doi);
            print ("  authors: %d\n", doc.authors.size);
            assert_true (found);
            assert_true (doc.year == "2016");
        } catch (Error e) {
            Test.fail_printf ("OpenAlex title search failed: %s", e.message);
        }
        loop.quit ();
    });

    Timeout.add_seconds (20, () => {
        Test.fail_printf ("Timeout");
        loop.quit ();
        return false;
    });

    loop.run ();
}

void test_crossref_component_type () {
    // DOI 10.7717/peerj-cs.1092/supp-6 is a supplementary figure (type=component)
    // The fetch should succeed but return type=component
    var loop = new MainLoop ();
    var doc = new Pince.Document ();
    doc.doi = "10.7717/peerj-cs.1092/supp-6";

    Pince.CrossRefClient.fetch_metadata.begin (doc, (obj, res) => {
        try {
            Pince.CrossRefClient.fetch_metadata.end (res);
            print ("CrossRef component DOI:\n");
            print ("  title: %s\n", doc.title);
            print ("  type: %s\n", doc.entry_type);
            print ("  authors: %d\n", doc.authors.size);
            print ("  year: '%s'\n", doc.year);
            // Verify it's a component — app should detect this and try title search instead
            assert_true (doc.entry_type == "component");
        } catch (Error e) {
            Test.fail_printf ("CrossRef fetch failed: %s", e.message);
        }
        loop.quit ();
    });

    Timeout.add_seconds (20, () => {
        Test.fail_printf ("Timeout");
        loop.quit ();
        return false;
    });

    loop.run ();
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/pince/live/openalex-doi", test_openalex_doi_fetch);
    Test.add_func ("/pince/live/openalex-404", test_openalex_doi_404);
    Test.add_func ("/pince/live/crossref-doi", test_crossref_doi_fetch);
    Test.add_func ("/pince/live/openalex-title", test_openalex_title_search);
    Test.add_func ("/pince/live/crossref-component", test_crossref_component_type);
    return Test.run ();
}
