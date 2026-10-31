import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_button.dart';

class _Page {
  const _Page(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const _pages = [
  _Page(Icons.medical_services_outlined, 'Understand your symptoms',
      'Describe how you feel and get clear, simple health information and next steps.'),
  _Page(Icons.medication_outlined, 'Manage medicines & records',
      'Keep prescriptions, reports and reminders together in one secure place.'),
  _Page(Icons.health_and_safety_outlined, 'Your safety comes first',
      'This app does not replace a doctor. In an emergency, call 1122 or go to the nearest '
          'hospital immediately. Your health data stays private and under your control.'),
];

/// Three intro pages, shown only on the first launch.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      context.read<AuthProvider>().completeOnboarding();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.read<AuthProvider>().completeOnboarding(),
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final page = _pages[i];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 80,
                          backgroundColor: AppColors.accentTint,
                          child: Icon(page.icon, size: 80, color: AppColors.accent),
                        ),
                        const SizedBox(height: 40),
                        Text(page.title,
                            textAlign: TextAlign.center,
                            style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700, color: AppColors.primary)),
                        const SizedBox(height: 16),
                        Text(page.body,
                            textAlign: TextAlign.center,
                            style: textTheme.bodyLarge?.copyWith(color: AppColors.textMuted, height: 1.5)),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index ? AppColors.accent : AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              AppButton(label: _isLast ? 'Get started' : 'Next', onPressed: _next),
            ],
          ),
        ),
      ),
    );
  }
}
