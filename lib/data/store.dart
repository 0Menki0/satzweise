import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Speicherort für den App-Stand. Die App hält alles als ein JSON-Dokument;
/// für die zu erwartende Datenmenge (einige hundert Trainings) reicht das und
/// ein laufendes Training übersteht so jeden Neustart.
abstract class Store {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> data);
}

class MemoryStore implements Store {
  MemoryStore([this.data]);
  Map<String, dynamic>? data;

  @override
  Future<Map<String, dynamic>?> load() async =>
      data == null ? null : jsonDecode(jsonEncode(data)) as Map<String, dynamic>;

  @override
  Future<void> save(Map<String, dynamic> d) async => data = jsonDecode(jsonEncode(d)) as Map<String, dynamic>;
}

class FileStore implements Store {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/satzweise.json');
  }

  @override
  Future<Map<String, dynamic>?> load() async {
    final f = await _file();
    if (!await f.exists()) return null;
    return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  }

  /// Schreibt zuerst in eine Zwischendatei und benennt sie dann um, damit
  /// ein Absturz beim Schreiben keine halbe Datei hinterlässt.
  @override
  Future<void> save(Map<String, dynamic> data) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }
}
