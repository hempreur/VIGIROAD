import 'dart:async';

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/session.dart';
import '../theme.dart';
import 'panel.dart';

typedef Loader = Future<Map<String, dynamic>> Function(AdminClient api);

/// Charge des données de l'API, les actualise automatiquement et gère
/// chargement, erreur et nouvel essai. Les données précédentes restent
/// affichées pendant une actualisation ou une coupure réseau.
class Fetch extends StatefulWidget {
  const Fetch({super.key, required this.load, required this.builder, this.refresh, this.loading});

  final Loader load;
  final Widget Function(BuildContext context, Map<String, dynamic> data, Future<void> Function() reload) builder;
  final Duration? refresh;
  final Widget? loading;

  @override
  State<Fetch> createState() => _FetchState();
}

class _FetchState extends State<Fetch> {
  Map<String, dynamic>? _data;
  ApiException? _error;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
    if (widget.refresh != null) {
      _timer = Timer.periodic(widget.refresh!, (_) => unawaited(_load()));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    final session = SessionScope.read(context);
    if (session.client == null) return;
    _loading = true;
    try {
      final d = await widget.load(session.api);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      if (_error != null) return ErrorPanel(_error!, onRetry: _load);
      return widget.loading ??
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _Banner('Actualisation impossible : ${_error!.message}', onRetry: _load),
          ),
        widget.builder(context, d, _load),
      ],
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel(this.error, {super.key, this.onRetry});
  final ApiException error;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          error.status == 403 ? Icons.lock_outline_rounded : Icons.cloud_off_rounded,
          color: error.status == 403 ? VrColors.warning : VrColors.criticalText,
          size: 34,
        ),
        const SizedBox(height: 10),
        Text(error.message, style: VrText.body, textAlign: TextAlign.center),
        if (onRetry != null && error.status != 403) ...[
          const SizedBox(height: 14),
          VrButton(label: 'Réessayer', icon: Icons.refresh_rounded, primary: false, onPressed: () => unawaited(onRetry!())),
        ],
      ],
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, {required this.onRetry});
  final String text;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: VrColors.warning.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: VrColors.warning.withValues(alpha: 0.4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: VrColors.warning, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: VrText.caption.copyWith(color: VrColors.textPrimary))),
        TextButton(onPressed: () => unawaited(onRetry()), child: const Text('Réessayer')),
      ],
    ),
  );
}
