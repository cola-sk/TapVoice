import 'package:flutter/services.dart';

import '../models/audio_mapping.dart';

class TapVoiceBridge {
  TapVoiceBridge._();
  static final instance = TapVoiceBridge._();
  static const _methods = MethodChannel('com.tapvoice.app/bridge');
  static const _events = EventChannel('com.tapvoice.app/events');

  Stream<Map<Object?, Object?>> get events => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Map<Object?, Object?>.from(event as Map));
  Future<List<AudioMapping>> getMappings() async {
    final raw = await _methods.invokeMethod<List<Object?>>('getMappings') ?? [];
    return raw
        .whereType<Map>()
        .map((item) => AudioMapping.fromMap(Map<Object?, Object?>.from(item)))
        .toList();
  }

  Future<void> saveMapping(String buttonId, int keyCode, {String? audioPath}) =>
      _methods.invokeMethod<void>('saveMapping', {
        'buttonId': buttonId,
        'keyCode': keyCode,
        'audioPath': audioPath,
      });
  Future<void> deleteMapping(String buttonId) =>
      _methods.invokeMethod<void>('deleteMapping', {'buttonId': buttonId});
  Future<int> playButton(String buttonId) async =>
      await _methods.invokeMethod<int>('playButton', {'buttonId': buttonId}) ??
      0;
  Future<void> pausePlayback(int streamId) =>
      _methods.invokeMethod<void>('pausePlayback', {'streamId': streamId});
  Future<void> resumePlayback(int streamId) =>
      _methods.invokeMethod<void>('resumePlayback', {'streamId': streamId});
  Future<void> stopPlayback(int streamId) =>
      _methods.invokeMethod<void>('stopPlayback', {'streamId': streamId});
  Future<void> stopAllPlayback() =>
      _methods.invokeMethod<void>('stopAllPlayback');
  Future<void> startRecording(String buttonId) =>
      _methods.invokeMethod<void>('startRecording', {'buttonId': buttonId});
  Future<Map<Object?, Object?>?> stopRecording() =>
      _methods.invokeMethod<Map<Object?, Object?>>('stopRecording');
  Future<void> cancelRecording() =>
      _methods.invokeMethod<void>('cancelRecording');
  Future<void> pauseRecording() =>
      _methods.invokeMethod<void>('pauseRecording');
  Future<void> resumeRecording() =>
      _methods.invokeMethod<void>('resumeRecording');
  Future<AudioMapping?> uploadAudio(String buttonId) async {
    final raw = await _methods.invokeMethod<Object?>('pickAudio', {
      'buttonId': buttonId,
    });
    if (raw is! Map) return null;
    return AudioMapping.fromMap(Map<Object?, Object?>.from(raw));
  }

  Future<int> recordingAmplitude() async =>
      await _methods.invokeMethod<int>('getRecordingAmplitude') ?? 0;
  Future<bool> microphoneGranted() async =>
      await _methods.invokeMethod<bool>('isMicrophonePermissionGranted') ??
      false;
  Future<void> requestMicrophonePermission() =>
      _methods.invokeMethod<void>('requestMicrophonePermission');
  Future<bool> accessibilityEnabled() async =>
      await _methods.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
  Future<void> openAccessibilitySettings() =>
      _methods.invokeMethod<void>('openAccessibilitySettings');
  Future<void> startForegroundService() =>
      _methods.invokeMethod<void>('startForegroundService');
  Future<void> requestNotificationPermission() =>
      _methods.invokeMethod<void>('requestNotificationPermission');
}
