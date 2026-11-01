import 'dart:async';

import 'package:postgres/postgres.dart' show ServerException;
import 'package:shelf/shelf.dart';

import 'accounts.dart';
import 'admin_auth.dart';
import 'admin_users.dart';
import 'context.dart';
import 'http_kit.dart';
import 'maintenance.dart';
import 'monitoring.dart';

/// API centrale : `/v1/account/*` (application mobile) et `/admin/*`
/// (applications d'administration Windows et Linux). Servie derrière Caddy
/// (HTTPS) ; jamais d'accès direct à PostgreSQL depuis Internet.
class AdminApi {
  AdminApi(this.ctx, {AgentClient? agent, TrafficProbe? traffic}) {
    accounts = AccountService(ctx);
    auth = AdminAuthService(ctx);
    users = AdminUsersService(ctx, auth);
    monitoring = MonitoringService(
      ctx,
      auth,
      agent ?? AgentClient(ctx.config.agentUrl, ctx.config.agentToken),
      traffic ?? TrafficProbe(ctx.config.trafficUrl, ctx.config.appKeys.firstOrNull),
    );
    maintenance = MaintenanceService(ctx, auth, monitoring);
    accounts.register(router);
    auth.register(router);
    users.register(router);
    monitoring.register(router);
    maintenance.register(router);
    router.get('/admin/health', (req, _) async {
      await ctx.db.scalar<int>('SELECT 1');
      return jsonOk({'status': 'ok', 'service': 'vigiroad-admin-api', 'version': version});
    });
  }

  static const version = '1.0.0';

  final AppContext ctx;
  final router = Router();
  late final AccountService accounts;
  late final AdminAuthService auth;
  late final AdminUsersService users;
  late final MonitoringService monitoring;
  late final MaintenanceService maintenance;

  void startJobs() {
    monitoring.start();
    maintenance.start();
  }

  void stopJobs() {
    monitoring.stop();
    maintenance.stop();
  }

  String _routeOf(Request req) {
    try {
      return router.match(req.method, '/${req.url.path}')?.$3 ?? 'inconnue';
    } on ApiError {
      return 'inconnue';
    }
  }

  Handler get handler => const Pipeline()
      .addMiddleware(ctx.requestStats.middleware(_routeOf))
      .addMiddleware(_securityHeaders)
      .addHandler(_dispatch);

  static Handler _securityHeaders(Handler inner) => (req) async {
    final res = await inner(req);
    return res.change(headers: {'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer'});
  };

  Future<Response> _dispatch(Request req) async {
    try {
      final m = router.match(req.method, '/${req.url.path}');
      if (m == null) return jsonError(ApiError.notFound);
      return await m.$1(req, m.$2);
    } on ApiError catch (e) {
      return jsonError(e);
    } on FormatException {
      return jsonError(ApiError.badRequest('Requête mal formée'));
    } on ServerException catch (e) {
      if (e.code == '23505') return jsonError(const ApiError(409, 'Valeur déjà utilisée', code: 'conflict'));
      if (e.code == '22P02') return jsonError(ApiError.badRequest('Valeur invalide'));
      ctx.recordError('${req.method} /${req.url.path}', e);
      return jsonError(const ApiError(500, 'Erreur interne du serveur', code: 'internal'));
    } catch (e, st) {
      ctx.recordError('${req.method} /${req.url.path}', '$e\n${st.toString().split('\n').take(6).join('\n')}');
      return jsonError(const ApiError(500, 'Erreur interne du serveur', code: 'internal'));
    }
  }
}
