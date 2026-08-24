import 'dart:math' as math;

import 'package:flutter/material.dart';

class RecorderBar extends StatelessWidget {
  const RecorderBar({
    super.key,
    required this.isRecording,
    required this.elapsed,
    required this.amplitude,
    required this.buttonLabel,
  });
  final bool isRecording;
  final Duration elapsed;
  final int amplitude;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
    decoration: BoxDecoration(
      color: const Color(0xFF1E1D27),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF353340)),
    ),
    child: Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: isRecording
                ? const Color(0xFFFF5F94)
                : const Color(0xFF777382),
            shape: BoxShape.circle,
            boxShadow: isRecording
                ? const [BoxShadow(color: Color(0x99FF5F94), blurRadius: 10)]
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          isRecording ? _format(elapsed) : '准备就绪',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _Wave(amplitude: amplitude, active: isRecording),
        ),
        const SizedBox(width: 18),
        Text(
          isRecording ? '正在录制 $buttonLabel' : '选择按键后开始录音',
          style: TextStyle(
            color: isRecording
                ? const Color(0xFFFFB1C9)
                : const Color(0xFFB6B2C0),
            fontSize: 13,
          ),
        ),
      ],
    ),
  );

  String _format(Duration value) =>
      '${value.inSeconds ~/ 60}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _Wave extends StatelessWidget {
  const _Wave({required this.amplitude, required this.active});
  final int amplitude;
  final bool active;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 26,
    child: CustomPaint(
      painter: _WavePainter(amplitude: amplitude, active: active),
    ),
  );
}

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.amplitude, required this.active});
  final int amplitude;
  final bool active;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2;
    final normalized = math.min(1.0, amplitude / 16000);
    for (var i = 0; i < 34; i++) {
      final wave = (math.sin(i * .74) + 1) / 2;
      final height = active ? 4 + (wave * (5 + normalized * 17)) : 3 + wave * 3;
      paint.color = active
          ? Color.lerp(
              const Color(0xFFFF87AD),
              const Color(0xFFFFFFFF),
              i / 34,
            )!
          : const Color(0xFF696572);
      final x = i * size.width / 33;
      canvas.drawLine(
        Offset(x, size.height / 2 - height / 2),
        Offset(x, size.height / 2 + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.amplitude != amplitude || old.active != active;
}
