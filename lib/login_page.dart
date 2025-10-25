// lib/login_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'home_page.dart';

enum AuthMode { none, signIn, signUp }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  AuthMode _mode = AuthMode.none;
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // --- Helpers ---------------------------------------------------------------

  Future<void> _ensureUserDoc(User user, {String? email, String? displayName, String? photoUrl}) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await docRef.get();
    if (!snap.exists) {
      await docRef.set({
        'email': email ?? user.email,
        'displayName': displayName ?? user.displayName,
        'photoUrl': photoUrl ?? user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Light touch update on subsequent sign-ins
      await docRef.update({
        'email': email ?? user.email,
        'displayName': displayName ?? user.displayName,
        'photoUrl': photoUrl ?? user.photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  String _prettyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
        return 'Incorrect password. Try again.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled in Firebase Console.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return e.message ?? 'Authentication failed. (${e.code})';
    }
  }

  void _pickMode(AuthMode m) {
    setState(() {
      _mode = m;
      _error = null;
      _emailCtrl.clear();
      _passCtrl.clear();
    });
  }

  Future<void> _goHome() async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
  }

  // --- Email/Password flows --------------------------------------------------

  Future<void> _authenticate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final email = _emailCtrl.text.trim();
      final pwd = _passCtrl.text.trim();
      UserCredential cred;

      if (_mode == AuthMode.signIn) {
        cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pwd);
      } else {
        // If currently anonymous, link to preserve UID/data.
        final current = FirebaseAuth.instance.currentUser;
        if (current != null && current.isAnonymous) {
          final epCred = EmailAuthProvider.credential(email: email, password: pwd);
          cred = await current.linkWithCredential(epCred);
        } else {
          cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pwd);
          // Optionally: await cred.user?.sendEmailVerification();
        }
      }

      await _ensureUserDoc(cred.user!, email: _emailCtrl.text.trim());
      await _goHome();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _prettyAuthError(e));
    } catch (e) {
      setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email above, then tap "Forgot password".');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent. Check your inbox.')),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _prettyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- Anonymous (Guest) -----------------------------------------------------

  Future<void> _signInAnon() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      await _ensureUserDoc(cred.user!, displayName: 'Guest');
      await _goHome();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _prettyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- Google Sign-In (Android ready; SHA-1/256 configured) ------------------

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      final gUser = await GoogleSignIn().signIn();
      if (gUser == null) {
        setState(() => _error = 'Google sign-in canceled.');
        return;
      }
      final gAuth = await gUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: gAuth.idToken,
        accessToken: gAuth.accessToken,
      );

      // If currently anonymous, prefer linking so data/UID is preserved.
      final current = FirebaseAuth.instance.currentUser;
      UserCredential cred;
      if (current != null && current.isAnonymous) {
        cred = await current.linkWithCredential(credential);
      } else {
        cred = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      final user = cred.user!;
      await _ensureUserDoc(
        user,
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoURL,
      );
      await _goHome();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _prettyAuthError(e));
    } catch (e) {
      setState(() => _error = 'Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _mode == AuthMode.none ? _buildChoice(cs) : _buildForm(cs),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChoice(ColorScheme cs) {
    return Column(
      key: const ValueKey('choice'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Stock Scout',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.login),
            label: const Text('Sign In'),
            onPressed: _loading ? null : () => _pickMode(AuthMode.signIn),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.person_add),
            label: const Text('Sign Up'),
            onPressed: _loading ? null : () => _pickMode(AuthMode.signUp),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.account_circle),
            label: const Text('Sign in with Google'),
            onPressed: _loading ? null : _signInWithGoogle,
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _loading ? null : _signInAnon,
          icon: const Icon(Icons.rocket_launch),
          label: const Text('Continue as Guest'),
        ),
      ],
    );
  }

  Widget _buildForm(ColorScheme cs) {
    final isSignIn = _mode == AuthMode.signIn;
    return Form(
      key: _formKey,
      child: Column(
        key: ValueKey(_mode),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: _loading ? null : () => _pickMode(AuthMode.none),
              ),
              Text(
                isSignIn ? 'Sign In' : 'Sign Up',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailCtrl,
            enabled: !_loading,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passCtrl,
            enabled: !_loading,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: _loading ? null : () => setState(() => _obscure = !_obscure),
              ),
            ),
            onFieldSubmitted: (_) => _authenticate(),
            validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _loading ? null : _authenticate,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isSignIn ? 'Continue' : 'Create Account'),
            ),
          ),
          if (isSignIn) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loading ? null : _forgotPassword,
                child: const Text('Forgot password?'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
