class AudioMapping {
  const AudioMapping({
    required this.buttonId,
    required this.keyCode,
    this.audioPath,
    this.durationMs = 0,
  });
  final String buttonId;
  final int keyCode;
  final String? audioPath;
  final int durationMs;
  bool get hasAudio => audioPath != null && audioPath!.isNotEmpty;
  factory AudioMapping.fromMap(Map<Object?, Object?> map) => AudioMapping(
    buttonId: map['buttonId']! as String,
    keyCode: (map['keyCode']! as num).toInt(),
    audioPath: map['audioPath'] as String?,
    durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
  );
}
