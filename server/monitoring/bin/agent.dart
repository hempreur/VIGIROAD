import 'dart:io';

import 'package:vigiroad_monitoring_agent/monitoring_agent.dart';

Future<void> main() async {
  final env = Platform.environment;
  final token = env['VR_AGENT_TOKEN'] ?? '';
  if (token.length < 24) {
    stderr.writeln('VR_AGENT_TOKEN manquant (24 caractères minimum).');
    exit(64);
  }
  final host = HostReader(
    proc: env['VR_HOST_PROC'] ?? '/host/proc',
    sys: env['VR_HOST_SYS'] ?? '/host/sys',
    root: env['VR_HOST_ROOT'] ?? '/host/root',
  )..start();
  final agent = MonitoringAgent(
    token: token,
    host: host,
    docker: DockerClient(socketPath: env['VR_DOCKER_SOCKET'] ?? '/var/run/docker.sock'),
    runDir: env['VR_RUN_DIR'] ?? '/run/vigiroad',
  );
  await agent.detectProject();
  final port = int.tryParse(env['PORT'] ?? '') ?? 9100;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Agent de supervision VIGIROAD : port $port, projet ${agent.policy.project ?? '?'}');
  server.listen((req) => agent.handle(req));
  for (final s in [ProcessSignal.sigint, if (!Platform.isWindows) ProcessSignal.sigterm]) {
    s.watch().listen((_) async {
      host.stop();
      await server.close(force: true);
      exit(0);
    });
  }
}
