import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/navigation/application/navigation_session.dart';
import 'voice_queue.dart';

export 'voice_queue.dart' show VoicePriority;

/// File vocale partagée par le guidage, les alertes et SENTRIX.
final voiceQueueProvider = Provider<VoiceQueue>(
  (ref) => VoiceQueue(ref.watch(speakerProvider), clock: ref.watch(clockProvider)),
);
