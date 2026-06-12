import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/services.dart';
import '../../utils/app_theme.dart';

/// Guest-first account screen. A guest can create an account (links to the same
/// uid, keeping their data) or sign into an existing one. Reached from More.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _registerMode = true; // true = create account, false = sign in
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AppUser> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (e.code == 'cancelled') return; // user backed out — say nothing
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submitEmail() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text;
    final password = _passwordCtrl.text;
    _run(() => _registerMode
        ? Services.auth.registerWithEmail(email, password)
        : Services.auth.signInWithEmail(email, password));
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_registerMode ? 'Create Account' : 'Sign In'),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 8),
            Text(
              _registerMode
                  ? 'Create an account to access your groups on any device. '
                      'Your current data stays with you.'
                  : 'Sign in to load your account on this device.',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline, size: 20),
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return 'Enter your email';
                      if (!s.contains('@') || !s.contains('.')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submitEmail(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) {
                      if ((v ?? '').isEmpty) return 'Enter a password';
                      if (_registerMode && v!.length < 6) {
                        return 'Use at least 6 characters';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _submitEmail,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_registerMode ? 'Create Account' : 'Sign In'),
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(child: Divider(color: AppTheme.divider)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ),
                Expanded(child: Divider(color: AppTheme.divider)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(Services.auth.signInWithGoogle),
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: const Text('Continue with Google'),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _registerMode = !_registerMode),
                child: Text(_registerMode
                    ? 'Already have an account? Sign in'
                    : 'New here? Create an account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
