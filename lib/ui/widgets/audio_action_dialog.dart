import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/audio_mapping.dart';
import '../../models/gamepad_button.dart';
import '../../services/tap_voice_bridge.dart';

class AudioActionDialog extends StatefulWidget {
  const AudioActionDialog({
    super.key,
    required this.button,
    this.audioItem,
  });

  final GamepadButton button;
  final AudioItem? audioItem;

  @override
  State<AudioActionDialog> createState() => _AudioActionDialogState();
}

class _AudioActionDialogState extends State<AudioActionDialog> {
  final _bridge = TapVoiceBridge.instance;
  late AudioItem? _currentItem;
  bool _recording = false;
  bool _paused = false;
  bool _playing = false;
  bool _playbackPaused = false;
  int? _playbackStreamId;
  int _playbackDurationMs = 0;
  Duration _playbackElapsed = Duration.zero;
  DateTime? _playbackStartedAt;
  Timer? _playbackTimer;

  Timer? _recordingTimer;
  Duration _recordingElapsed = Duration.zero;
  DateTime? _recordingStartedAt;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.audioItem;
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
    if (_recording) {
      unawaited(_bridge.cancelRecording());
    }
    final streamId = _playbackStreamId;
    if (streamId != null) {
      unawaited(_bridge.stopPlayback(streamId));
    }
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // --- RECORDING ---

