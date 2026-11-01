import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class DockerException implements Exception {
  DockerException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'Docker $status : $message';
}

/// Client minimal de l'API Docker Engine par le socket Unix. Seules des
/// lectures et les opérations autorisées par [ContainerPolicy] sont exposées
/// par l'agent ; le socket lui-même n'est jamais accessible depuis le réseau.
class DockerClient {
  DockerClient({this.socketPath = '/var/run/docker.sock'}) {
    _http.connectionFactory = (uri, proxyHost, proxyPort) =>
        Socket.startConnect(InternetAddress(socketPath, type: InternetAddressType.unix), 0);
    _http.connectionTimeout = const Duration(seconds: 5);
  }

  final String socketPath;
  final _http = HttpClient();

  Future<(int, List<int>)> _raw(String method, String path, {Duration timeout = const Duration(seconds: 20)}) async {
    final req = await _http.openUrl(method, Uri.parse('http://docker$path'));
    final res = await req.close().timeout(timeout);
    final bytes = await res.fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d)).timeout(timeout);
    return (res.statusCode, bytes.takeBytes());
  }

  Future<Object?> json(String method, String path, {Duration timeout = const Duration(seconds: 20)}) async {
    final (status, body) = await _raw(method, path, timeout: timeout);
    if (status >= 400) {
      var msg = utf8.decode(body, allowMalformed: true);
      try {
        msg = (jsonDecode(msg) as Map<String, dynamic>)['message'] as String? ?? msg;
      } catch (_) {}
      throw DockerException(status, msg);
    }
    if (body.isEmpty) return null;
    return jsonDecode(utf8.decode(body));
  }

  Future<Map<String, dynamic>> version() async => await json('GET', '/version') as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> containers() async =>
      (await json('GET', '/containers/json?all=true') as List<dynamic>).cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> inspect(String id) async =>
      await json('GET', '/containers/${Uri.encodeComponent(id)}/json') as Map<String, dynamic>;

  /// Statistiques instantanées (deux mesures prises par Docker à ~1 s).
  Future<Map<String, dynamic>> stats(String id) async =>
      await json('GET', '/containers/${Uri.encodeComponent(id)}/stats?stream=false', timeout: const Duration(seconds: 10))
          as Map<String, dynamic>;

  Future<void> action(String id, String action) async {
    final timeout = action == 'start' ? '' : '?t=20';
    await json('POST', '/containers/${Uri.encodeComponent(id)}/$action$timeout', timeout: const Duration(seconds: 60));
  }

  /// Dernières lignes des journaux (flux stdout/stderr démultiplexés).
  Future<List<Map<String, String>>> logs(String id, {int tail = 200, bool tty = false}) async {
    final (status, body) = await _raw(
      'GET',
      '/containers/${Uri.encodeComponent(id)}/logs?stdout=1&stderr=1&timestamps=1&tail=$tail',
    );
    if (status >= 400) throw DockerException(status, utf8.decode(body, allowMalformed: true));
    return demuxLogs(body, tty: tty);
  }

  Future<List<Map<String, dynamic>>> volumes() async {
    final r = await json('GET', '/volumes') as Map<String, dynamic>;
    return ((r['Volumes'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> networks() async =>
      (await json('GET', '/networks') as List<dynamic>).cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> images() async =>
      (await json('GET', '/images/json') as List<dynamic>).cast<Map<String, dynamic>>();

  /// Taille des volumes (calcul Docker, peut prendre quelques secondes).
  Future<Map<String, int>> volumeSizes() async {
    try {
      final r = await json('GET', '/system/df?type=volume', timeout: const Duration(seconds: 30)) as Map<String, dynamic>;
      return {
        for (final v in ((r['Volumes'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>())
          v['Name'] as String: ((v['UsageData'] as Map<String, dynamic>?)?['Size'] as num?)?.toInt() ?? -1,
      };
    } catch (_) {
      return const {};
    }
  }

  void close() => _http.close(force: true);
}

/// Démultiplexe le format de journaux Docker (en-tête de 8 octets par bloc
/// quand le conteneur n'a pas de terminal).
List<Map<String, String>> demuxLogs(List<int> body, {bool tty = false}) {
  final out = <Map<String, String>>[];
  void addText(String stream, String text) {
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) continue;
      final sp = line.indexOf(' ');
      final looksTs = sp > 0 && RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(line);
      out.add({
        'stream': stream,
        'at': looksTs ? line.substring(0, sp) : '',
        'line': looksTs ? line.substring(sp + 1) : line,
      });
    }
  }

  if (tty || body.length < 8 || (body[0] != 1 && body[0] != 2) || body[1] != 0) {
    addText('stdout', utf8.decode(body, allowMalformed: true));
    return out;
  }
  var i = 0;
  final order = <(String, String)>[];
  while (i + 8 <= body.length) {
    final stream = body[i] == 2 ? 'stderr' : 'stdout';
    final size = (body[i + 4] << 24) | (body[i + 5] << 16) | (body[i + 6] << 8) | body[i + 7];
    final end = (i + 8 + size).clamp(0, body.length);
    order.add((stream, utf8.decode(body.sublist(i + 8, end), allowMalformed: true)));
    i = end;
  }
  for (final (s, t) in order) {
    addText(s, t);
  }
  return out;
}

/// Opérations permises sur les conteneurs du projet VIGIROAD. L'arrêt de
/// l'API d'administration, de Caddy, de PostgreSQL ou de l'agent couperait
/// l'accès aux applications : seul leur redémarrage est autorisé.
class ContainerPolicy {
  const ContainerPolicy({required this.project});

  final String? project;

  static const stoppable = {'traffic'};
  static const restartable = {'traffic', 'admin-api', 'caddy', 'backup', 'postgres'};

  bool belongs(Map<String, dynamic> labels) => project != null && labels['com.docker.compose.project'] == project;

  Set<String> allowed(Map<String, dynamic> labels) {
    if (!belongs(labels)) return const {};
    final service = labels['com.docker.compose.service'] as String?;
    return {
      if (stoppable.contains(service)) ...{'start', 'stop'},
      if (restartable.contains(service)) 'restart',
    };
  }
}

/// Utilisation CPU (en % d'un cœur × nombre de cœurs) et mémoire d'un
/// conteneur, d'après la réponse `stats`.
Map<String, Object?> summarizeStats(Map<String, dynamic> s) {
  final cpu = s['cpu_stats'] as Map<String, dynamic>? ?? const {};
  final pre = s['precpu_stats'] as Map<String, dynamic>? ?? const {};
  num usage(Map<String, dynamic> m) => ((m['cpu_usage'] as Map<String, dynamic>?)?['total_usage'] as num?) ?? 0;
  final cpuDelta = usage(cpu) - usage(pre);
  final sysDelta = ((cpu['system_cpu_usage'] as num?) ?? 0) - ((pre['system_cpu_usage'] as num?) ?? 0);
  final online = (cpu['online_cpus'] as num?) ??
      (((cpu['cpu_usage'] as Map<String, dynamic>?)?['percpu_usage'] as List<dynamic>?)?.length ?? 1);
  final cpuPercent = sysDelta > 0 && cpuDelta >= 0 ? cpuDelta / sysDelta * online * 100 : 0.0;
  final mem = s['memory_stats'] as Map<String, dynamic>? ?? const {};
  final memStats = mem['stats'] as Map<String, dynamic>? ?? const {};
  final cache = (memStats['inactive_file'] as num?) ?? (memStats['cache'] as num?) ?? 0;
  final memUsage = ((mem['usage'] as num?) ?? 0) - cache;
  var rx = 0, tx = 0;
  for (final n in ((s['networks'] as Map<String, dynamic>?) ?? const {}).values) {
    rx += ((n as Map<String, dynamic>)['rx_bytes'] as num?)?.toInt() ?? 0;
    tx += (n['tx_bytes'] as num?)?.toInt() ?? 0;
  }
  return {
    'cpuPercent': double.parse(cpuPercent.toStringAsFixed(2)),
    'memUsage': memUsage.toInt().clamp(0, 1 << 50),
    'memLimit': ((mem['limit'] as num?) ?? 0).toInt(),
    'netRx': rx,
    'netTx': tx,
    'pids': ((s['pids_stats'] as Map<String, dynamic>?)?['current'] as num?)?.toInt(),
  };
}
