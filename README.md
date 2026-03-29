# Pince

Run without install.
```
git pull && meson setup --wipe build && meson compile -C build && meson test -C build -v && GSETTINGS_SCHEMA_DIR=build/data ./build/pince
```

Install and run.
```
git pull && meson setup build --prefix=$HOME/.local && meson compile -C build && meson install -C build && pince
```

A lightweight personal document library for GNOME.

Pince indexes your existing documents with metadata and tags, backed by
standard CSL JSON or BibTeX files. Files are never moved or copied — the
library is just a portable index you can sync anywhere.

## Features

- **Automatic metadata extraction** from PDFs (embedded DOI, XMP/Info dict)
- **CrossRef DOI lookup** for complete bibliographic data
- **Tag-based organization** with sidebar filtering
- **Full-text search** across titles, authors, and tags
- **Drag-and-drop** to add documents
- **Portable library files** — CSL JSON (.json) or BibTeX (.bib)
- **Auto-save** with 2-second debounce

## Building

### Dependencies

- GTK 4 (>= 4.12)
- Libadwaita (>= 1.4)
- Vala compiler
- Meson (>= 0.62)
- blueprint-compiler
- json-glib-1.0
- libsoup-3.0
- poppler-glib
- libgee-0.8

### Build from source

```bash
meson setup build
meson compile -C build
meson install -C build
```

### Flatpak

```bash
flatpak-builder --user --install --force-clean build-flatpak io.github.essicolo.Pince.json
```

## Architecture

```
src/
  main.vala                 Entry point
  application.vala          GApplication subclass
  window.vala               Main window with three-panel layout
  document.vala             Document data model
  library.vala              Library manager (load/save/filter)
  library-csl-json.vala     CSL JSON serialization
  library-bibtex.vala       BibTeX parser and writer
  metadata-extractor.vala   PDF/DOCX/ODT metadata extraction pipeline
  crossref-client.vala      CrossRef API client (libsoup3)
  document-row.vala         Document list row widget
  tag-row.vala              Tag sidebar row widget
  add-dialog.vala           Add document confirmation dialog
  preferences.vala          Preferences dialog
  utils.vala                Shared utilities

data/
  ui/window.blp             Main window Blueprint
  ui/document-row.blp       Document row Blueprint
  ui/add-dialog.blp         Add dialog Blueprint
  ui/preferences.blp        Preferences dialog Blueprint
  style.css                 Custom styles
```

## Library File Format

Pince uses standard CSL JSON as the default format, with `pince-path` and
`pince-tags` extension fields to track file locations and tags. BibTeX is
also supported, using the `keywords` field for tags and a custom `pince-path`
field for file paths.

## License

GPL-3.0-or-later
