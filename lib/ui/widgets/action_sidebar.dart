import 'package:flutter/material.dart';

/// The reference design uses a plain, high-contrast text action stack rather
/// than cards or icon buttons.
class ActionSidebar extends StatelessWidget {
  const ActionSidebar({
    super.key,
    this.recording = false,
    required this.playing,
    required this.paused,
    required this.hasAudio,
    this.onRecord,
    required this.onPauseOrResume,
    required this.onStop,
    required this.onPlay,
    this.onDelete,
    this.onUpload,
    this.onEdit,
  });

  final bool recording;
  final bool playing;
  final bool paused;
  final bool hasAudio;
  final VoidCallback? onRecord;
  final VoidCallback onPauseOrResume;
  final VoidCallback onStop;
  final VoidCallback onPlay;
  final VoidCallback? onDelete;
  final VoidCallback? onUpload;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final List<_TextAction> actions;
    if (recording || playing) {
      actions = [
        _TextAction(
          label: paused ? 'Resume' : 'Pause',
          onTap: onPauseOrResume,
        ),
        _TextAction(label: 'Stop', onTap: onStop),
      ];
    } else if (onEdit != null) {
      actions = [
        if (hasAudio) _TextAction(label: 'Play', onTap: onPlay),
        _TextAction(label: 'Edit', onTap: onEdit!),
      ];
    } else if (hasAudio) {
      actions = [
        _TextAction(label: 'Play', onTap: onPlay),
        if (onRecord != null) _TextAction(label: 'Record', onTap: onRecord!),
        if (onUpload != null) _TextAction(label: 'Upload', onTap: onUpload!),
        if (onDelete != null) _TextAction(label: 'Del', onTap: onDelete!),
      ];
    } else {
      actions = [
        if (onRecord != null) _TextAction(label: 'Record', onTap: onRecord!),
        if (onUpload != null) _TextAction(label: 'Upload', onTap: onUpload!),
      ];
    }

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
