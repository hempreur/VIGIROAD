import 'dart:async';
import 'dart:io';

/// Lecture des métriques de l'hôte à travers /proc, /sys et la racine montés
/// en lecture seule dans le conteneur (`/host/...`).
class HostReader {
  HostReader({this.proc = '/host/proc', this.sys = '/host/sys', this.root = '/host/root'});

  final String proc;
  final String sys;
  final String root;

  CpuSample? _cpuPrev;
  _NetSample? _netPrev;
  double? cpuPercent;
  List<double> perCore = const [];
  int rxBps = 0, txBps = 0, rxTotal = 0, txTotal = 0;
  Timer? _timer;

  /// Échantillonnage toutes les [every] (CPU et réseau sont des débits).
  void start({Duration every = const Duration(seconds: 2)}) {
    sample();
    _timer = Timer.periodic(every, (_) => sample());
  }

  void stop() => _timer?.cancel();

  void sample() {
    try {
      final cpu = parseCpu(File('$proc/stat').readAsStringSync());
      final prev = _cpuPrev;
      if (prev != null) {
        cpuPercent = cpu.total.percentSince(prev.total);
        perCore = [
          for (var i = 0; i < cpu.cores.length && i < prev.cores.length; i++) cpu.cores[i].percentSince(prev.cores[i]),
        ];
      }
      _cpuPrev = cpu;
    } catch (_) {}
    try {
      final net = parseNetDev(_read('$proc/1/net/dev') ?? _read('$proc/net/dev') ?? '');
      final now = DateTime.now();
      final prev = _netPrev;
      if (prev != null) {
        final dt = now.difference(prev.at).inMilliseconds / 1000;
        if (dt > 0) {
          rxBps = ((net.rx - prev.rx) / dt).round().clamp(0, 1 << 40);
          txBps = ((net.tx - prev.tx) / dt).round().clamp(0, 1 << 40);
        }
      }
      rxTotal = net.rx;
      txTotal = net.tx;
      _netPrev = _NetSample(now, net.rx, net.tx);
    } catch (_) {}
  }

