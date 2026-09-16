class AudioItem {
  const AudioItem({
    required this.id,
    required this.path,
    this.durationMs = 0,
    this.name = '',
    this.createdAt = 0,
  });

  final String id;
  final String path;
  final int durationMs;
  final String name;
  final int createdAt;

  factory AudioItem.fromMap(Map<Object?, Object?> map) => AudioItem(
    id: map['id']?.toString() ?? '',
    path: map['path']?.toString() ?? '',
    durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
    name: map['name']?.toString() ?? '',
    createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'path': path,
    'durationMs': durationMs,
    'name': name,
    'createdAt': createdAt,
  };
}

class AudioMapping {
  const AudioMapping({
    required this.buttonId,
    required this.keyCode,
    this.audios = const [],
    String? audioPath,
    int durationMs = 0,
  })  : _legacyAudioPath = audioPath,
        _legacyDurationMs = durationMs;

  final String buttonId;
  final int keyCode;
  final List<AudioItem> audios;
  final String? _legacyAudioPath;
  final int _legacyDurationMs;

  String? get audioPath =>
      audios.isNotEmpty ? audios.first.path : _legacyAudioPath;

  int get durationMs =>
      audios.isNotEmpty ? audios.first.durationMs : _legacyDurationMs;

  bool get hasAudio =>
      audios.isNotEmpty || (audioPath != null && audioPath!.isNotEmpty);

  factory AudioMapping.fromMap(Map<Object?, Object?> map) {
    final rawAudios = map['audios'];
    final audiosList = <AudioItem>[];
    if (rawAudios is List) {
      for (final item in rawAudios) {
        if (item is Map) {
          audiosList.add(AudioItem.fromMap(Map<Object?, Object?>.from(item)));
        }
      }
    }

    final legacyPath = map['audioPath'] as String?;
    final legacyDuration = (map['durationMs'] as num?)?.toInt() ?? 0;

    // Backward compatibility: If no audios list but legacy path exists, convert to AudioItem
    if (audiosList.isEmpty && legacyPath != null && legacyPath.isNotEmpty) {
      audiosList.add(
        AudioItem(
          id: '${map['buttonId']}_legacy',
          path: legacyPath,
          durationMs: legacyDuration,
          name: 'Audio 1',
        ),
      );
    }

    return AudioMapping(
      buttonId: map['buttonId']! as String,
      keyCode: (map['keyCode']! as num).toInt(),
      audios: audiosList,
      audioPath: legacyPath,
      durationMs: legacyDuration,
    );
  }

  Map<String, Object?> toMap() => {
    'buttonId': buttonId,
    'keyCode': keyCode,
    'audios': audios.map((a) => a.toMap()).toList(),
    'audioPath': audioPath,
    'durationMs': durationMs,
  };
}
