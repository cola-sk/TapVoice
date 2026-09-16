import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/audio_mapping.dart';
import '../../models/gamepad_button.dart';
import '../../services/tap_voice_bridge.dart';
import '../widgets/audio_action_dialog.dart';

class AudioListPage extends StatefulWidget {
  const AudioListPage({
    super.key,
    required this.button,
    required this.mapping,
    required this.onMappingChanged,
  });

  final GamepadButton button;
  final AudioMapping? mapping;
  final ValueChanged<AudioMapping?> onMappingChanged;

  @override
  State<AudioListPage> createState() => _AudioListPageState();
}

class _AudioListPageState extends State<AudioListPage> {
  final _bridge = TapVoiceBridge.instance;
  late AudioMapping? _mapping;
  String? _previewingAudioId;
  int? _previewStreamId;
  Timer? _previewTimer;

  List<AudioItem> get _audios => _mapping?.audios ?? [];

  @override
  void initState() {
    super.initState();
    _mapping = widget.mapping;
  }

  @override
  void dispose() {
    _stopPreview();
    super.dispose();
  }

  Future<void> _refreshMapping() async {
    try {
      final mappings = await _bridge.getMappings();
      final updated = mappings.where((m) => m.buttonId == widget.button.id);
      if (!mounted) return;
      setState(() {
        _mapping = updated.isNotEmpty ? updated.first : null;
      });
      widget.onMappingChanged(_mapping);
    } catch (_) {}
  }

  Future<void> _togglePreview(AudioItem audio) async {
    if (_previewingAudioId == audio.id) {
      await _stopPreview();
      return;
    }

    await _stopPreview();

    try {
      final result = await _bridge.playButton(
        widget.button.id,
        audioId: audio.id,
      );
      if (!mounted || !result.isSuccess) return;

      final duration = result.durationMs > 0 ? result.durationMs : audio.durationMs;
      final effectiveDuration = duration > 0 ? duration : 1500;

      setState(() {
        _previewingAudioId = audio.id;
        _previewStreamId = result.streamId;
      });

      _previewTimer?.cancel();
      _previewTimer = Timer(Duration(milliseconds: effectiveDuration + 100), () {
        if (mounted && _previewingAudioId == audio.id) {
          setState(() {
            _previewingAudioId = null;
            _previewStreamId = null;
          });
        }
      });
    } on PlatformException catch (e) {
      _showMessage('Playback failed: ${e.message ?? e.code}');
    }
  }

  Future<void> _stopPreview() async {
    _previewTimer?.cancel();
    _previewTimer = null;
    final streamId = _previewStreamId;
    _previewStreamId = null;
    if (streamId != null) {
      try {
        await _bridge.stopPlayback(streamId);
      } catch (_) {}
    }
    if (mounted && _previewingAudioId != null) {
      setState(() => _previewingAudioId = null);
    }
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

  Future<void> _openAudioDialog([AudioItem? item]) async {
    await _stopPreview();
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => AudioActionDialog(
        button: widget.button,
        audioItem: item,
      ),
    );

    if (changed == true || mounted) {
      await _refreshMapping();
    }
  }

  String _formatDuration(int durationMs) {
    if (durationMs <= 0) return '0:00';
    final seconds = (durationMs / 1000).round();
    final mins = seconds ~/ 60;
    final remSecs = seconds % 60;
    return '$mins:${remSecs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final audios = _audios;
    final canAdd = audios.length < 10;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F3F3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_ios_new, size: 16, color: Colors.black),
                          SizedBox(width: 6),
                          Text(
                            'Back',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Button ${widget.button.label} - Audios',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: audios.length >= 10
                                ? const Color(0xFFFFEBEE)
                                : const Color(0xFFF0F0F0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${audios.length} / 10',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: audios.length >= 10
                                  ? const Color(0xFFE53935)
                                  : const Color(0xFF666666),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: canAdd ? () => _openAudioDialog(null) : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: canAdd ? Colors.black : const Color(0xFFCCCCCC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            size: 20,
                            color: canAdd ? Colors.white : const Color(0xFF888888),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            canAdd ? 'Add Audio' : 'Max 10 Reached',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: canAdd ? Colors.white : const Color(0xFF888888),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: audios.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.graphic_eq_rounded,
                            size: 56,
                            color: Color(0xFFBBBBBB),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No audios added yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF444444),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'You can bind up to 10 recordings or uploaded files to this button.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF888888),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () => _openAudioDialog(null),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add Audio'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      itemCount: audios.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final audio = audios[index];
                        final isPreviewing = _previewingAudioId == audio.id;
                        final displayName = audio.name.isNotEmpty
                            ? audio.name
                            : 'Audio ${index + 1}';

                        return Material(
                          color: const Color(0xFFFAFAFA),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () => _openAudioDialog(audio),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isPreviewing
                                      ? const Color(0xFFE53935)
                                      : const Color(0xFFE8E8E8),
                                  width: isPreviewing ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(15),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Duration: ${_formatDuration(audio.durationMs)}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF777777),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Quick preview button
                                  IconButton(
                                    icon: Icon(
                                      isPreviewing
                                          ? Icons.stop_circle_rounded
                                          : Icons.play_circle_fill_rounded,
                                      color: isPreviewing
                                          ? const Color(0xFFE53935)
                                          : Colors.black,
                                      size: 36,
                                    ),
                                    tooltip: isPreviewing ? 'Stop Preview' : 'Play Preview',
                                    onPressed: () => _togglePreview(audio),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 16,
                                    color: Color(0xFFAAAAAA),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