  String? _read(String path) {
    try {
      return File(path).readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  static ({CpuTimes total, List<CpuTimes> cores}) parseCpuLines(String stat) {
    CpuTimes? total;
    final cores = <CpuTimes>[];
    for (final line in stat.split('\n')) {
      if (!line.startsWith('cpu')) continue;
      final f = line.split(RegExp(r'\s+'));
      final v = [for (final x in f.skip(1)) int.tryParse(x) ?? 0];
      if (v.length < 4) continue;
      final idle = v[3] + (v.length > 4 ? v[4] : 0);
      final all = v.take(8).fold<int>(0, (a, b) => a + b);
      final c = CpuTimes(all, idle);
      if (f[0] == 'cpu') {
        total = c;
      } else {
        cores.add(c);
      }
    }
    return (total: total ?? const CpuTimes(0, 0), cores: cores);
  }

  static CpuSample parseCpu(String stat) {
    final r = parseCpuLines(stat);
    return CpuSample(r.total, r.cores);
  }

  /// Octets reçus/émis sur les interfaces physiques (hors boucle locale et
  /// interfaces virtuelles de Docker).
  static ({int rx, int tx}) parseNetDev(String text) {
    var rx = 0, tx = 0;
    for (final line in text.split('\n')) {
      final i = line.indexOf(':');
      if (i < 0) continue;
      final name = line.substring(0, i).trim();
      if (name == 'lo' || name.startsWith('docker') || name.startsWith('veth') || name.startsWith('br-')) continue;
      final f = line.substring(i + 1).trim().split(RegExp(r'\s+'));
      if (f.length < 9) continue;
      rx += int.tryParse(f[0]) ?? 0;
      tx += int.tryParse(f[8]) ?? 0;
    }
    return (rx: rx, tx: tx);
  }

  static Map<String, int> parseMeminfo(String text) => {
    for (final line in text.split('\n'))
      if (line.contains(':'))
        line.split(':')[0].trim(): (int.tryParse(line.split(':')[1].trim().split(' ').first) ?? 0) * 1024,
  };

  Map<String, Object?> memory() {
    final m = parseMeminfo(_read('$proc/meminfo') ?? '');
    final total = m['MemTotal'] ?? 0, available = m['MemAvailable'] ?? 0;
    return {
      'total': total,
      'available': available,
      'used': total - available,
      'cached': (m['Cached'] ?? 0) + (m['Buffers'] ?? 0),
      'swapTotal': m['SwapTotal'] ?? 0,
      'swapUsed': (m['SwapTotal'] ?? 0) - (m['SwapFree'] ?? 0),
    };
  }

  List<double> load() {
    final f = (_read('$proc/loadavg') ?? '').split(' ');
    return [for (final x in f.take(3)) double.tryParse(x) ?? 0];
  }

  double uptimeSeconds() => double.tryParse((_read('$proc/uptime') ?? '').split(' ').first) ?? 0;

  /// Espace disque de la racine de l'hôte (`df`).
  Future<List<Map<String, Object?>>> disks() async {
    final out = <Map<String, Object?>>[];
    try {
      final r = await Process.run('df', ['-B1', '-P', root]).timeout(const Duration(seconds: 5));
      for (final line in (r.stdout as String).split('\n').skip(1)) {
        final f = line.trim().split(RegExp(r'\s+'));
        if (f.length < 6) continue;
        out.add({
          'mount': '/',
          'device': f[0],
          'total': int.tryParse(f[1]) ?? 0,
          'used': int.tryParse(f[2]) ?? 0,
          'available': int.tryParse(f[3]) ?? 0,
        });
      }
    } catch (_) {}
    return out;
  }

  /// Températures quand le VPS expose des capteurs (souvent absents).
  List<Map<String, Object?>> temperatures() {
    final out = <Map<String, Object?>>[];
    void add(String label, String? raw) {
      final v = int.tryParse(raw?.trim() ?? '');
      if (v != null && v > 0 && v < 150000) out.add({'sensor': label, 'celsius': v / 1000});
    }

    for (final dir in _list('$sys/class/thermal')) {
      if (!dir.path.split('/').last.startsWith('thermal_zone')) continue;
      add(_read('${dir.path}/type')?.trim() ?? dir.path.split('/').last, _read('${dir.path}/temp'));
    }
    for (final dir in _list('$sys/class/hwmon')) {
      final name = _read('${dir.path}/name')?.trim() ?? 'hwmon';
      for (final f in _list(dir.path)) {
        final n = f.path.split('/').last;
        if (n.startsWith('temp') && n.endsWith('_input')) add('$name ${n.replaceAll('_input', '')}', _read(f.path));
      }
    }
    return out;
  }

  List<FileSystemEntity> _list(String path) {
    try {
      return Directory(path).listSync();
    } catch (_) {
      return const [];
    }
  }

  Map<String, Object?> system() {
    final os = {
      for (final line in (_read('$root/etc/os-release') ?? '').split('\n'))
        if (line.contains('=')) line.split('=')[0]: line.substring(line.indexOf('=') + 1).replaceAll('"', ''),
    };
    final cpuinfo = _read('$proc/cpuinfo') ?? '';
    final model = RegExp(r'model name\s*:\s*(.+)').firstMatch(cpuinfo)?.group(1)?.trim();
    bool has(String p) => File('$root$p').existsSync();
    return {
      'hostname': (_read('$root/etc/hostname') ?? Platform.localHostname).trim(),
      'os': os['PRETTY_NAME'] ?? 'Linux',
      'kernel': (_read('$proc/sys/kernel/osrelease') ?? '').trim(),
      'cpus': RegExp(r'^processor\s*:', multiLine: true).allMatches(cpuinfo).length,
      'cpuModel': model,
      'uptimeSeconds': uptimeSeconds(),
      'memTotal': memory()['total'],
      'gui': {
        'xfce': has('/usr/bin/startxfce4'),
        'xrdp': has('/usr/sbin/xrdp'),
        'serverControl': has('/usr/bin/vigiroad-server-control') || has('/opt/vigiroad-server-control/vigiroad_server_control'),
      },
    };
  }

  Future<Map<String, Object?>> metrics() async => {
    'at': DateTime.now().toUtc().toIso8601String(),
    'cpuPercent': cpuPercent,
    'perCore': perCore,
    'load': load(),
    'memory': memory(),
    'disks': await disks(),
    'network': {'rxBps': rxBps, 'txBps': txBps, 'rxTotal': rxTotal, 'txTotal': txTotal},
    'temperatures': temperatures(),
    'uptimeSeconds': uptimeSeconds(),
  };

  /// Processus les plus actifs (deux lectures à 1 s d'intervalle).
  Future<List<Map<String, Object?>>> processes({int top = 25}) async {
    Map<int, (String, int, int, String)> snap() {
      final out = <int, (String, int, int, String)>{};
      for (final d in _list(proc)) {
        final pid = int.tryParse(d.path.split('/').last);
        if (pid == null) continue;
        final stat = _read('${d.path}/stat');
        if (stat == null) continue;
        final close = stat.lastIndexOf(')');
        if (close < 0) continue;
        final name = stat.substring(stat.indexOf('(') + 1, close);
        final f = stat.substring(close + 2).split(' ');
        if (f.length < 22) continue;
        final ticks = (int.tryParse(f[11]) ?? 0) + (int.tryParse(f[12]) ?? 0);
        final rss = (int.tryParse(f[21]) ?? 0) * 4096;
        out[pid] = (name, ticks, rss, f[0]);
      }
      return out;
    }

    final a = snap();
    final totalA = parseCpuLines(_read('$proc/stat') ?? '').total.all;
    await Future<void>.delayed(const Duration(seconds: 1));
    final b = snap();
    final totalB = parseCpuLines(_read('$proc/stat') ?? '').total.all;
    final cores = parseCpuLines(_read('$proc/stat') ?? '').cores.length.clamp(1, 1024);
    final dt = (totalB - totalA).clamp(1, 1 << 62);
    final rows = [
      for (final e in b.entries)
        {
          'pid': e.key,
          'name': e.value.$1,
          'state': e.value.$4,
          'cpuPercent': a.containsKey(e.key) ? (e.value.$2 - a[e.key]!.$2) / dt * 100 * cores : 0.0,
          'rss': e.value.$3,
        },
    ]..sort((x, y) {
        final c = (y['cpuPercent'] as double).compareTo(x['cpuPercent'] as double);
        return c != 0 ? c : (y['rss'] as int).compareTo(x['rss'] as int);
      });
    return rows.take(top).toList();
  }

  /// Services de l'hôte reconnus parmi les processus.
  Future<List<Map<String, Object?>>> services() async {
    const known = {
      'sshd': 'SSH',
      'dockerd': 'Docker',
      'containerd': 'containerd',
      'xrdp': 'Bureau à distance (xrdp)',
      'xrdp-sesman': 'Sessions xrdp',
      'xfce4-session': 'Session XFCE',
      'caddy': 'Caddy (HTTPS)',
      'postgres': 'PostgreSQL',
      'cron': 'cron',
      'systemd-journal': 'Journal système',
      'fail2ban-server': 'fail2ban',
      'ufw': 'Pare-feu',
      'server': 'Serveur de trafic',
      'admin_api': 'API d\'administration',
    };
    final seen = <String, int>{};
    for (final d in _list(proc)) {
      if (int.tryParse(d.path.split('/').last) == null) continue;
      final comm = _read('${d.path}/comm')?.trim();
      if (comm != null && known.containsKey(comm)) seen[comm] = (seen[comm] ?? 0) + 1;
    }
    return [
      for (final e in known.entries)
        if (seen.containsKey(e.key)) {'process': e.key, 'label': e.value, 'instances': seen[e.key]},
    ];
  }
}

class CpuTimes {
  const CpuTimes(this.all, this.idle);
  final int all;
  final int idle;

  double percentSince(CpuTimes prev) {
    final dAll = all - prev.all, dIdle = idle - prev.idle;
    if (dAll <= 0) return 0;
    return ((dAll - dIdle) / dAll * 100).clamp(0, 100).toDouble();
  }
}

class CpuSample {
  CpuSample(this.total, this.cores);
  final CpuTimes total;
  final List<CpuTimes> cores;
}

class _NetSample {
  _NetSample(this.at, this.rx, this.tx);
  final DateTime at;
  final int rx;
  final int tx;
}
