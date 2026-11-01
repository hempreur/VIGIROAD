import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'docker.dart';
import 'host.dart';

/// Agent de supervision : écoute uniquement sur le réseau Docker interne,
/// exige un jeton partagé avec l'API d'administration et n'expose qu'une
/// liste fermée d'opérations (aucune commande arbitraire, aucun accès direct
/// au socket Docker).
class MonitoringAgent {
  MonitoringAgent({required this.token, required this.host, required this.docker, this.runDir = '/run/vigiroad'});

  final String token;
  final HostReader host;
  final DockerClient docker;

  /// Dossier partagé avec l'hôte : demandes de déploiement et leur état.
  final String runDir;
  ContainerPolicy policy = const ContainerPolicy(project: null);

  /// Projet Docker Compose de l'agent (les conteneurs pilotables sont ceux du
  /// même projet).
  Future<void> detectProject() async {
    final env = Platform.environment['VR_COMPOSE_PROJECT'];
    if (env != null && env.isNotEmpty) {
      policy = ContainerPolicy(project: env);
      return;
    }
    try {
      final self = await docker.inspect(Platform.localHostname);
      final labels = (self['Config'] as Map<String, dynamic>)['Labels'] as Map<String, dynamic>? ?? const {};
      policy = ContainerPolicy(project: labels['com.docker.compose.project'] as String?);
    } catch (e) {
      stderr.writeln('Projet Docker introuvable ($e) : aucune action sur les conteneurs.');
    }
  }

