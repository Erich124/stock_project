// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'pages/history_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Surface framework errors instead of silently swallowing them.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
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

      // Show LoginPage if signed out; HomePage if signed in.
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _Splash();
          }
          final user = snap.data;
          if (user == null) {
            return const LoginPage();
          }
          return const HomePage();
        },
      ),

      // App routes
      routes: {
        '/home': (_) => const HomePage(),
        '/history': (_) => const HistoryPage(),
      },
    );
  }
}

/// Minimal splash while Firebase/Auth resolves.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
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
