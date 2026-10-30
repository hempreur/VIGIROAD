/// Mode de performance de la lecture des plaques.
enum PerformanceMode {
  /// Analyses espacées : moins de batterie et de chaleur.
  economy(Duration(milliseconds: 500), 'Économie'),

  /// Compromis par défaut.
  balanced(Duration(milliseconds: 250), 'Équilibré'),

  /// Analyses aussi fréquentes que le téléphone le permet.
  maximum(Duration(milliseconds: 120), 'Maximal');

  const PerformanceMode(this.minInterval, this.label);

  /// Intervalle minimal entre deux analyses OCR.
  final Duration minInterval;
  final String label;
}

/// Durée de conservation de l'historique.
enum Retention {
  day1(Duration(days: 1), '24 heures'),
  days7(Duration(days: 7), '7 jours'),
  days30(Duration(days: 30), '30 jours'),
  days90(Duration(days: 90), '90 jours'),
  days365(Duration(days: 365), '1 an'),
  unlimited(null, 'Illimitée');

  const Retention(this.duration, this.label);
  final Duration? duration;
  final String label;
}

/// Réglages de l'application, persistés sur le téléphone.
class AppSettings {
  const AppSettings({
    this.autoStartDetection = false,
    this.performance = PerformanceMode.balanced,
    this.minConfidence = 0.8,
    this.minVotes = 3,
    this.alertSound = true,
    this.alertVolume = 1.0,
    this.sentrixAnnounce = true,
    this.voiceGuidance = true,
    this.drive3d = true,
    this.logHistory = true,
    this.saveLocation = true,
    this.retention = Retention.days30,
    this.allowExport = false,
  });

  /// Lancer la lecture des plaques à l'ouverture de l'écran de navigation.
  final bool autoStartDetection;
  final PerformanceMode performance;

  /// Seuil de confiance d'une alerte (0,6 – 0,95).
  final double minConfidence;

  /// Nombre de lectures concordantes exigées (2 – 6).
  final int minVotes;
  final bool alertSound;
  final double alertVolume;

  /// Annonce vocale des alertes par SENTRIX.
  final bool sentrixAnnounce;
  final bool voiceGuidance;

  /// Vue inclinée « conduite » par défaut.
  final bool drive3d;
  final bool logHistory;

  /// Enregistrer la position GPS dans l'historique.
  final bool saveLocation;
  final Retention retention;

  /// Autoriser l'export de l'historique (désactivé par défaut : données personnelles).
  final bool allowExport;

  AppSettings copyWith({
    bool? autoStartDetection,
    PerformanceMode? performance,
    double? minConfidence,
    int? minVotes,
    bool? alertSound,
    double? alertVolume,
    bool? sentrixAnnounce,
    bool? voiceGuidance,
    bool? drive3d,
    bool? logHistory,
    bool? saveLocation,
    Retention? retention,
    bool? allowExport,
  }) => AppSettings(
    autoStartDetection: autoStartDetection ?? this.autoStartDetection,
    performance: performance ?? this.performance,
    minConfidence: minConfidence ?? this.minConfidence,
    minVotes: minVotes ?? this.minVotes,
    alertSound: alertSound ?? this.alertSound,
    alertVolume: alertVolume ?? this.alertVolume,
    sentrixAnnounce: sentrixAnnounce ?? this.sentrixAnnounce,
    voiceGuidance: voiceGuidance ?? this.voiceGuidance,
    drive3d: drive3d ?? this.drive3d,
    logHistory: logHistory ?? this.logHistory,
    saveLocation: saveLocation ?? this.saveLocation,
    retention: retention ?? this.retention,
    allowExport: allowExport ?? this.allowExport,
  );

  Map<String, Object> toJson() => {
    'autoStartDetection': autoStartDetection,
    'performance': performance.name,
    'minConfidence': minConfidence,
    'minVotes': minVotes,
    'alertSound': alertSound,
    'alertVolume': alertVolume,
    'sentrixAnnounce': sentrixAnnounce,
    'voiceGuidance': voiceGuidance,
    'drive3d': drive3d,
    'logHistory': logHistory,
    'saveLocation': saveLocation,
    'retention': retention.name,
    'allowExport': allowExport,
  };

  /// Lecture tolérante : toute valeur absente ou invalide reprend sa valeur
  /// par défaut (mise à jour de l'application, fichier corrompu…).
  factory AppSettings.fromJson(Map<String, Object?> j) {
    const d = AppSettings();
    T pick<T>(String k, T fallback) => j[k] is T ? j[k]! as T : fallback;
    E pickEnum<E extends Enum>(String k, List<E> values, E fallback) =>
        values.where((e) => e.name == j[k]).firstOrNull ?? fallback;
    double clampD(double v, double lo, double hi) => v.isNaN ? lo : v.clamp(lo, hi);
    return AppSettings(
      autoStartDetection: pick('autoStartDetection', d.autoStartDetection),
      performance: pickEnum('performance', PerformanceMode.values, d.performance),
      minConfidence: clampD(pick<num>('minConfidence', d.minConfidence).toDouble(), 0.6, 0.95),
      minVotes: pick<num>('minVotes', d.minVotes).toInt().clamp(2, 6),
      alertSound: pick('alertSound', d.alertSound),
      alertVolume: clampD(pick<num>('alertVolume', d.alertVolume).toDouble(), 0, 1),
      sentrixAnnounce: pick('sentrixAnnounce', d.sentrixAnnounce),
      voiceGuidance: pick('voiceGuidance', d.voiceGuidance),
      drive3d: pick('drive3d', d.drive3d),
      logHistory: pick('logHistory', d.logHistory),
      saveLocation: pick('saveLocation', d.saveLocation),
      retention: pickEnum('retention', Retention.values, d.retention),
      allowExport: pick('allowExport', d.allowExport),
    );
  }
}
