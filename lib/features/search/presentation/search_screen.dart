import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/vr_colors.dart';
import '../../../core/theme/vr_typography.dart';
import '../../../core/widgets/glow_panel.dart';
import '../../../core/widgets/vr_backdrop.dart';
import '../../navigation/application/navigation_providers.dart';
import '../../navigation/domain/geo_math.dart';
import '../data/photon_geocoder.dart';

final geocoderProvider = Provider<Geocoder>((ref) {
  final config = ref.watch(appConfigProvider);
  return PhotonGeocoder(baseUrl: config.geocodingBaseUrl, userAgent: config.userAgent);
});

/// Recherche de destination (adresses et lieux, données OpenStreetMap).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _field = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;
  bool _loading = false;
  String? _error;
  List<Place> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(text));
  }

  Future<void> _search(String text) async {
    final id = ++_requestId;
    if (text.trim().length < 3) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final near = ref.read(positionProvider).value?.point;
      final results = await ref.read(geocoderProvider).search(text, near: near);
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = results;
        _error = null;
      });
    } on GeocodingException catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  void _choose(Place p) {
    ref.read(destinationProvider.notifier).set(
      Destination(label: p.label, detail: p.detail, point: p.point),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final here = ref.watch(positionProvider).value?.point;
    return Scaffold(
      body: VrBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Retour',
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: VrColors.textPrimary),
                    ),
                    Expanded(
                      child: GlowPanel(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        radius: 14,
                        child: TextField(
                          controller: _field,
                          autofocus: true,
                          onChanged: _onChanged,
                          onSubmitted: _search,
                          textInputAction: TextInputAction.search,
                          style: VrText.label.copyWith(fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Adresse, lieu, ville…',
                            hintStyle: VrText.label.copyWith(color: VrColors.textMuted, fontSize: 16),
                            border: InputBorder.none,
                            icon: const Icon(Icons.search_rounded, color: VrColors.cyan),
                            suffixIcon: _loading
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: VrColors.cyan),
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GlowPanel(
                    tone: PanelTone.alert,
                    child: Text(_error!, style: VrText.label),
                  ),
                ),
              Expanded(
                child: _results.isEmpty
                    ? Center(
                        child: Text(
                          _field.text.trim().length < 3
                              ? 'Saisissez au moins 3 caractères.'
                              : (_loading || _error != null ? '' : 'Aucun résultat.'),
                          style: VrText.caption,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final p = _results[i];
                          final dist = here == null ? null : formatDistance(distanceMeters(here, p.point));
                          return GestureDetector(
                            onTap: () => _choose(p),
                            child: GlowPanel(
                              glow: false,
                              child: Row(
                                children: [
                                  const Icon(Icons.place_rounded, color: VrColors.cyan),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.label, style: VrText.label.copyWith(fontWeight: FontWeight.w600)),
                                        if (p.detail.isNotEmpty) Text(p.detail, style: VrText.caption),
                                      ],
                                    ),
                                  ),
                                  if (dist != null) Text(dist, style: VrText.caption),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Données © contributeurs OpenStreetMap', style: VrText.caption),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
