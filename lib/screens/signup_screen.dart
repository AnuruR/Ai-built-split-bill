import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../utils/validators.dart';
import '../widgets/auth_form.dart';

/// Register (FR-01).
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final signedIn =
          await ref.read(authServiceProvider).signUp(_name.text, _email.text, _password.text);
      if (!mounted) return;
      if (!signedIn) {
        // "Confirm email" is ON in Supabase: the user must click the link.
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Check your email'),
            content: Text('We sent a confirmation link to ${_email.text.trim()}. '
                'Open it, then sign in.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
          ),
        );
        if (mounted) context.pop();
      }
      // If signed in, the router redirect goes to Home by itself.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) =>
        InputDecoration(labelText: label, border: const OutlineInputBorder());
    return AuthScaffold(
      title: 'Create your account',
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: deco('Your name'),
                validator: (v) => Validators.requiredText(v, 'your name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: deco('Email'),
                validator: Validators.email,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _password,
                action: TextInputAction.next,
                validator: Validators.password,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _confirm,
                label: 'Confirm password',
                validator: (v) => Validators.confirmPassword(v, _password.text),
                onSubmitted: _submit,
              ),
              const SizedBox(height: 16),
              if (_error != null) ErrorBanner(_error!),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create account'),
              ),
              TextButton(
                onPressed: _busy ? null : () => context.pop(),
                child: const Text('Already have an account? Sign in'),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
