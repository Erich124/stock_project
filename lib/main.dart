// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'login_page.dart';
import 'home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Optional: forward framework errors to the zone so they don't crash silently.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
    // If init fails, show a readable error UI instead of a hard crash.
    runApp(_InitErrorApp(error: e, stack: st));
    return;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stock Project',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoginPage(), // Start at your login screen
      routes: {
        '/home': (_) => const HomePage(),
      },
    );
  }
}

/// Simple error app to surface Firebase init issues during setup.
class _InitErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace? stack;
  const _InitErrorApp({required this.error, this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Firebase Init Error')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: SelectableText(
              'Firebase failed to initialize:\n\n$error\n\n$stack',
            ),
          ),
        ),
      ),
    );
  }
}