  static bool _eq(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  Future<void> handle(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType = ContentType.json;
    res.headers.set('cache-control', 'no-store');
    try {
      final path = req.uri.path;
      if (path == '/health') return await _send(res, 200, {'status': 'ok'});
      if (!_eq(req.headers.value('x-agent-token') ?? '', token)) return await _send(res, 401, {'error': 'Jeton agent invalide'});
      return await _send(res, 200, await route(req.method, path, req.uri.queryParameters));
    } on DockerException catch (e) {
      return _send(res, e.status == 404 ? 404 : 502, {'error': e.message});
    } on _HttpError catch (e) {
      return _send(res, e.status, {'error': e.message});
    } catch (e) {
      return _send(res, 500, {'error': '$e'});
    }
  }

  Future<void> _send(HttpResponse res, int status, Object? body) async {
    res.statusCode = status;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<Object?> route(String method, String path, Map<String, String> q) async {
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    switch ((method, seg)) {
      case ('GET', ['system']):
        String? dockerVersion;
        try {
          dockerVersion = (await docker.version())['Version'] as String?;
        } catch (_) {}
        return {...host.system(), 'docker': dockerVersion, 'project': policy.project};
      case ('GET', ['metrics']):
        return host.metrics();
      case ('GET', ['processes']):
        return {'processes': await host.processes(), 'services': await host.services()};
      case ('GET', ['containers']):
        return {'containers': await containers(withStats: q['stats'] == 'true')};
      case ('GET', ['containers', final id, 'logs']):
        final c = await _container(id);
        final tail = (int.tryParse(q['tail'] ?? '') ?? 200).clamp(10, 2000);
        final tty = ((c['Config'] as Map<String, dynamic>)['Tty'] as bool?) ?? false;
        return {'id': c['Id'], 'lines': await docker.logs(c['Id'] as String, tail: tail, tty: tty)};
      case ('GET', ['containers', final id, 'stats']):
        final c = await _container(id);
        return summarizeStats(await docker.stats(c['Id'] as String));
      case ('POST', ['containers', final id, final action]):
        final c = await _container(id);
        final labels = (c['Config'] as Map<String, dynamic>)['Labels'] as Map<String, dynamic>? ?? const {};
        if (!policy.allowed(labels).contains(action)) {
          throw _HttpError(403, 'Action « $action » non autorisée sur ce conteneur');
        }
        await docker.action(c['Id'] as String, action);
        return {'ok': true, 'action': action, 'service': labels['com.docker.compose.service']};
      case ('GET', ['volumes']):
        final sizes = await docker.volumeSizes();
        return {
          'volumes': [
            for (final v in await docker.volumes())
              {
                'name': v['Name'],
                'driver': v['Driver'],
                'mountpoint': v['Mountpoint'],
                'createdAt': v['CreatedAt'],
                'size': sizes[v['Name']],
                'project': ((v['Labels'] as Map<String, dynamic>?) ?? const {})['com.docker.compose.project'],
              },
          ],
        };
      case ('GET', ['networks']):
        return {
          'networks': [
            for (final n in await docker.networks())
              {
                'name': n['Name'],
                'driver': n['Driver'],
                'scope': n['Scope'],
                'internal': n['Internal'],
                'containers': ((n['Containers'] as Map<String, dynamic>?) ?? const {}).length,
              },
          ],
        };
      case ('GET', ['images']):
        return {
          'images': [
            for (final i in await docker.images())
              {
                'id': (i['Id'] as String).replaceFirst('sha256:', '').substring(0, 12),
                'tags': i['RepoTags'] ?? const [],
                'size': i['Size'],
                'created': DateTime.fromMillisecondsSinceEpoch(((i['Created'] as num?) ?? 0).toInt() * 1000, isUtc: true)
                    .toIso8601String(),
              },
          ],
        };
      case ('GET', ['deploy']):
        return deployStatus();
      case ('POST', ['deploy']):
        return requestDeploy(q['by'] ?? 'admin');
      default:
        throw _HttpError(404, 'Ressource inconnue');
    }
  }

  Future<Map<String, dynamic>> _container(String id) async {
    if (!RegExp(r'^[A-Za-z0-9_.\-]{1,128}$').hasMatch(id)) throw _HttpError(400, 'Identifiant invalide');
    return docker.inspect(id);
  }

  Future<List<Map<String, Object?>>> containers({bool withStats = false}) async {
    final list = await docker.containers();
    final out = <Map<String, Object?>>[];
    final stats = <String, Future<Map<String, Object?>?>>{};
    if (withStats) {
      for (final c in list) {
        if (c['State'] == 'running') {
          final id = c['Id'] as String;
          stats[id] = docker.stats(id).then<Map<String, Object?>?>(summarizeStats).catchError((_) => null);
        }
      }
    }
    for (final c in list) {
      final labels = (c['Labels'] as Map<String, dynamic>?) ?? const {};
      final id = c['Id'] as String;
      out.add({
        'id': id.substring(0, 12),
        'name': ((c['Names'] as List<dynamic>?)?.firstOrNull as String? ?? '').replaceFirst('/', ''),
        'image': c['Image'],
        'state': c['State'],
        'status': c['Status'],
        'created': DateTime.fromMillisecondsSinceEpoch(((c['Created'] as num?) ?? 0).toInt() * 1000, isUtc: true)
            .toIso8601String(),
        'service': labels['com.docker.compose.service'],
        'project': labels['com.docker.compose.project'],
        'vigiroad': policy.belongs(labels),
        'actions': policy.allowed(labels).toList()..sort(),
        'health': RegExp(r'\((healthy|unhealthy|health: starting)\)').firstMatch(c['Status'] as String? ?? '')?.group(1),
        'ports': [
          for (final p in (c['Ports'] as List<dynamic>?) ?? const [])
            if ((p as Map<String, dynamic>)['PublicPort'] != null) '${p['PublicPort']}/${p['Type']}',
        ],
        if (withStats) 'stats': await (stats[id] ?? Future.value(null)),
      });
    }
    out.sort((a, b) => (b['vigiroad'] == true ? 1 : 0).compareTo(a['vigiroad'] == true ? 1 : 0));
    return out;
  }

  /// État du dernier déploiement (fichiers écrits par install.sh sur l'hôte).
  Map<String, Object?> deployStatus() {
    String? read(String name) {
      try {
        return File('$runDir/$name').readAsStringSync();
      } catch (_) {
        return null;
      }
    }

    Map<String, dynamic>? deployed;
    try {
      deployed = jsonDecode(read('deployed.json') ?? '') as Map<String, dynamic>;
    } catch (_) {}
    final log = read('deploy.log') ?? '';
    final lines = const LineSplitter().convert(log);
    return {
      'deployed': deployed,
      'state': read('deploy.request') != null ? 'pending' : (read('deploy.status')?.trim() ?? 'idle'),
      'log': lines.length > 80 ? lines.sublist(lines.length - 80) : lines,
      'available': Directory(runDir).existsSync(),
    };
  }

  Map<String, Object?> requestDeploy(String by) {
    if (!Directory(runDir).existsSync()) {
      throw _HttpError(503, 'Mise à jour à distance non installée (relancer install.sh sur le VPS)');
    }
    final status = deployStatus();
    if (status['state'] == 'pending' || status['state'] == 'running') {
      throw _HttpError(409, 'Une mise à jour est déjà en cours');
    }
    File('$runDir/deploy.request').writeAsStringSync(
      jsonEncode({'requestedAt': DateTime.now().toUtc().toIso8601String(), 'by': by.replaceAll(RegExp(r'[^\w@.\-]'), '')}),
    );
    return {'ok': true, 'state': 'pending'};
  }
}

class _HttpError implements Exception {
  _HttpError(this.status, this.message);
  final int status;
  final String message;
}
