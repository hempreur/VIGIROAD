import 'package:shelf/shelf.dart';

/// Compteurs de requêtes et de latence par minute et par route.
class RequestStats {
  RequestStats({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _buckets = <(DateTime, String), _Bucket>{};

  void record(String route, Duration latency, {required bool error}) {
    final now = _clock().toUtc();
    final minute = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);
    final b = _buckets.putIfAbsent((minute, route), _Bucket.new);
    b.count++;
    if (error) b.errors++;
    if (b.samples.length < 2000) b.samples.add(latency.inMicroseconds / 1000);
    _buckets.removeWhere((k, _) => now.difference(k.$1) > const Duration(hours: 2));
  }

  /// Minutes terminées (et la minute en cours si [includeCurrent]).
  List<Map<String, Object?>> snapshot({bool includeCurrent = true}) {
    final now = _clock().toUtc();
    final current = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);
    return [
      for (final e in _buckets.entries)
        if (includeCurrent || e.key.$1.isBefore(current))
          {
            'minute': e.key.$1.toIso8601String(),
            'route': e.key.$2,
            'count': e.value.count,
            'errors': e.value.errors,
            'p50Ms': e.value.percentile(0.5),
            'p95Ms': e.value.percentile(0.95),
          },
    ];
  }

  /// Middleware shelf (modèle de route via [routeOf]).
  Middleware middleware(String Function(Request) routeOf) => (inner) => (req) async {
    final sw = Stopwatch()..start();
    try {
      final res = await inner(req);
      record(routeOf(req), sw.elapsed, error: res.statusCode >= 500);
      return res;
    } catch (_) {
      record(routeOf(req), sw.elapsed, error: true);
      rethrow;
    }
  };
}

class _Bucket {
  int count = 0;
  int errors = 0;
  final samples = <double>[];

  double? percentile(double p) {
    if (samples.isEmpty) return null;
    final s = [...samples]..sort();
    return s[((s.length - 1) * p).round()];
  }
}
