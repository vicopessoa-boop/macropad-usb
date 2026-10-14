import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/macropad_connection.dart';
import 'services/settings_store.dart';
import 'ui/macropad_screen.dart';
import 'ui/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Tela cheia: o celular vira um periférico dedicado.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final settings = await ConnectionSettings.load();
  final connection = MacropadConnection(host: settings.host, port: settings.port, token: settings.token)..start();
  runApp(MacropadApp(connection: connection));
}

class MacropadApp extends StatelessWidget {
  final MacropadConnection connection;
  const MacropadApp({super.key, required this.connection});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Macropad USB',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Palette.background,
        colorScheme: ColorScheme.fromSeed(seedColor: Palette.blue, brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: MacropadScreen(connection: connection),
    );
  }
}
