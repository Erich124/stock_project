// lib/account_profile_page.dart
import 'package:flutter/material.dart';
import 'login_page.dart';

class AccountProfilePage extends StatelessWidget {
  const AccountProfilePage({super.key});

  static const String _displayName = 'name';
  static const String _userId = '#A123456';

  Future<void> _logout(BuildContext context) async {
    // clear session/tokens here if needed...
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: cs.surfaceContainerHighest,
                    child: Icon(Icons.person, color: cs.onSurface.withOpacity(0.5), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('name', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(_userId, style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.7))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                  onPressed: () => _logout(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
