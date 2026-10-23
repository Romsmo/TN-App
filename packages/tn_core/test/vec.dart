import 'dart:convert';
import 'dart:io';

/// Reads a test vector file from the export (`drive-core/vectors`), copied into `test/vectors`.
dynamic vec(String name) => jsonDecode(File('test/vectors/$name.json').readAsStringSync());

/// The app's texts (German and English tables), read from the app's asset files.
Map<String, String> textTable(String lang) =>
    (jsonDecode(File('../../assets/texts/$lang.json').readAsStringSync()) as Map).cast<String, String>();
