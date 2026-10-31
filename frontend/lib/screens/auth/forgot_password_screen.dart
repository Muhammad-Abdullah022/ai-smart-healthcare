import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../utils/validators.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import 'auth_header.dart';

/// Forgot-password screen.
///
/// NOTE: Sending the reset email needs the email service (tracker task C-09),
/// which is not connected yet. Until then this screen validates the email and
/// tells the user honestly that reset emails are not available.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthHeader(
                  title: 'Reset your password',
                  subtitle: "Enter your account email and we'll send you a reset link.",
                ),
                AppTextField(
                  label: 'Email',
                  controller: _email,
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
                if (_submitted)
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.warningTint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Password reset by email is not available yet — the email service is still '
                      'being set up. Please contact support to reset your password.',
                    ),
                  ),
                AppButton(label: 'Send reset link', onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
