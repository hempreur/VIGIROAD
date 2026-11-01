import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;
import 'package:vigiroad_admin_api/admin_api.dart';

Future<void> main() async {
  final config = AdminConfig(Platform.environment);
  try {
    config.masterKey;
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }

  // PostgreSQL peut démarrer après l'API : nouvelles tentatives pendant 2 min.
  late Db db;
  for (var attempt = 1;; attempt++) {
    try {
      db = await Db.connect(
        host: config.dbHost,
        port: config.dbPort,
        database: config.dbName,
        user: config.dbUser,
        password: config.dbPassword,
      );
      final applied = await db.migrate(config.migrationsDir);
      if (applied.isNotEmpty) stdout.writeln('Migrations appliquées : ${applied.join(', ')}');
      break;
    } catch (e) {
      if (attempt >= 40) {
        stderr.writeln('PostgreSQL injoignable : $e');
        exit(70);
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  final ctx = AppContext(config: config, db: db, geo: GeoIp.empty());
  // Base de géolocalisation chargée en arrière-plan, rechargée quand le
  // fichier est renouvelé (mise à jour mensuelle par install.sh).
  DateTime? geoStamp;
  Future<void> loadGeo() async {
    try {
      final f = File(config.geoIpFile);
      final stamp = await f.exists() ? await f.lastModified() : null;
      if (stamp == geoStamp) return;
      geoStamp = stamp;
      final g = await GeoIp.load(config.geoIpFile);
      ctx.geo = g;
      stdout.writeln(g.available ? 'GeoIP : ${g.ranges} plages' : 'GeoIP absente (${config.geoIpFile})');
    } catch (e) {
      stderr.writeln('GeoIP : $e');
    }
  }

  unawaited(loadGeo());
  Timer.periodic(const Duration(hours: 6), (_) => unawaited(loadGeo()));

  final api = AdminApi(ctx);
  if (config.backgroundJobs) api.startJobs();
  final server = await io.serve(api.handler, InternetAddress.anyIPv4, config.port);
  server.idleTimeout = const Duration(minutes: 2);
  stdout.writeln('API d\'administration VIGIROAD ${AdminApi.version} : port ${server.port}');
  if (config.setupToken != null) stdout.writeln('Création du premier administrateur possible (jeton d\'installation).');

  for (final s in [ProcessSignal.sigint, if (!Platform.isWindows) ProcessSignal.sigterm]) {
    s.watch().listen((_) async {
      api.stopJobs();
      await server.close(force: true);
      await db.close();
      exit(0);
    });
  }
}
