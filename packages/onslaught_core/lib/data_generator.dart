/// Tooling-only library: builds the `assets/data` documents from the
/// committed legacy reference table (`docs/legacy/legacy_values.json`) and
/// the `l10n/` string tables, and writes typed game data back out as those
/// documents. Used by `tool/gen_data_from_legacy.dart`, the data snapshot
/// and round-trip tests; the game never imports it.
library;

export 'src/data_gen/game_documents.dart';
export 'src/data_gen/game_documents_generator.dart';
