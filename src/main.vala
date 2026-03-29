int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "");
    Intl.bindtextdomain ("pince", null);
    Intl.bind_textdomain_codeset ("pince", "UTF-8");
    Intl.textdomain ("pince");

    var app = new Pince.Application ();
    return app.run (args);
}
