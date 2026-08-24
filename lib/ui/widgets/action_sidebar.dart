import 'package:flutter/material.dart';

/// The reference design uses a plain, high-contrast text action stack rather
/// than cards or icon buttons.
class ActionSidebar extends StatelessWidget {
  const ActionSidebar({
    super.key,
    required this.recording,
    required this.playing,
    required this.paused,
    required this.hasAudio,
    required this.onRecord,
    required this.onPauseOrResume,
    required this.onStop,
    required this.onPlay,
    required this.onDelete,
    required this.onUpload,
  });

  final bool recording;
  final bool playing;
  final bool paused;
  final bool hasAudio;
  final VoidCallback onRecord;
  final VoidCallback onPauseOrResume;
  final VoidCallback onStop;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final actions = recording || playing
        ? <_TextAction>[
            _TextAction(
              label: paused ? 'Resume' : 'Pause',
              onTap: onPauseOrResume,
            ),
            _TextAction(label: 'Stop', onTap: onStop),
          ]
        : hasAudio
        ? <_TextAction>[
            _TextAction(label: 'Play', onTap: onPlay),
            _TextAction(label: 'Record', onTap: onRecord),
            _TextAction(label: 'Upload', onTap: onUpload),
            _TextAction(label: 'Del', onTap: onDelete),
          ]
        : <_TextAction>[
            _TextAction(label: 'Record', onTap: onRecord),
            _TextAction(label: 'Upload', onTap: onUpload),
          ];

    return SizedBox(
      width: 150,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final action in actions) ...[action, const SizedBox(height: 18)],
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    hoverColor: Colors.transparent,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 28,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: -.8,
      ),
    ),
  );
}
