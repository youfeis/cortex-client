import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'cortex.dart';
import 'screens.dart';

const ink = Color(0xFF2D4135);
const muted = Color(0xFF74816C);
const paper = Color(0xFFF8FAF5);
const line = Color(0xFFDEE5D7);
const soft = Color(0xFFEFF3E8);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarBrightness: Brightness.light),
  );
  runApp(const CortexApp());
}

class CortexApp extends StatelessWidget {
  const CortexApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'External Prefrontal Cortex',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ink,
        primary: ink,
        surface: paper,
        secondary: muted,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: ink, fontSize: 15, height: 1.45),
        bodyLarge: TextStyle(color: ink, fontSize: 16, height: 1.45),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 46),
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: line),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: soft,
        height: 66,
        surfaceTintColor: Colors.transparent,
      ),
    ),
    home: const CortexRoot(),
  );
}

class CortexRoot extends StatefulWidget {
  const CortexRoot({super.key});
  @override
  State<CortexRoot> createState() => _CortexRootState();
}

class _CortexRootState extends State<CortexRoot> with WidgetsBindingObserver {
  final model = CortexModel();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && model.paired) {
      model.refresh().catchError((_) {});
      model.readAccount().catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      if (model.initializing) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (model.startupError != null) {
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 42),
                  const SizedBox(height: 20),
                  Text(model.startupError!, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: model.initialize,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      if (!model.paired) {
        return PairScreen(model: model);
      }
      return HomeScreen(model: model);
    },
  );
}
