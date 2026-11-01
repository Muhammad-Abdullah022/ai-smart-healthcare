import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/mental_repository.dart';
import '../../widgets/app_button.dart';

/// One step of a breathing pattern.
class BreathStep {
  const BreathStep(this.label, this.seconds, this.expand);
  final String label;
  final int seconds;
  final bool? expand; // true = grow circle, false = shrink, null = hold
}

const breathingPatterns = <String, (String, List<BreathStep>)>{
  'box': ('Box breathing (4-4-4-4)', [
    BreathStep('Breathe in', 4, true),
    BreathStep('Hold', 4, null),
    BreathStep('Breathe out', 4, false),
    BreathStep('Hold', 4, null),
  ]),
  '4-7-8': ('4-7-8 relaxing breath', [
    BreathStep('Breathe in', 4, true),
    BreathStep('Hold', 7, null),
    BreathStep('Breathe out slowly', 8, false),
  ]),
  'calm': ('Calm breathing (5-5)', [
    BreathStep('Breathe in', 5, true),
    BreathStep('Breathe out', 5, false),
  ]),
};

/// Feature 22: guided breathing with an animated circle and a timer.
class BreathingScreen extends StatefulWidget {
  const BreathingScreen({super.key, this.repository});

  final MentalRepository? repository;

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen> {
  late final MentalRepository _repo =
      widget.repository ?? MentalRepository(context.read<AuthProvider>().repository.api);
  String _pattern = 'box';
  int _minutes = 2;
  Timer? _timer;
  int _elapsed = 0; // seconds since start
  bool get _running => _timer != null;

  List<BreathStep> get _steps => breathingPatterns[_pattern]!.$2;
  int get _cycle => _steps.fold(0, (sum, s) => sum + s.seconds);

  /// Index of the step we are in, and how many seconds remain in it.
  (int, int) get _current {
    var t = _elapsed % _cycle;
    for (var i = 0; i < _steps.length; i++) {
      if (t < _steps[i].seconds) return (i, _steps[i].seconds - t);
      t -= _steps[i].seconds;
    }
    return (0, _steps.first.seconds);
  }

  /// Circle size for a step; "hold" keeps the size of the step before it.
  double _sizeFor(int index) {
    for (var k = 0; k < _steps.length; k++) {
      final s = _steps[(index - k) % _steps.length];
      if (s.expand != null) return s.expand! ? 220 : 110;
    }
    return 140;
  }

  void _start() {
    setState(() => _elapsed = 0);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed++);
      if (_elapsed >= _minutes * 60) _stop(completed: true);
    });
  }

  Future<void> _stop({bool completed = false}) async {
    _timer?.cancel();
    final seconds = _elapsed;
    setState(() => _timer = null);
    if (seconds >= 10) {
      try {
        await _repo.saveBreathing(_pattern, seconds);
      } on ApiException {
        // Saving history is optional; the exercise itself already helped.
      }
    }
    if (completed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Well done! Session saved.')));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (index, remaining) = _current;
    final step = _steps[index];
    final size = _running ? _sizeFor(index) : 140.0;
    return Scaffold(
      appBar: AppBar(title: const Text('Breathing exercise')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _pattern,
            decoration: const InputDecoration(labelText: 'Pattern'),
            items: [
              for (final e in breathingPatterns.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1)),
            ],
            onChanged: _running ? null : (v) => setState(() => _pattern = v!),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Length:'),
              const SizedBox(width: 8),
              for (final m in [1, 2, 5])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$m min'),
                    selected: _minutes == m,
                    onSelected: _running ? null : (_) => setState(() => _minutes = m),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 240,
            child: Center(
              child: AnimatedContainer(
                duration: Duration(seconds: _running && step.expand != null ? step.seconds : 0),
                curve: Curves.easeInOut,
                width: size,
                height: size,
                decoration: const BoxDecoration(color: AppColors.accentTint, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(
                  _running ? '${step.label}\n$remaining' : 'Ready',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_running)
            LinearProgressIndicator(value: _elapsed / (_minutes * 60), color: AppColors.accent),
          const SizedBox(height: 24),
          AppButton(
            label: _running ? 'Stop' : 'Start',
            icon: _running ? Icons.stop : Icons.play_arrow,
            outlined: _running,
            onPressed: _running ? () => _stop() : _start,
          ),
          const SizedBox(height: 12),
          const Text(
            'Stop if you feel dizzy or unwell, and breathe normally.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
