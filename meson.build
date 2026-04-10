project(
  'pince',
  ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 1.4.0',
  default_options: [
    'warning_level=2',
    'werror=false',
  ],
)

app_id = 'io.github.essicolo.Pince'
gettext_package = 'pince'

# i18n
add_project_arguments(
  '-DGETTEXT_PACKAGE="' + gettext_package + '"',
  language: 'c',
)

subdir('po')

# Dependencies
gtk4_dep = dependency('gtk4', version: '>= 4.12')
adw_dep = dependency('libadwaita-1', version: '>= 1.4')
json_dep = dependency('json-glib-1.0')
soup_dep = dependency('libsoup-3.0')
poppler_dep = dependency('poppler-glib')
gio_dep = dependency('gio-2.0')
gee_dep = dependency('gee-0.8')

# Blueprint compiler
blueprint_compiler = find_program('blueprint-compiler', required: true)

# Blueprint files → .ui files in build dir
blueprints = files(
  'data/ui/window.blp',
  'data/ui/document-row.blp',
  'data/ui/add-dialog.blp',
  'data/ui/preferences.blp',
)

blueprint_targets = []
foreach bp : blueprints
  blueprint_targets += custom_target(
    bp.full_path().underscorify(),
    input: bp,
    output: '@BASENAME@.ui',
    command: [blueprint_compiler, 'compile', '--output', '@OUTPUT@', '@INPUT@'],
  )
endforeach

# GResource — .ui files are found via source_dir pointing to build dir
gnome = import('gnome')

resources = gnome.compile_resources(
  'pince-resources',
  'data/pince.gresource.xml',
  dependencies: blueprint_targets,
  source_dir: [meson.current_build_dir(), 'data'],
)

# Vala sources
sources = files(
  'src/main.vala',
  'src/application.vala',
  'src/window.vala',
  'src/document.vala',
  'src/library.vala',
  'src/library-bibtex.vala',
  'src/library-csl-json.vala',
  'src/metadata-extractor.vala',
  'src/crossref-client.vala',
  'src/openalex-client.vala',
  'src/document-row.vala',
  'src/tag-row.vala',
  'src/add-dialog.vala',
  'src/preferences.vala',
  'src/utils.vala',
  'src/citation-formatter.vala',
  'src/recent-libraries.vala',
)

executable(
  'pince',
  sources,
  resources,
  dependencies: [
    gtk4_dep,
    adw_dep,
    json_dep,
    soup_dep,
    poppler_dep,
    gio_dep,
    gee_dep,
  ],
  install: true,
)

# Data files
install_data(
  'data/icons/hicolor/scalable/apps/io.github.essicolo.Pince.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps',
)

install_data(
  'data/io.github.essicolo.Pince.desktop',
  install_dir: get_option('datadir') / 'applications',
)

install_data(
  'data/io.github.essicolo.Pince.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo',
)

install_data(
  'data/io.github.essicolo.Pince.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

# Compile GSettings schemas in source data/ dir for uninstalled runs
# This way GSETTINGS_SCHEMA_DIR=data works from the source tree
run_command(
  find_program('glib-compile-schemas'),
  meson.current_source_dir() / 'data',
  check: false,
)

# Tests
test_sources = files(
  'src/document.vala',
  'src/library.vala',
  'src/library-csl-json.vala',
  'src/library-bibtex.vala',
  'src/metadata-extractor.vala',
  'src/crossref-client.vala',
  'src/openalex-client.vala',
  'src/utils.vala',
  'src/citation-formatter.vala',
  'src/recent-libraries.vala',
)

test_exe = executable(
  'pince-test',
  'tests/test-library.vala',
  test_sources,
  dependencies: [
    gtk4_dep,
    adw_dep,
    json_dep,
    soup_dep,
    poppler_dep,
    gio_dep,
    gee_dep,
  ],
  install: false,
)

test('library-tests', test_exe,
  workdir: meson.current_source_dir(),
)

# PDF title extraction test
pdf_test_exe = executable(
  'pince-pdf-title-test',
  'tests/test-pdf-title.vala',
  test_sources,
  dependencies: [
    gtk4_dep,
    adw_dep,
    json_dep,
    soup_dep,
    poppler_dep,
    gio_dep,
    gee_dep,
  ],
  install: false,
)

# Live fetch tests (require network, not run by default)
fetch_test_exe = executable(
  'pince-fetch-test',
  'tests/test-fetch-live.vala',
  test_sources,
  dependencies: [
    gtk4_dep,
    adw_dep,
    json_dep,
    soup_dep,
    poppler_dep,
    gio_dep,
    gee_dep,
  ],
  install: false,
)

gnome.post_install(
  glib_compile_schemas: true,
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
