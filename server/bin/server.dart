import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:vigiroad_traffic_aggregator/traffic_aggregator.dart';

Future<void> main() async {
  final config = ServerConfig(Platform.environment);
  final keys = config.apiKeys;
  if (keys.isEmpty) {
    stderr.writeln('VR_API_KEYS manquante : au moins une clé de 16 caractères ou plus est requise.');
    exit(64);
  }
  final aggregator = TrafficAggregator(chains: config.chains(), client: http.Client())..start();
  final api = TrafficApi(aggregator, apiKeys: keys);

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(api.handler);
  final server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
  stdout.writeln('VigiRoadTrafficAggregator : port ${server.port}, sources : '
      '${aggregator.statuses.map((s) => s.connector.info.id).join(', ')}');

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      aggregator.stop();
      await server.close();
      exit(0);
    });
  }
}
