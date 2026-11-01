import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vigiroad_monitoring_agent/monitoring_agent.dart';

void main() {
  group('lecture de /proc', () {
    late Directory root;
    late HostReader host;

    setUp(() {
      root = Directory.systemTemp.createTempSync('vr_agent');
      Directory('${root.path}/proc/1/net').createSync(recursive: true);
      Directory('${root.path}/proc/4242').createSync(recursive: true);
      Directory('${root.path}/root/etc').createSync(recursive: true);
      Directory('${root.path}/sys/class/thermal/thermal_zone0').createSync(recursive: true);
      File('${root.path}/proc/stat').writeAsStringSync('cpu  100 0 100 800 0 0 0 0 0 0\ncpu0 50 0 50 400 0 0 0 0\ncpu1 50 0 50 400 0 0 0 0\n');
      File('${root.path}/proc/meminfo').writeAsStringSync(
        'MemTotal:        4000000 kB\nMemFree:          500000 kB\nMemAvailable:    2500000 kB\nBuffers:  100000 kB\n'
        'Cached:  900000 kB\nSwapTotal:  0 kB\nSwapFree: 0 kB\n',
      );
      File('${root.path}/proc/loadavg').writeAsStringSync('0.52 0.40 0.31 1/250 4242\n');
      File('${root.path}/proc/uptime').writeAsStringSync('12345.67 20000.00\n');
      File('${root.path}/proc/1/net/dev').writeAsStringSync(
        'Inter-|   Receive\n face |bytes packets\n    lo: 999 1 0 0 0 0 0 0 999 1 0 0 0 0 0 0\n'
        '  ens3: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\ndocker0: 5000 5 0 0 0 0 0 0 5000 5 0 0 0 0 0 0\n',
      );
      File('${root.path}/proc/4242/stat').writeAsStringSync('4242 (admin api) S 1 1 1 0 -1 0 0 0 0 0 30 10 0 0 20 0 1 0 100 1000 2500 0');
      File('${root.path}/proc/4242/comm').writeAsStringSync('dockerd\n');
      File('${root.path}/root/etc/os-release').writeAsStringSync('PRETTY_NAME="Ubuntu 24.04.1 LTS"\nID=ubuntu\n');
      File('${root.path}/root/etc/hostname').writeAsStringSync('vps-vigiroad\n');
      File('${root.path}/sys/class/thermal/thermal_zone0/type').writeAsStringSync('x86_pkg_temp\n');
      File('${root.path}/sys/class/thermal/thermal_zone0/temp').writeAsStringSync('47000\n');
      host = HostReader(proc: '${root.path}/proc', sys: '${root.path}/sys', root: '${root.path}/root');
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('CPU : pourcentage entre deux mesures, par cœur', () {
      host.sample();
      File('${host.proc}/stat').writeAsStringSync('cpu  150 0 150 900 0 0 0 0 0 0\ncpu0 100 0 50 450 0 0 0 0\ncpu1 50 0 100 450 0 0 0 0\n');
      host.sample();
      // 100 « actif » sur 200 au total.
      expect(host.cpuPercent, closeTo(50, 0.01));
      expect(host.perCore, hasLength(2));
      expect(host.perCore[0], closeTo(50, 0.01));
    });

    test('mémoire, charge, disponibilité, températures, système', () {
      final m = host.memory();
      expect(m['total'], 4000000 * 1024);
      expect(m['used'], (4000000 - 2500000) * 1024);
      expect(host.load(), [0.52, 0.40, 0.31]);
      expect(host.uptimeSeconds(), closeTo(12345.67, 0.001));
      expect(host.temperatures().single, {'sensor': 'x86_pkg_temp', 'celsius': 47.0});
      final s = host.system();
      expect(s['os'], 'Ubuntu 24.04.1 LTS');
      expect(s['hostname'], 'vps-vigiroad');
      expect((s['gui'] as Map)['xfce'], isFalse);
    });

    test('réseau : interfaces physiques seulement', () {
      final n = HostReader.parseNetDev(File('${host.proc}/1/net/dev').readAsStringSync());
      expect(n.rx, 1000);
      expect(n.tx, 2000);
    });

    test('processus (nom avec espace) et services reconnus', () async {
      final p = await host.processes();
      expect(p.single['name'], 'admin api');
      expect(p.single['rss'], 2500 * 4096);
      final s = await host.services();
      expect(s.single['label'], 'Docker');
    });
  });

  test('journaux Docker démultiplexés (stdout/stderr)', () {
    List<int> frame(int stream, String text) {
      final b = utf8.encode(text);
      return [stream, 0, 0, 0, (b.length >> 24) & 255, (b.length >> 16) & 255, (b.length >> 8) & 255, b.length & 255, ...b];
    }

    final body = [
      ...frame(1, '2026-11-01T10:00:00.000000000Z démarrage\n'),
      ...frame(2, '2026-11-01T10:00:01.000000000Z erreur source\n'),
    ];
    final lines = demuxLogs(body);
    expect(lines, hasLength(2));
    expect(lines[0], {'stream': 'stdout', 'at': '2026-11-01T10:00:00.000000000Z', 'line': 'démarrage'});
    expect(lines[1]['stream'], 'stderr');
    expect(demuxLogs(utf8.encode('ligne tty\n'), tty: true).single['line'], 'ligne tty');
  });

  group('politique des conteneurs', () {
    const p = ContainerPolicy(project: 'deploy');
    Map<String, dynamic> labels(String service, [String project = 'deploy']) =>
        {'com.docker.compose.project': project, 'com.docker.compose.service': service};

    test('trafic : démarrer, arrêter, redémarrer', () {
      expect(p.allowed(labels('traffic')), {'start', 'stop', 'restart'});
    });

    test('services d\'accès : redémarrage seulement (jamais d\'arrêt)', () {
      for (final s in ['admin-api', 'caddy', 'postgres', 'backup']) {
        expect(p.allowed(labels(s)), {'restart'}, reason: s);
      }
      expect(p.allowed(labels('agent')), isEmpty);
    });

    test('conteneurs d\'un autre projet : aucune action', () {
      expect(p.allowed(labels('traffic', 'autre')), isEmpty);
      expect(const ContainerPolicy(project: null).allowed(labels('traffic')), isEmpty);
    });
  });

  test('statistiques Docker : CPU et mémoire hors cache', () {
    final s = summarizeStats({
      'cpu_stats': {'cpu_usage': {'total_usage': 300}, 'system_cpu_usage': 2000, 'online_cpus': 2},
      'precpu_stats': {'cpu_usage': {'total_usage': 100}, 'system_cpu_usage': 1000},
      'memory_stats': {'usage': 1000, 'limit': 4000, 'stats': {'inactive_file': 200}},
      'networks': {'eth0': {'rx_bytes': 10, 'tx_bytes': 20}},
    });
    expect(s['cpuPercent'], 40.0);
    expect(s['memUsage'], 800);
    expect(s['netTx'], 20);
  });

  test('demande de déploiement : fichier pour l\'hôte, pas de double demande', () async {
    final dir = Directory.systemTemp.createTempSync('vr_run');
    addTearDown(() => dir.deleteSync(recursive: true));
    final agent = MonitoringAgent(token: 't' * 32, host: HostReader(), docker: DockerClient(), runDir: dir.path);
    expect(agent.deployStatus()['state'], 'idle');
    agent.requestDeploy('admin@vigiroad.fr; rm -rf /');
    final req = jsonDecode(File('${dir.path}/deploy.request').readAsStringSync()) as Map<String, dynamic>;
    expect(req['by'], 'admin@vigiroad.frrm-rf', reason: 'caractères neutralisés');
    expect(agent.deployStatus()['state'], 'pending');
    expect(() => agent.requestDeploy('x'), throwsA(anything));
  });
}
