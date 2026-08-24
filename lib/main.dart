import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const TapVoiceApp());
}

class TapVoiceApp extends StatelessWidget {
  const TapVoiceApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TapVoice',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: false,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
      scaffoldBackgroundColor: Colors.white,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
    ),
    home: const HomePage(),
  );
}
