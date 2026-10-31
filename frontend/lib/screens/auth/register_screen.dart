import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../utils/validators.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/error_banner.dart';
import 'auth_header.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _accepted = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (!_accepted) {
      setState(() => _error = 'Please accept the terms and privacy policy to continue.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().register(
            fullName: _name.text,
            email: _email.text,
            password: _password.text,
            acceptedTerms: _accepted,
          );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthHeader(title: 'Create your account', subtitle: 'It takes less than a minute.'),
                AppTextField(
                  label: 'Full name',
                  controller: _name,
                  icon: Icons.person_outline,
                  validator: Validators.fullName,
                  autofillHints: const [AutofillHints.name],
                ),
                AppTextField(
                  label: 'Email',
                  controller: _email,
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                  autofillHints: const [AutofillHints.email],
                ),
                AppTextField(
                  label: 'Password',
                  controller: _password,
                  hint: 'At least 8 characters, with a number',
                  icon: Icons.lock_outline,
                  isPassword: true,
                  validator: Validators.password,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                AppTextField(
                  label: 'Confirm password',
                  controller: _confirm,
                  icon: Icons.lock_outline,
                  isPassword: true,
                  validator: Validators.confirmPassword(() => _password.text),
                  textInputAction: TextInputAction.done,
                ),
                CheckboxListTile(
                  value: _accepted,
                  onChanged: (v) => setState(() => _accepted = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.accent,
                  title: const Text(
                    'I agree to the Terms and Privacy Policy, and understand this app does not '
                    'replace professional medical advice.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                if (_error != null) ErrorBanner(_error!),
                AppButton(label: 'Create account', loading: _loading, onPressed: _submit),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account?'),
                    TextButton(onPressed: () => context.go('/login'), child: const Text('Log in')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
