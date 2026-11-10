import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/router_provider.dart';
import '../services/auth_service.dart';
import '../utils/validators.dart';
import '../widgets/auth_form.dart';

/// Sign in (FR-01).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signIn(_email.text, _password.text);
      // No navigation here: the router redirect reacts to the sign-in.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Sign in to split your receipts',
      children: [
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                validator: Validators.email,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _password,
                // Only check it's filled in; length rules are for sign up.
                validator: (v) => Validators.requiredText(v, 'your password'),
                onSubmitted: _submit,
              ),
              const SizedBox(height: 16),
              if (_error != null) ErrorBanner(_error!),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sign in'),
              ),
              TextButton(
                onPressed: _busy ? null : () => context.push(Routes.signup),
                child: const Text("Don't have an account? Sign up"),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