  Future<void> _startRecording() async {
    await _stopPlayback();

    if (!await _bridge.microphoneGranted()) {
      await _bridge.requestMicrophonePermission();
      _showMessage('Please grant microphone permission and tap Record again.');
      return;
    }

    try {
      await _bridge.startRecording(
        widget.button.id,
        audioId: _currentItem?.id,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _paused = false;
        _recordingElapsed = Duration.zero;
        _recordingStartedAt = DateTime.now();
      });
      _startRecordingTimer();
    } on PlatformException catch (e) {
      _showMessage('Failed to start recording: ${e.message ?? e.code}');
    }
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!_recording || _paused || _recordingStartedAt == null) return;
      final elapsed = DateTime.now().difference(_recordingStartedAt!);
      if (elapsed >= const Duration(minutes: 1)) {
        await _finishRecording();
        return;
      }
      if (mounted && _recording && !_paused) {
        setState(() => _recordingElapsed = elapsed);
      }
    });
  }

  Future<void> _pauseRecording() async {
    if (_paused) return;
    try {
      await _bridge.pauseRecording();
      _recordingTimer?.cancel();
      if (mounted) setState(() => _paused = true);
    } on PlatformException catch (e) {
      _showMessage('Failed to pause recording: ${e.message ?? e.code}');
    }
  }

  Future<void> _resumeRecording() async {
    if (!_paused) return;
    try {
      await _bridge.resumeRecording();
      if (!mounted) return;
      setState(() {
        _paused = false;
        _recordingStartedAt = DateTime.now().subtract(_recordingElapsed);
      });
      _startRecordingTimer();
    } on PlatformException catch (e) {
      _showMessage('Failed to resume recording: ${e.message ?? e.code}');
    }
  }

  Future<void> _finishRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final result = await _bridge.stopRecording();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _paused = false;
        _recordingStartedAt = null;
      });

      if (result == null) {
        _showMessage('Recording too short or failed to save.');
        return;
      }

      final savedPath = result['path'] as String? ?? '';
      final savedDuration = (result['durationMs'] as num?)?.toInt() ?? 0;
      final savedId = result['audioId'] as String? ??
          (_currentItem?.id ?? '${widget.button.id}_${DateTime.now().millisecondsSinceEpoch}');
      final savedName = result['name'] as String? ??
          (_currentItem?.name.isNotEmpty == true ? _currentItem!.name : 'Audio');

      setState(() {
        _currentItem = AudioItem(
          id: savedId,
          path: savedPath,
          durationMs: savedDuration,
          name: savedName,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        _hasChanges = true;
      });
      _showMessage('Recording saved.');
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _recording = false;
          _paused = false;
        });
      }
      _showMessage('Failed to save recording: ${e.message ?? e.code}');
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _bridge.cancelRecording();
    if (mounted) {
      setState(() {
        _recording = false;
        _paused = false;
      });
    }
  }

  // --- UPLOAD ---

  Future<void> _uploadAudio() async {
    await _stopPlayback();
    try {
      final mapping = await _bridge.uploadAudio(
        widget.button.id,
        audioId: _currentItem?.id,
      );
      if (mapping == null || !mounted) return;

      final target = _currentItem?.id != null
          ? mapping.audios.firstWhere(
              (a) => a.id == _currentItem!.id,
              orElse: () => mapping.audios.last,
            )
          : mapping.audios.isNotEmpty
              ? mapping.audios.last
              : null;

      setState(() {
        if (target != null) {
          _currentItem = target;
        }
        _hasChanges = true;
      });
      _showMessage('Audio file uploaded.');
    } on PlatformException catch (e) {
      if (e.code != 'cancelled') {
        _showMessage('Upload failed: ${e.message ?? e.code}');
      }
    }
  }

  // --- PLAYBACK ---

  Future<void> _playCurrent() async {
    final item = _currentItem;
    if (item == null || item.path.isEmpty) return;

    await _stopPlayback();
    final duration = item.durationMs > 0 ? item.durationMs : 1500;

    setState(() {
      _playing = true;
      _playbackPaused = false;
      _playbackDurationMs = duration;
      _playbackElapsed = Duration.zero;
      _playbackStartedAt = null;
    });

    try {
      final result = await _bridge.playButton(
        widget.button.id,
        audioId: item.id,
      );
      if (!mounted || !result.isSuccess) {
        _clearPlayback();
        return;
      }

      final actualDuration = result.durationMs > 0 ? result.durationMs : duration;
      setState(() {
        _playbackStreamId = result.streamId;
        _playbackDurationMs = actualDuration;
        _playbackStartedAt = DateTime.now();
      });
      _startPlaybackTimer();
    } on PlatformException catch (e) {
      _clearPlayback();
      _showMessage('Playback failed: ${e.message ?? e.code}');
    }
  }

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || !_playing) {
        timer.cancel();
        return;
      }
      if (_playbackPaused || _playbackStartedAt == null) return;
      final elapsed = _playbackElapsed + DateTime.now().difference(_playbackStartedAt!);
      if (elapsed.inMilliseconds >= _playbackDurationMs) {
        _clearPlayback();
      } else if (mounted) {
        setState(() => _playbackElapsed = elapsed);
      }
    });
  }

  Future<void> _pauseOrResumePlayback() async {
    final streamId = _playbackStreamId;
    if (streamId == null || !_playing) return;

    try {
      if (_playbackPaused) {
        await _bridge.resumePlayback(streamId);
        if (!mounted) return;
        setState(() {
          _playbackPaused = false;
          _playbackStartedAt = DateTime.now();
        });
        _startPlaybackTimer();
      } else {
        final elapsed = _playbackElapsed +
            (_playbackStartedAt == null
                ? Duration.zero
                : DateTime.now().difference(_playbackStartedAt!));
        await _bridge.pausePlayback(streamId);
        if (!mounted) return;
        setState(() {
          _playbackPaused = true;
          _playbackElapsed = elapsed;
          _playbackStartedAt = null;
        });
        _playbackTimer?.cancel();
      }
    } on PlatformException catch (e) {
      _showMessage('Failed to switch playback: ${e.message ?? e.code}');
    }
  }

  Future<void> _stopPlayback() async {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    final streamId = _playbackStreamId;
    _playbackStreamId = null;
    if (streamId != null) {
      try {
        await _bridge.stopPlayback(streamId);
      } catch (_) {}
    }
    if (mounted) _clearPlayback();
  }

  void _clearPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _playbackStreamId = null;
    _playbackStartedAt = null;
    _playbackElapsed = Duration.zero;
    if (mounted) {
      setState(() {
        _playing = false;
        _playbackPaused = false;
        _playbackDurationMs = 0;
      });
    }
  }

  // --- DELETE ---

  Future<void> _deleteAudio() async {
    final item = _currentItem;
    if (item == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Audio?'),
        content: const Text('Are you sure you want to delete this audio? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _stopPlayback();
    try {
      await _bridge.deleteAudio(widget.button.id, item.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PlatformException catch (e) {
      _showMessage('Delete failed: ${e.message ?? e.code}');
    }
  }

  String _formatTime(Duration duration) {
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentItem;
    final hasAudio = item != null && item.path.isNotEmpty;
    final title = item != null && item.name.isNotEmpty
        ? 'Button ${widget.button.label} - ${item.name}'
        : 'Button ${widget.button.label} - New Audio';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 22, color: Color(0xFF666666)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context, _hasChanges),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Simple Status (No waveform, no filename)
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _recording
                          ? const Color(0xFFFF5F94)
                          : _playing
                              ? const Color(0xFF16C82A)
                              : hasAudio
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFF999999),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _recording
                        ? (_paused
                            ? 'Recording Paused (${_formatTime(_recordingElapsed)})'
                            : 'Recording (${_formatTime(_recordingElapsed)} / 1:00)')
                        : _playing
                            ? (_playbackPaused
                                ? 'Playback Paused'
                                : 'Playing (${_formatTime(_playbackElapsed)})')
                            : hasAudio
                                ? 'Duration: ${_formatTime(Duration(milliseconds: item.durationMs))}'
                                : 'Ready to record or upload',
                    style: const TextStyle(
                      color: Color(0xFF555555),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Actions
              Align(
                alignment: Alignment.centerRight,
                child: _recording
                    ? Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          _DialogBtn(
                            label: _paused ? 'Resume' : 'Pause',
                            onTap: _paused ? _resumeRecording : _pauseRecording,
                          ),
                          _DialogBtn(
                            label: 'Stop',
                            onTap: _finishRecording,
                          ),
                          _DialogBtn(
                            label: 'Cancel',
                            color: const Color(0xFF888888),
                            onTap: _cancelRecording,
                          ),
                        ],
                      )
                    : _playing
                        ? Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              _DialogBtn(
                                label: _playbackPaused ? 'Resume' : 'Pause',
                                onTap: _pauseOrResumePlayback,
                              ),
                              _DialogBtn(
                                label: 'Stop',
                                onTap: _stopPlayback,
                              ),
                            ],
                          )
                        : Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              if (hasAudio)
                                _DialogBtn(
                                  label: 'Play',
                                  onTap: _playCurrent,
                                ),
                              _DialogBtn(
                                label: 'Record',
                                onTap: _startRecording,
                              ),
                              _DialogBtn(
                                label: 'Upload',
                                onTap: _uploadAudio,
                              ),
                              if (hasAudio)
                                _DialogBtn(
                                  label: 'Del',
                                  color: const Color(0xFFE53935),
                                  onTap: _deleteAudio,
                                ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogBtn extends StatelessWidget {
  const _DialogBtn({
    required this.label,
    required this.onTap,
    this.color = Colors.black,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
    ),
  );
}
