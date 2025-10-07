// lib/login_page.dart
import 'package:flutter/material.dart';
import 'home_page.dart'; // <-- your existing HomePage

enum AuthMode { none, signIn, signUp }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  AuthMode _mode = AuthMode.none;
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    // TODO: replace with your real sign-in/up calls
    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;
    // Simple mock “failure” if username is 'fail'
    if (_userCtrl.text.trim().toLowerCase() == 'fail') {
      setState(() {
        _loading = false;
        _error = 'Authentication failed. Try another username.';
      });
      return;
    }

    // On success, go to HomePage and remove login from back stack
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  void _pickMode(AuthMode m) {
    setState(() {
      _mode = m;
      _error = null;
      _userCtrl.clear();
      _passCtrl.clear();
    });
  }

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
              child: _mode == AuthMode.none
                  ? _buildChoice(cs)
                  : _buildForm(cs),
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
        const Text('Stock Scout', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.login),
            label: const Text('Sign In'),
            onPressed: () => _pickMode(AuthMode.signIn),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.person_add),
            label: const Text('Sign Up'),
            onPressed: () => _pickMode(AuthMode.signUp),
          ),
        ),
        // (Logout button removed from Login page)
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
              Text(isSignIn ? 'Sign In' : 'Sign Up',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _userCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a username' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onFieldSubmitted: (_) => _authenticate(),
            validator: (v) => (v == null || v.length < 4) ? 'Min 4 characters' : null,
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
                  ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isSignIn ? 'Continue' : 'Create Account'),
            ),
          ),
        ],
      ),
    );
  }
}
