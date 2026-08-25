import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/audio_mapping.dart';
import '../models/gamepad_button.dart';
import '../services/tap_voice_bridge.dart';
import 'widgets/action_sidebar.dart';
import 'widgets/gamepad_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _bridge = TapVoiceBridge.instance;
  final _mappings = <String, AudioMapping>{};
  StreamSubscription<Map<Object?, Object?>>? _events;
  Timer? _recordingTimer;
  Timer? _playbackTimer;

  String? _selectedId;
  String? _triggeredId;
  String? _playingId;
  int? _playbackStreamId;
  int _playingDurationMs = 0;
  Duration _playbackElapsed = Duration.zero;
  DateTime? _playbackStartedAt;
  double _playingProgress = 0.0;
  bool _playingPaused = false;
  bool _recording = false;
  bool _paused = false;
  bool _accessibilityEnabled = false;
  Duration _elapsed = Duration.zero;
  DateTime? _recordingStartedAt;

  GamepadButton? get _selected {
    final selectedId = _selectedId;
    if (selectedId == null) return null;
    return gamepadButtons.firstWhere((button) => button.id == selectedId);
  }

  AudioMapping? get _selectedMapping => _mappings[_selectedId];
  Set<String> get _boundIds => _mappings.values
      .where((mapping) => mapping.hasAudio)
      .map((mapping) => mapping.buttonId)
      .toSet();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _events = _bridge.events.listen(_handleNativeEvent);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
    final streamId = _playbackStreamId;
    if (streamId != null) {
      unawaited(_bridge.stopPlayback(streamId));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAccessibility();
    }
  }

  Future<void> _load() async {
    await Future.wait([_loadMappings(), _refreshAccessibility()]);
  }

  Future<void> _loadMappings() async {
    try {
      final mappings = await _bridge.getMappings();
      if (!mounted) return;
      setState(() {
        _mappings
          ..clear()
          ..addEntries(
            mappings.map((mapping) => MapEntry(mapping.buttonId, mapping)),
          );
      });
    } on PlatformException catch (error) {
      _message('无法读取映射：${error.message ?? error.code}');
    }
  }

  Future<void> _refreshAccessibility() async {
    final enabled = await _bridge.accessibilityEnabled();
    if (mounted) setState(() => _accessibilityEnabled = enabled);
  }

  void _handleNativeEvent(Map<Object?, Object?> event) {
    if (event['type'] != 'keyPressed') return;
    final keyCode = (event['keyCode'] as num).toInt();
    final matches = gamepadButtons.where(
      (item) => (_mappings[item.id]?.keyCode ?? item.keyCode) == keyCode,
    );
    if (matches.isEmpty || !mounted) return;
    final button = matches.first;
    setState(() {
      _selectedId = button.id;
      _triggeredId = button.id;
    });
    HapticFeedback.lightImpact();
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted && _triggeredId == button.id) {
        setState(() => _triggeredId = null);
      }
    });
  }

  Future<void> _playCurrentButton([String? buttonId]) async {
    final targetId = buttonId ?? _selectedId;
    if (targetId == null) return;
    final mapping = _mappings[targetId];
    if (mapping?.hasAudio != true) return;

    await _stopPlayback();
    final durationMs = mapping!.durationMs > 0 ? mapping.durationMs : 1200;

    setState(() {
      _playingId = targetId;
      _playingDurationMs = durationMs;
      _playbackElapsed = Duration.zero;
      _playbackStartedAt = null;
      _playingPaused = false;
      _playingProgress = 0.0;
    });

    try {
      final streamId = await _bridge.playButton(targetId);
      if (!mounted || _playingId != targetId || streamId == 0) {
        if (streamId != 0) unawaited(_bridge.stopPlayback(streamId));
        if (mounted && _playingId == targetId) _clearPlaybackState();
        return;
      }
      _playbackStreamId = streamId;
      _playbackStartedAt = DateTime.now();
      _startPlaybackTimer(targetId);
    } on PlatformException catch (error) {
      if (mounted && _playingId == targetId) _clearPlaybackState();
      _message('播放录音失败：${error.message ?? error.code}');
    }
  }

  void _startPlaybackTimer(String targetId) {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted || _playingId != targetId) {
        timer.cancel();
        return;
      }
      if (_playingPaused || _playbackStartedAt == null) return;
      final elapsed =
          _playbackElapsed + DateTime.now().difference(_playbackStartedAt!);
      final progress = (elapsed.inMilliseconds / _playingDurationMs).clamp(
        0.0,
        1.0,
      );
      if (progress >= 1.0) {
        _clearPlaybackState();
      } else if (mounted) {
        setState(() => _playingProgress = progress);
      }
    });
  }

  Future<void> _pauseOrResumePlayback() async {
    final streamId = _playbackStreamId;
    final targetId = _playingId;
    if (streamId == null || targetId == null) return;

    try {
      if (_playingPaused) {
        await _bridge.resumePlayback(streamId);
        if (!mounted || _playingId != targetId) return;
        setState(() {
          _playingPaused = false;
          _playbackStartedAt = DateTime.now();
        });
        _startPlaybackTimer(targetId);
      } else {
        final elapsed =
            _playbackElapsed +
            (_playbackStartedAt == null
                ? Duration.zero
                : DateTime.now().difference(_playbackStartedAt!));
        await _bridge.pausePlayback(streamId);
        if (!mounted || _playingId != targetId) return;
        setState(() {
          _playingPaused = true;
          _playbackElapsed = elapsed;
          _playbackStartedAt = null;
          _playingProgress = (elapsed.inMilliseconds / _playingDurationMs)
              .clamp(0.0, 1.0);
        });
        _playbackTimer?.cancel();
      }
    } on PlatformException catch (error) {
      _message('播放状态切换失败：${error.message ?? error.code}');
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
    if (mounted) _clearPlaybackState();
  }

  void _clearPlaybackState() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _playbackStreamId = null;
    _playbackStartedAt = null;
    _playbackElapsed = Duration.zero;
    if (_playingId != null || _playingProgress != 0 || _playingPaused) {
      setState(() {
        _playingId = null;
        _playingDurationMs = 0;
        _playingProgress = 0.0;
        _playingPaused = false;
      });
    }
  }

  Future<void> _startRecording() async {
    final selectedId = _selectedId;
    if (selectedId == null) {
      _message('请先选择一个手柄按键。');
      return;
    }
    if (!await _bridge.microphoneGranted()) {
      await _bridge.requestMicrophonePermission();
      _message('请允许麦克风权限后再次点击 Record。');
      return;
    }
    try {
      await _bridge.startRecording(selectedId);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _paused = false;
        _elapsed = Duration.zero;
        _recordingStartedAt = DateTime.now();
      });
      _startMeter();
    } on PlatformException catch (error) {
      _message('录音无法开始：${error.message ?? error.code}');
    }
  }

  void _startMeter() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      if (!_recording || _paused || _recordingStartedAt == null) return;
      final elapsed = DateTime.now().difference(_recordingStartedAt!);
      if (elapsed >= const Duration(minutes: 1)) {
        await _finishRecording();
        return;
      }
      if (mounted && _recording && !_paused) {
        setState(() => _elapsed = elapsed);
      }
    });
  }

  Future<void> _pauseRecording() async {
    if (_paused) return;
    try {
      await _bridge.pauseRecording();
      _recordingTimer?.cancel();
      if (mounted) setState(() => _paused = true);
    } on PlatformException catch (error) {
      _message('暂停录音失败：${error.message ?? error.code}');
    }
  }

  Future<void> _pauseOrResumeActivity() async {
    if (_recording) {
      if (_paused) {
        try {
          await _bridge.resumeRecording();
          if (!mounted) return;
          setState(() {
            _paused = false;
            _recordingStartedAt = DateTime.now().subtract(_elapsed);
          });
          _startMeter();
        } on PlatformException catch (error) {
          _message('录音状态切换失败：${error.message ?? error.code}');
        }
      } else {
        await _pauseRecording();
      }
      return;
    }
    await _pauseOrResumePlayback();
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
        _message('录音太短或保存失败，请重试。');
        return;
      }
      await _loadMappings();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _recording = false;
          _paused = false;
        });
      }
      _message('保存录音失败：${error.message ?? error.code}');
    }
  }

  Future<void> _deleteSelected() async {
    final selectedId = _selectedId;
    final selected = _selected;
    if (selectedId == null ||
        selected == null ||
        _selectedMapping?.hasAudio != true) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除录音？'),
        content: Text('将移除 ${selected.label} 的本地音频，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _stopPlayback();
    await _bridge.deleteMapping(selectedId);
    if (mounted) {
      setState(() {
        _selectedId = null;
        _mappings.remove(selectedId);
      });
    }
    await _loadMappings();
  }

  Future<void> _uploadSelected() async {
    final selectedId = _selectedId;
    if (selectedId == null) {
      _message('请先选择一个手柄按键。');
      return;
    }
    try {
      final mapping = await _bridge.uploadAudio(selectedId);
      if (mapping == null || !mounted) return;
      await _loadMappings();
      _message('音频上传成功。');
    } on PlatformException catch (error) {
      if (error.code != 'cancelled') {
        _message('音频上传失败：${error.message ?? error.code}');
      }
    }
  }

  Future<void> _enableBackground() async {
    await _bridge.requestNotificationPermission();
    await _bridge.startForegroundService();
    await _bridge.openAccessibilitySettings();
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actionWidth = (constraints.maxWidth * .16).clamp(140.0, 210.0);
          return Stack(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 26, right: 12),
                        child: GamepadView(
                          selectedId: _selectedId,
                          boundIds: _boundIds,
                          triggeredId: _triggeredId,
                          playingId: _playingId,
                          playingProgress: _playingProgress,
                          recording: _recording && !_paused,
                          recordingProgress: (_elapsed.inMilliseconds / 60000)
                              .clamp(0.0, 1.0),
                          onSelect: (button) {
                            if (!_recording) {
                              setState(() => _selectedId = button.id);
                              if (_playingId != null) {
                                unawaited(_stopPlayback());
                              }
                            }
                          },
                          onButtonPressed: (_) {},
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: actionWidth,
                    child: Center(
                      child: ActionSidebar(
                        recording: _recording,
                        playing: _playingId != null,
                        paused: _recording ? _paused : _playingPaused,
                        hasAudio: _selectedMapping?.hasAudio == true,
                        onRecord: _startRecording,
                        onPauseOrResume: _pauseOrResumeActivity,
                        onStop: _recording ? _finishRecording : _stopPlayback,
                        onPlay: () => _playCurrentButton(_selectedId),
                        onDelete: _deleteSelected,
                        onUpload: _uploadSelected,
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 18,
                right: 22,
                child: GestureDetector(
                  onTap: _accessibilityEnabled
                      ? _refreshAccessibility
                      : _enableBackground,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _accessibilityEnabled
                          ? const Color(0xFFD0D0D0)
                          : const Color(0xFFD9D7D7),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
