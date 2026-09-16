import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/audio_mapping.dart';
import '../models/gamepad_button.dart';
import '../services/tap_voice_bridge.dart';
import 'pages/audio_list_page.dart';
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
  Timer? _playbackTimer;
  Timer? _nativePlaybackFeedbackTimer;
  Timer? _messageTimer;
  OverlayEntry? _messageOverlay;

  String? _selectedId;
  String? _triggeredId;
  String? _playingId;
  String? _nativePlaybackFeedbackId;
  int? _playbackStreamId;
  int _playingDurationMs = 0;
  Duration _playbackElapsed = Duration.zero;
  DateTime? _playbackStartedAt;
  double _playingProgress = 0.0;
  double _nativePlaybackFeedbackProgress = 0.0;
  bool _playingPaused = false;
  bool _accessibilityEnabled = false;

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
    _playbackTimer?.cancel();
    _nativePlaybackFeedbackTimer?.cancel();
    _messageTimer?.cancel();
    _messageOverlay?.remove();
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
      _message('Failed to load mappings: ${error.message ?? error.code}');
    }
  }

  Future<void> _refreshAccessibility() async {
    final enabled = await _bridge.accessibilityEnabled();
    if (mounted) setState(() => _accessibilityEnabled = enabled);
  }

  void _handleNativeEvent(Map<Object?, Object?> event) {
    if (event['type'] != 'keyPressed') return;
    final keyCode = (event['keyCode'] as num).toInt();
    final buttonId = event['buttonId'] as String?;
    final durationMs = (event['durationMs'] as num?)?.toInt();
    final matches = buttonId == null
        ? gamepadButtons.where((item) {
            final mappedKeyCode = _mappings[item.id]?.keyCode ?? item.keyCode;
            return mappedKeyCode == keyCode ||
                item.keyCode == keyCode ||
                item.alternateKeyCodes.contains(keyCode);
          })
        : gamepadButtons.where((item) => item.id == buttonId);
    if (matches.isEmpty || !mounted) return;
    final button = matches.first;
    setState(() {
      _selectedId = button.id;
      _triggeredId = button.id;
    });
    _startNativePlaybackFeedback(button.id, durationMs);
    HapticFeedback.lightImpact();
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (mounted && _triggeredId == button.id) {
        setState(() => _triggeredId = null);
      }
    });
  }

  /// Accessibility playback starts in the Android service, so Flutter does
  /// not receive a MediaPlayer stream ID. Keep a UI-only countdown in sync
  /// with the saved recording duration without starting the audio twice.
  void _startNativePlaybackFeedback(String buttonId, [int? eventDurationMs]) {
    _nativePlaybackFeedbackTimer?.cancel();
    final mapping = _mappings[buttonId];
    final durationMs = eventDurationMs != null && eventDurationMs > 0
        ? eventDurationMs
        : (mapping != null && mapping.durationMs > 0 ? mapping.durationMs : 1200);
    final startedAt = DateTime.now();
    if (mounted) {
      setState(() {
        _nativePlaybackFeedbackId = buttonId;
        _nativePlaybackFeedbackProgress = 0.0;
      });
    }
    _nativePlaybackFeedbackTimer = Timer.periodic(
      const Duration(milliseconds: 30),
      (timer) {
        if (!mounted || _nativePlaybackFeedbackId != buttonId) {
          timer.cancel();
          return;
        }
        final progress =
            (DateTime.now().difference(startedAt).inMilliseconds / durationMs)
                .clamp(0.0, 1.0);
        if (progress >= 1.0) {
          timer.cancel();
          setState(() {
            _nativePlaybackFeedbackId = null;
            _nativePlaybackFeedbackProgress = 0.0;
          });
        } else {
          setState(() => _nativePlaybackFeedbackProgress = progress);
        }
      },
    );
  }

  Future<void> _playCurrentButton([String? buttonId]) async {
    final targetId = buttonId ?? _selectedId;
    if (targetId == null) return;
    final mapping = _mappings[targetId];
    if (mapping?.hasAudio != true) return;

    await _stopPlayback();
    final fallbackDuration = mapping!.durationMs > 0 ? mapping.durationMs : 1200;

    setState(() {
      _playingId = targetId;
      _playingDurationMs = fallbackDuration;
      _playbackElapsed = Duration.zero;
      _playbackStartedAt = null;
      _playingPaused = false;
      _playingProgress = 0.0;
    });

    try {
      final result = await _bridge.playButton(targetId);
      if (!mounted || _playingId != targetId || !result.isSuccess) {
        if (result.isSuccess) unawaited(_bridge.stopPlayback(result.streamId));
        if (mounted && _playingId == targetId) _clearPlaybackState();
        return;
      }
      final actualDuration = result.durationMs > 0 ? result.durationMs : fallbackDuration;
      _playbackStreamId = result.streamId;
      _playingDurationMs = actualDuration;
      _playbackStartedAt = DateTime.now();
      _startPlaybackTimer(targetId);
    } on PlatformException catch (error) {
      if (mounted && _playingId == targetId) _clearPlaybackState();
      _message('Playback failed: ${error.message ?? error.code}');
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
      _message('Playback state change failed: ${error.message ?? error.code}');
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
    try {
      await _bridge.stopAllPlayback();
    } catch (_) {}
    if (mounted) _clearPlaybackState();
  }

  void _clearPlaybackState() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _nativePlaybackFeedbackTimer?.cancel();
    _nativePlaybackFeedbackTimer = null;
    _playbackStreamId = null;
    _playbackStartedAt = null;
    _playbackElapsed = Duration.zero;
    if (_playingId != null ||
        _playingProgress != 0 ||
        _playingPaused ||
        _nativePlaybackFeedbackId != null ||
        _nativePlaybackFeedbackProgress != 0) {
      setState(() {
        _playingId = null;
        _playingDurationMs = 0;
        _playingProgress = 0.0;
        _playingPaused = false;
        _nativePlaybackFeedbackId = null;
        _nativePlaybackFeedbackProgress = 0.0;
      });
    }
  }

  Future<void> _openAudioList(GamepadButton button) async {
    unawaited(_stopPlayback());
    final mapping = _mappings[button.id];
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AudioListPage(
          button: button,
          mapping: mapping,
          onMappingChanged: (updated) {
            if (mounted) {
              setState(() {
                if (updated != null) {
                  _mappings[button.id] = updated;
                } else {
                  _mappings.remove(button.id);
                }
              });
            }
          },
        ),
      ),
    );
    await _loadMappings();
  }

  Future<void> _openBackgroundSettings() async {
    try {
      if (!_accessibilityEnabled) {
        await _bridge.requestNotificationPermission();
        await _bridge.startForegroundService();
      }
      await _bridge.openAccessibilitySettings();
    } on PlatformException catch (error) {
      _message('Failed to open settings: ${error.message ?? error.code}');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    _messageTimer?.cancel();
    _messageOverlay?.remove();
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: MediaQuery.paddingOf(overlayContext).top + 12,
        left: 24,
        right: 24,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF323232),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _messageOverlay = entry;
    overlay.insert(entry);
    _messageTimer = Timer(const Duration(seconds: 3), () {
      _messageOverlay?.remove();
      _messageOverlay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final actionWidth = (constraints.maxWidth * 0.18).clamp(110.0, 160.0);
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
                            playingId: _nativePlaybackFeedbackId ?? _playingId,
                            playingProgress: _nativePlaybackFeedbackId != null
                                ? _nativePlaybackFeedbackProgress
                                : _playingProgress,
                            recording: false,
                            recordingProgress: 0.0,
                            onSelect: (button) {
                              if (button.id == 'btn_star') {
                                unawaited(_stopPlayback());
                                _message('★ is an internal function key and cannot be mapped.');
                                return;
                              }
                              unawaited(_stopPlayback());
                              if (_selectedId == button.id) {
                                _openAudioList(button);
                              } else {
                                setState(() => _selectedId = button.id);
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
                          playing: _playingId != null,
                          paused: _playingPaused,
                          hasAudio: _selectedMapping?.hasAudio == true,
                          onPauseOrResume: _pauseOrResumePlayback,
                          onStop: _stopPlayback,
                          onPlay: () => _playCurrentButton(_selectedId),
                          onEdit: _selected != null ? () => _openAudioList(_selected!) : null,
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 18,
                  right: 22,
                child: Tooltip(
                  message: _accessibilityEnabled
                      ? 'Background service active. Tap to open Accessibility settings.'
                      : 'Enable background service',
                  child: Semantics(
                    button: true,
                    label: _accessibilityEnabled ? 'Active' : 'Enable',
                    child: GestureDetector(
                      onTap: _openBackgroundSettings,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _accessibilityEnabled
                              ? const Color(0xFFDDF4E1)
                              : const Color(0xFFE7E5E5),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: _accessibilityEnabled
                                ? const Color(0xFF42A85A)
                                : const Color(0xFFB8B5B5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                _accessibilityEnabled
                                    ? Icons.check_circle
                                    : Icons.accessibility_new,
                                key: ValueKey(_accessibilityEnabled),
                                size: 22,
                                color: _accessibilityEnabled
                                    ? const Color(0xFF25863D)
                                    : const Color(0xFF6F6B6B),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _accessibilityEnabled ? 'Active' : 'Enable',
                              style: TextStyle(
                                color: _accessibilityEnabled
                                    ? const Color(0xFF25863D)
                                    : const Color(0xFF5D5959),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
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
}
