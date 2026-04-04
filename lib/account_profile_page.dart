import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'login_page.dart';

class AccountProfilePage extends StatefulWidget {
  const AccountProfilePage({super.key});

  @override
  State<AccountProfilePage> createState() => _AccountProfilePageState();
}

class _AccountProfilePageState extends State<AccountProfilePage> {
  bool _busy = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final user = _user;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete account?'),
          content: const Text(
            'This permanently deletes your account and clears your saved app '
            'data, including recent views and search history. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _reauthenticateIfNeeded(user);
      await _deleteFirestoreUserData(user.uid);
      await user.delete();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } on _DeletionCancelledException {
      // User backed out of reauthentication.
    } on FirebaseAuthException catch (e) {
      await _showMessage(_friendlyAuthError(e));
    } catch (e) {
      await _showMessage('Account deletion failed. Please try again. ($e)');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _reauthenticateIfNeeded(User user) async {
    if (user.isAnonymous) {
      return;
    }

    final providerIds = user.providerData
        .map((info) => info.providerId)
        .where((id) => id != 'firebase')
        .toSet();

    if (providerIds.contains('password')) {
      final email = user.email;
      if (email == null) {
        throw FirebaseAuthException(
          code: 'missing-email',
          message: 'This account is missing an email address.',
        );
      }
      final password = await _promptForPassword(email);
      if (password == null) {
        throw const _DeletionCancelledException();
      }
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (!kIsWeb && Platform.isIOS && providerIds.contains('apple.com')) {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      final result = await user.reauthenticateWithProvider(provider);
      final authCode = result.additionalUserInfo?.authorizationCode;
      if (authCode != null && authCode.isNotEmpty) {
        await FirebaseAuth.instance.revokeTokenWithAuthorizationCode(authCode);
      }
      return;
    }

    if (providerIds.contains('google.com')) {
      await user.reauthenticateWithProvider(GoogleAuthProvider());
      return;
    }
  }

  Future<String?> _promptForPassword(String email) async {
    final controller = TextEditingController();
    bool obscure = true;

    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Confirm password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter the password for $email to delete this account.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                    onSubmitted: (_) =>
                        Navigator.of(context).pop(controller.text.trim()),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(controller.text.trim()),
                  child: const Text('Continue'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    if (password == null || password.isEmpty) {
      return null;
    }
    return password;
  }

  Future<void> _deleteFirestoreUserData(String uid) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    for (final name in const [
      'settings',
      'search_history',
      'searches',
      'recent_views',
    ]) {
      await _deleteCollection(userRef.collection(name));
    }

    await userRef.delete();
  }

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final snapshot = await collection.limit(200).get();
      if (snapshot.docs.isEmpty) {
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _showMessage(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'requires-recent-login':
        return 'Please sign in again, then retry account deletion.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Password was incorrect. Please try again.';
      case 'network-request-failed':
        return 'Network error while deleting your account. Please try again.';
      default:
        return e.message ?? 'Account deletion failed.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final cs = Theme.of(context).colorScheme;
    final name = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : 'Account';
    final email = user?.email ?? 'Guest session';
    final providerSummary = user == null || user.isAnonymous
        ? 'Signed in as guest'
        : user.providerData
              .map((provider) => provider.providerId)
              .where((id) => id != 'firebase')
              .map(_providerLabel)
              .join(', ');

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.person,
                          color: cs.onSurface.withValues(alpha: 0.55),
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.72),
                              ),
                            ),
                            if (providerSummary.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                providerSummary,
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.62),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Account deletion'),
                      subtitle: const Text(
                        'Profile -> Delete Account permanently removes your account and app data.',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Log out'),
                      subtitle: const Text('Sign out on this device'),
                      enabled: !_busy,
                      onTap: _busy ? null : _signOut,
                    ),
                    if (user != null && !user.isAnonymous) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.delete_forever, color: cs.error),
                        title: Text(
                          'Delete Account',
                          style: TextStyle(color: cs.error),
                        ),
                        subtitle: const Text(
                          'Permanently delete your account and saved data',
                        ),
                        enabled: !_busy,
                        onTap: _busy ? null : _confirmDeleteAccount,
                      ),
                    ],
                  ],
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _providerLabel(String providerId) {
    switch (providerId) {
      case 'password':
        return 'Email and password';
      case 'google.com':
        return 'Google';
      case 'apple.com':
        return 'Apple';
      default:
        return providerId;
    }
  }
}

class _DeletionCancelledException implements Exception {
  const _DeletionCancelledException();
}
