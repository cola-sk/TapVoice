import 'package:flutter/material.dart';

import '../../models/gamepad_button.dart';

/// Uses the supplied controller artwork as the visual base and overlays
/// transparent hit targets plus the reference green/red state rings.
class GamepadView extends StatelessWidget {
  const GamepadView({
    super.key,
    required this.selectedId,
    required this.boundIds,
    required this.triggeredId,
    required this.playingId,
    required this.playingProgress,
    required this.recording,
    required this.recordingProgress,
    required this.onSelect,
    required this.onButtonPressed,
  });

  final String? selectedId;
  final Set<String> boundIds;
  final String? triggeredId;
  final String? playingId;
  final double playingProgress;
  final bool recording;
  final double recordingProgress;
  final ValueChanged<GamepadButton> onSelect;
  final ValueChanged<GamepadButton> onButtonPressed;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1670 / 924,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            const Image(
              image: AssetImage('assets/images/blue_controller.png'),
              fit: BoxFit.contain,
            ),
            for (final button in gamepadButtons)
              _ControllerHotspot(
                button: button,
                containerWidth: width,
                containerHeight: height,
                selected: button.id == selectedId,
                bound: boundIds.contains(button.id),
                triggered: button.id == triggeredId,
                playing: button.id == playingId,
                playingProgress: playingProgress,
                recording: recording && button.id == selectedId,
                recordingProgress: recordingProgress,
                onTap: () {
                  onSelect(button);
                  onButtonPressed(button);
                },
              ),
          ],
        );
      },
    ),
  );
}

class _ControllerHotspot extends StatelessWidget {
  const _ControllerHotspot({
    required this.button,
    required this.containerWidth,
    required this.containerHeight,
    required this.selected,
    required this.bound,
    required this.triggered,
    required this.playing,
    required this.playingProgress,
    required this.recording,
    required this.recordingProgress,
    required this.onTap,
  });

  final GamepadButton button;
  final double containerWidth;
  final double containerHeight;
  final bool selected;
  final bool bound;
  final bool triggered;
  final bool playing;
  final double playingProgress;
  final bool recording;
  final double recordingProgress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final position = button.center;
    final touchSize = (_touchDiameters[button.id] ?? 0.080) * containerWidth;
    final ringSize = (_ringDiameters[button.id] ?? 0.065) * containerWidth;

    final centerX = position.dx * containerWidth;
    final centerY = position.dy * containerHeight;

    return Positioned(
      left: centerX - touchSize / 2,
      top: centerY - touchSize / 2,
      width: touchSize,
      height: touchSize,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: Center(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            scale: triggered ? .9 : 1,
            child: SizedBox(
              width: ringSize,
              height: ringSize,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (triggered && !playing)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFE53935),
                          width: selected ? 3 : 2,
                        ),
                      ),
                    )
                  else if (!recording && !playing && (bound || selected))
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF16C82A),
                          width: selected ? 3 : 2,
                        ),
                      ),
                    ),
                  if (recording)
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: CircularProgressIndicator(
                        value: recordingProgress,
                        strokeWidth: 3,
                        color: const Color(0xFFE53935),
                        backgroundColor: const Color(0x55999999),
                      ),
                    ),
                  if (playing)
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: CircularProgressIndicator(
                        value: (1.0 - playingProgress).clamp(0.0, 1.0),
                        strokeWidth: 3,
                        color: const Color(0xFFE53935),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Touch target diameter factor relative to container width
const _touchDiameters = <String, double>{
  'btn_l1': 0.11,
  'btn_r1': 0.11,
  'btn_dpad_up': 0.08,
  'btn_dpad_left': 0.08,
  'btn_dpad_right': 0.08,
  'btn_dpad_down': 0.08,
  'btn_minus': 0.07,
  'btn_plus': 0.07,
  'btn_x': 0.085,
  'btn_y': 0.085,
  'btn_a': 0.085,
  'btn_b': 0.085,
  'btn_star': 0.08,
  'btn_home': 0.08,
};

// Visual ring sizes follow the actual button sizes in the artwork (width / 1670)
const _ringDiameters = <String, double>{
  'btn_l1': 0.080,
  'btn_r1': 0.080,
  'btn_dpad_up': 0.055,
  'btn_dpad_left': 0.055,
  'btn_dpad_right': 0.055,
  'btn_dpad_down': 0.055,
  'btn_minus': 0.046,
  'btn_plus': 0.046,
  'btn_x': 0.065,
  'btn_y': 0.065,
  'btn_a': 0.065,
  'btn_b': 0.065,
  'btn_star': 0.056,
  'btn_home': 0.056,
};
