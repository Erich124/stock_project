import 'package:flutter/material.dart';
import 'login_page.dart';

class AccountProfilePage extends StatelessWidget {
  const AccountProfilePage({super.key});

  static const String _displayName = 'name';   // <-- changed here
  static const String _userId = '#A123456';

  Future<void> _logout(BuildContext context) async {
    // TODO: clear tokens/secure storage/session here if needed
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Account Profile')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- Top header: blank avatar + name + id ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Blank circular avatar
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: cs.surfaceContainerHighest,
                    child: Icon(
                      Icons.person,
                      color: cs.onSurface.withOpacity(0.5),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _userId,
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // --- Logout button ---
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

      // Bottom tabs: Home / Profile
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        onDestinationSelected: (i) {
          if (i == 0) {
            Navigator.of(context).pop(); // back to Home
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
