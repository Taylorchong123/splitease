import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'features/auth/login_screen.dart';
import 'features/tickets/tickets_screen.dart';

class SplitEaseApp extends StatelessWidget {
  const SplitEaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SplitEase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: const AuthGate(),
    );
  }
}

/// Shows the login screen or the tickets list depending on auth state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.hasData ? const TicketsScreen() : const LoginScreen();
      },
    );
  }
}
