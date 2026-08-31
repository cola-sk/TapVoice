import 'package:flutter/material.dart';

class GamepadButton {
  const GamepadButton({
    required this.id,
    required this.label,
    required this.keyCode,
    this.alternateKeyCodes = const [],
    required this.center,
    this.size = 58,
    this.shape = GamepadButtonShape.circle,
  });
  final String id;
  final String label;
  final int keyCode;

  /// Key codes emitted by the same physical button in keyboard (K) mode.
  final List<int> alternateKeyCodes;
  final Offset center;
  final double size;
  final GamepadButtonShape shape;
}

enum GamepadButtonShape { circle, rounded, dpad }

const gamepadButtons = <GamepadButton>[
  GamepadButton(
    id: 'btn_l1',
    label: 'L',
    keyCode: 102,
    alternateKeyCodes: [45],
    center: Offset(0.2515, 0.2002),
    size: 78,
    shape: GamepadButtonShape.rounded,
  ),
  GamepadButton(
    id: 'btn_r1',
    label: 'R',
    keyCode: 103,
    alternateKeyCodes: [44],
    center: Offset(0.7485, 0.2002),
    size: 78,
    shape: GamepadButtonShape.rounded,
  ),
  GamepadButton(
    id: 'btn_dpad_up',
    label: '▲',
    keyCode: 19,
    alternateKeyCodes: [31],
    center: Offset(0.2844, 0.4545),
    size: 46,
    shape: GamepadButtonShape.dpad,
  ),
  GamepadButton(
    id: 'btn_dpad_left',
    label: '◀',
    keyCode: 21,
    alternateKeyCodes: [33],
    center: Offset(0.2246, 0.5628),
    size: 46,
    shape: GamepadButtonShape.dpad,
  ),
  GamepadButton(
    id: 'btn_dpad_right',
    label: '▶',
    keyCode: 22,
    alternateKeyCodes: [34],
    center: Offset(0.3443, 0.5628),
    size: 46,
    shape: GamepadButtonShape.dpad,
  ),
  GamepadButton(
    id: 'btn_dpad_down',
    label: '▼',
    keyCode: 20,
    alternateKeyCodes: [32],
    center: Offset(0.2844, 0.6710),
    size: 46,
    shape: GamepadButtonShape.dpad,
  ),
  GamepadButton(
    id: 'btn_minus',
    label: '−',
    keyCode: 69,
    alternateKeyCodes: [42],
    center: Offset(0.4054, 0.4123),
    size: 38,
  ),
  GamepadButton(
    id: 'btn_plus',
    label: '+',
    keyCode: 81,
    alternateKeyCodes: [43],
    center: Offset(0.5422, 0.4123),
    size: 38,
  ),
  GamepadButton(
    id: 'btn_x',
    label: 'X',
    keyCode: 99,
    alternateKeyCodes: [36],
    center: Offset(0.6545, 0.4318),
    size: 52,
  ),
  GamepadButton(
    id: 'btn_y',
    label: 'Y',
    keyCode: 100,
    alternateKeyCodes: [37],
    center: Offset(0.5826, 0.5628),
    size: 52,
  ),
  GamepadButton(
    id: 'btn_a',
    label: 'A',
    keyCode: 96,
    alternateKeyCodes: [35],
    center: Offset(0.7251, 0.5617),
    size: 52,
  ),
  GamepadButton(
    id: 'btn_b',
    label: 'B',
    keyCode: 97,
    alternateKeyCodes: [38],
    center: Offset(0.6539, 0.6937),
    size: 52,
  ),
  GamepadButton(
    id: 'btn_star',
    label: '★',
    keyCode: 17,
    alternateKeyCodes: [],
    center: Offset(0.4302, 0.7071),
    size: 44,
  ),
  GamepadButton(
    id: 'btn_home',
    label: '♥',
    keyCode: 3,
    alternateKeyCodes: [47],
    center: Offset(0.5156, 0.7071),
    size: 44,
  ),
];
