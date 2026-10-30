import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Base SQLite chiffrée (SQLCipher, AES-256) de l'application.
///
/// La clé est générée aléatoirement au premier lancement et conservée dans
/// le trousseau sécurisé du système (Android Keystore / iOS Keychain) ;
/// elle ne quitte jamais l'appareil.
class VigiroadDatabase {
  VigiroadDatabase._(this.db);

  final Database db;

  static const _keyName = 'vigiroad_db_key_v1';
  static const fileName = 'vigiroad.db';
  static const version = 1;

  static Future<VigiroadDatabase> open({FlutterSecureStorage storage = const FlutterSecureStorage()}) async {
    var key = await storage.read(key: _keyName);
    if (key == null) {
      final rnd = Random.secure();
      key = base64UrlEncode(List<int>.generate(32, (_) => rnd.nextInt(256)));
      await storage.write(key: _keyName, value: key);
    }
    final path = p.join(await getDatabasesPath(), fileName);
    final db = await openDatabase(
      path,
      password: key,
      version: version,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE watchlist (
            plate TEXT PRIMARY KEY,
            country TEXT NOT NULL,
            category TEXT NOT NULL,
            priority INTEGER NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            source TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE detections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            plate TEXT NOT NULL,
            display TEXT NOT NULL,
            country TEXT NOT NULL,
            category TEXT NOT NULL,
            priority INTEGER NOT NULL,
            confidence REAL NOT NULL,
            at INTEGER NOT NULL,
            lat REAL,
            lng REAL
          )''');
        await db.execute('CREATE INDEX detections_at ON detections(at DESC)');
      },
    );
    return VigiroadDatabase._(db);
  }

  Future<void> close() => db.close();
}
