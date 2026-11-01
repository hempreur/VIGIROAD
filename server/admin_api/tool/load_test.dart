// Test de charge : N utilisateurs simultanés (inscription, connexion,
// battements de cœur) et un administrateur qui consulte le tableau de bord.
//   dart run tool/load_test.dart https://localhost <utilisateurs> <battements>
// Échoue si une requête échoue ou si la latence dépasse les seuils.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

final lat = <String, List<int>>{};
var errors = 0;

Future<http.Response> timed(String kind, Future<http.Response> Function() f) async {
  final sw = Stopwatch()..start();
  try {
    final r = await f();
    (lat[kind] ??= []).add(sw.elapsedMilliseconds);
    if (r.statusCode >= 400) {
      errors++;
      stderr.writeln('$kind : HTTP ${r.statusCode} ${r.body}');
    }
    return r;
  } catch (e) {
    errors++;
    stderr.writeln('$kind : $e');
    rethrow;
  }
}

int pct(List<int> v, double p) {
  final s = [...v]..sort();
  return s[((s.length - 1) * p).round()];
}

Future<void> main(List<String> args) async {
  final base = Uri.parse(args.isNotEmpty ? args[0] : 'https://localhost');
  final users = args.length > 1 ? int.parse(args[1]) : 50;
  final beats = args.length > 2 ? int.parse(args[2]) : 20;
  final key = Platform.environment['VR_APP_KEY']!;
  final adminToken = Platform.environment['VR_ADMIN_TOKEN'];
  final client = IOClient(
    HttpClient()
      ..badCertificateCallback = ((c, h, p) => h == 'localhost')
      ..maxConnectionsPerHost = 64,
  );
  final run = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  const json = {'content-type': 'application/json'};
  final sw = Stopwatch()..start();

  Future<void> user(int i) async {
    final r = await timed(
      'inscription',
      () => client.post(
        base.replace(path: '/v1/account/register'),
        headers: {...json, 'x-api-key': key, 'x-forwarded-for': '198.18.${i ~/ 250}.${i % 250}'},
        body: jsonEncode({'pseudonym': 'charge_${run}_$i', 'password': 'Charge2026x', 'appVersion': '1.4.0'}),
      ),
    );
    final token = (jsonDecode(r.body) as Map<String, dynamic>)['token'] as String;
    for (var b = 0; b < beats; b++) {
      await timed(
        'battement',
        () => client.post(
          base.replace(path: '/v1/account/heartbeat'),
          headers: {...json, 'authorization': 'Bearer $token'},
          body: '{"appVersion":"1.4.0"}',
        ),
      );
      await Future<void>.delayed(Duration(milliseconds: 50 + (i * 7) % 100));
    }
  }

  var adminRunning = true;
  Future<void> admin() async {
    if (adminToken == null) return;
    while (adminRunning) {
      for (final p in ['/admin/dashboard', '/admin/users', '/admin/sessions?state=online', '/admin/stats/activity?period=24h']) {
        await timed('administration', () => client.get(base.replace(path: p.split('?').first, query: p.contains('?') ? p.split('?')[1] : null), headers: {'authorization': 'Bearer $adminToken'}));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  final a = admin();
  await Future.wait([for (var i = 0; i < users; i++) user(i)]);
  adminRunning = false;
  await a;
  final total = lat.values.fold<int>(0, (s, v) => s + v.length);
  stdout.writeln('Test de charge : $users utilisateurs simultanés, $total requêtes en ${sw.elapsed.inSeconds} s, $errors erreur(s)');
  for (final e in lat.entries) {
    stdout.writeln('  ${e.key.padRight(15)} n=${e.value.length.toString().padLeft(5)}  p50=${pct(e.value, .5)} ms  p95=${pct(e.value, .95)} ms  max=${pct(e.value, 1)} ms');
  }
  final p95Beat = pct(lat['battement']!, .95);
  final ok = errors == 0 && p95Beat < 500;
  stdout.writeln(ok ? 'Seuils respectés (0 erreur, battement p95 < 500 ms).' : 'Seuils dépassés.');
  exit(ok ? 0 : 1);
}
