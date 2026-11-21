import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/mental_repository.dart';
import '../../widgets/state_views.dart';

/// One guided step: what to do and for how long.
class GuideStep {
  const GuideStep(this.text, this.seconds);
  final String text;
  final int seconds;
}

class WellnessSession {
  const WellnessSession(this.title, this.kind, this.icon, this.steps);
  final String title;
  final String kind;
  final IconData icon;
  final List<GuideStep> steps;

  int get seconds => steps.fold(0, (a, s) => a + s.seconds);
  int get minutes => (seconds / 60).ceil();
}

const _settle = GuideStep('Sit comfortably. Let your shoulders drop. Close your eyes or look softly at the floor.', 20);
const _close = GuideStep('Slowly open your eyes. Notice how you feel now. Well done.', 15);

/// The 7-day plan: each day = a breathing practice, a mindfulness practice and a small reflection.
final List<(String, List<WellnessSession>)> wellnessPlan = [
  ('Arrive and breathe', const [
    WellnessSession('Calm breathing', 'Breathing', Icons.air, [
      _settle,
      GuideStep('Breathe in through your nose for 4… and out through your mouth for 6.', 60),
      GuideStep('Keep the same slow rhythm. In for 4… out for 6.', 60),
      _close,
    ]),
    WellnessSession('Body scan', 'Mindfulness', Icons.accessibility_new, [
      _settle,
      GuideStep('Bring your attention to your feet. Notice warmth, weight, any tightness.', 40),
      GuideStep('Move slowly up to your legs and hips. Let them be heavy.', 40),
      GuideStep('Notice your stomach and chest rising and falling.', 40),
      GuideStep('Relax your shoulders, jaw and forehead.', 40),
      _close,
    ]),
    WellnessSession('Three good things', 'Reflection', Icons.favorite_border, [
      GuideStep('Think of one good thing that happened today, however small.', 40),
      GuideStep('Think of a second good thing. Who or what made it happen?', 40),
      GuideStep('Think of a third. Notice the feeling it brings.', 40),
    ]),
  ]),
  ('Notice the present', const [
    WellnessSession('Box breathing', 'Breathing', Icons.crop_square, [
      _settle,
      GuideStep('In for 4… hold for 4… out for 4… hold for 4.', 60),
      GuideStep('Again: in 4, hold 4, out 4, hold 4. Keep it gentle.', 60),
      _close,
    ]),
    WellnessSession('5-4-3-2-1 grounding', 'Mindfulness', Icons.visibility_outlined, [
      GuideStep('Name 5 things you can see around you.', 30),
      GuideStep('Name 4 things you can feel: your clothes, the chair, the air…', 30),
      GuideStep('Name 3 things you can hear.', 30),
      GuideStep('Name 2 things you can smell, and 1 thing you can taste.', 30),
      _close,
    ]),
    WellnessSession('Kind words to yourself', 'Reflection', Icons.sentiment_satisfied_alt, [
      GuideStep('Think of something you are finding hard right now.', 30),
      GuideStep('What would you say to a close friend in the same situation? Say it to yourself.', 45),
      GuideStep('Repeat quietly: "I am doing my best, and that is enough for today."', 30),
    ]),
  ]),
  ('Release tension', const [
    WellnessSession('Slow exhale', 'Breathing', Icons.air, [
      _settle,
      GuideStep('Breathe in for 4, then breathe out slowly for 8, like blowing through a straw.', 60),
      GuideStep('Long, slow breaths out. Let each one carry tension away.', 60),
      _close,
    ]),
    WellnessSession('Muscle relaxation', 'Mindfulness', Icons.fitness_center, [
      GuideStep('Make tight fists for 5 seconds… then let go. Feel the difference.', 30),
      GuideStep('Lift your shoulders to your ears… hold… and drop them.', 30),
      GuideStep('Scrunch your face… hold… and relax it completely.', 30),
      GuideStep('Tighten your legs and feet… hold… and release.', 30),
      _close,
    ]),
    WellnessSession('Let go of one worry', 'Reflection', Icons.cloud_outlined, [
      GuideStep('Notice one worry in your mind. Name it in a few words.', 30),
      GuideStep('Is it something you can act on today? If yes, pick one small step.', 40),
      GuideStep('If not, imagine placing it on a cloud and watching it drift away.', 40),
    ]),
  ]),
  ('Mindful moments', const [
    WellnessSession('Counting breaths', 'Breathing', Icons.filter_1, [
      _settle,
      GuideStep('Count each breath out: one… two… up to ten, then start again.', 90),
      GuideStep('If your mind wanders, that is fine. Just start again at one.', 45),
      _close,
    ]),
    WellnessSession('Mindful sip of tea', 'Mindfulness', Icons.local_cafe_outlined, [
      GuideStep('Hold a cup of tea or water. Notice its warmth or coolness.', 30),
      GuideStep('Look at it closely, smell it, take one slow sip.', 40),
      GuideStep('Notice the taste and the feeling as you swallow.', 30),
    ]),
    WellnessSession('Someone I am thankful for', 'Reflection', Icons.people_outline, [
      GuideStep('Think of a person who has helped you.', 30),
      GuideStep('Remember one thing they did. How did it make you feel?', 40),
      GuideStep('Think of a way to thank them this week, even with a message.', 30),
    ]),
  ]),
  ('Better sleep', const [
    WellnessSession('4-7-8 breathing', 'Breathing', Icons.bedtime_outlined, [
      _settle,
      GuideStep('In through your nose for 4… hold for 7… out through your mouth for 8.', 60),
      GuideStep('Again, slowly: 4… 7… 8. Let your body get heavy.', 60),
      _close,
    ]),
    WellnessSession('Sleep wind-down', 'Mindfulness', Icons.nightlight_outlined, [
      GuideStep('Lie down. Put your phone away after this session.', 20),
      GuideStep('Let your whole body sink into the bed, from head to toe.', 45),
      GuideStep('Imagine a calm place. Notice its colours, sounds and smells.', 60),
    ]),
    WellnessSession('Tomorrow, one thing', 'Reflection', Icons.wb_sunny_outlined, [
      GuideStep('Think of one small thing you want to do tomorrow.', 30),
      GuideStep('Picture yourself doing it calmly. Then let the day go.', 40),
    ]),
  ]),
  ('Gentle movement', const [
    WellnessSession('Energising breath', 'Breathing', Icons.bolt_outlined, [
      _settle,
      GuideStep('Breathe in deeply for 4, out for 4. Sit up tall.', 60),
      GuideStep('Stretch your arms up as you breathe in, lower them as you breathe out.', 60),
      _close,
    ]),
    WellnessSession('Desk stretches', 'Movement', Icons.self_improvement, [
      GuideStep('Roll your shoulders backwards slowly, 5 times.', 30),
      GuideStep('Tilt your head gently to each side. No pain, just a stretch.', 30),
      GuideStep('Stand up, reach to the sky, then let your arms hang loose.', 30),
      GuideStep('Walk slowly for a minute, noticing each step.', 60),
    ]),
    WellnessSession('What helped this week', 'Reflection', Icons.lightbulb_outline, [
      GuideStep('Which session helped you most so far?', 30),
      GuideStep('When in your day could you use it again?', 30),
    ]),
  ]),
  ('Your own routine', const [
    WellnessSession('Calm breathing', 'Breathing', Icons.air, [
      _settle,
      GuideStep('In for 4… out for 6. Your breath is always with you.', 90),
      _close,
    ]),
    WellnessSession('Open awareness', 'Mindfulness', Icons.blur_on, [
      _settle,
      GuideStep('Notice sounds, body feelings and thoughts coming and going, without holding on.', 90),
      _close,
    ]),
    WellnessSession('My plan from here', 'Reflection', Icons.flag_outlined, [
      GuideStep('Choose one practice you will keep doing every day.', 30),
      GuideStep('Choose a time for it, e.g. after Fajr or before sleep.', 30),
      GuideStep('Well done for finishing 7 days. Be proud of yourself.', 20),
    ]),
  ]),
];

/// Feature 23: Meditation & wellness plan.
class WellnessPlanScreen extends StatefulWidget {
  const WellnessPlanScreen({super.key});

  @override
  State<WellnessPlanScreen> createState() => _WellnessPlanScreenState();
}

class _WellnessPlanScreenState extends State<WellnessPlanScreen> {
  late final MentalRepository _repo = MentalRepository(context.read<AuthProvider>().repository.api);
  Map<String, dynamic>? _state;
  Object? _error;
  int? _openDay;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _repo.wellnessPlan();
      if (mounted) setState(() => _state = s);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  bool _done(int day, int session) => (_state?['completed'] as List? ?? const [])
      .any((c) => (c as Map)['day'] == day && c['session'] == session);

  Future<void> _start(int day, int session) async {
    final s = wellnessPlan[day - 1].$2[session - 1];
    final finished = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => _SessionPlayer(session: s, dayTitle: 'Day $day')));
    if (finished == true) {
      try {
        final st = await _repo.completeWellness(day, session, s.minutes);
        if (mounted) setState(() => _state = st);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _state;
    if (st == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Wellness plan')),
        body: _error != null ? ErrorView(message: '$_error', onRetry: _load) : const LoadingView(),
      );
    }
    final total = wellnessPlan.length * 3;
    final doneCount = (st['completed'] as List).length;
    final current = (st['current_day'] as int?) ?? 1;
    final openDay = _openDay ?? current;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Meditation & wellness plan'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) async {
              final s = await _repo.restartWellness();
              if (mounted) setState(() {
                _state = s;
                _openDay = null;
              });
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'restart', child: Text('Start the plan again'))],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.mind, Color(0xFF5B4BC4)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(children: [
            SizedBox(
              width: 74,
              height: 74,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: 74,
                  height: 74,
                  child: CircularProgressIndicator(
                    value: doneCount / total,
                    strokeWidth: 7,
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                  ),
                ),
                Text('${(doneCount * 100 / total).round()}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st['finished'] == true ? 'Plan complete!' : 'Day $current of 7',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('$doneCount of $total sessions · ${st['total_minutes']} min practised',
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(st['practised_today'] == true ? 'You practised today. Well done!' : 'About 10 minutes a day.',
                    style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        for (var d = 1; d <= wellnessPlan.length; d++) _dayCard(d, current, openDay),
        const SizedBox(height: 8),
        const Text(
          'These are relaxation exercises, not treatment. If you feel low most days or have thoughts of hurting '
          'yourself, please talk to a doctor or call 1122.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ]),
    );
  }

  Widget _dayCard(int day, int current, int openDay) {
    final (title, sessions) = wellnessPlan[day - 1];
    final allDone = [for (var i = 1; i <= sessions.length; i++) _done(day, i)].every((x) => x);
    final locked = day > current;
    final open = openDay == day;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: day == current ? AppColors.mind : AppColors.border, width: day == current ? 1.5 : 1),
      ),
      child: Column(children: [
        ListTile(
          onTap: locked ? null : () => setState(() => _openDay = open ? -1 : day),
          leading: CircleAvatar(
            backgroundColor: allDone ? AppColors.success : (locked ? const Color(0xFFE5E7EB) : AppColors.mindTint),
            child: allDone
                ? const Icon(Icons.check, color: Colors.white)
                : Text('$day',
                    style: TextStyle(color: locked ? AppColors.textMuted : AppColors.mind, fontWeight: FontWeight.w800)),
          ),
          title: Text('Day $day · $title', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(locked
              ? 'Unlocks after day ${day - 1}'
              : '${sessions.fold(0, (a, s) => a + s.minutes)} min · ${sessions.length} sessions'),
          trailing: Icon(locked ? Icons.lock_outline : (open ? Icons.expand_less : Icons.expand_more),
              color: AppColors.textMuted),
        ),
        if (open && !locked)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: [
              for (var i = 1; i <= sessions.length; i++)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: Icon(sessions[i - 1].icon, color: AppColors.mind),
                    title: Text(sessions[i - 1].title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${sessions[i - 1].kind} · ${sessions[i - 1].minutes} min'),
                    trailing: _done(day, i)
                        ? const Icon(Icons.check_circle, color: AppColors.success)
                        : FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: AppColors.mind, visualDensity: VisualDensity.compact),
                            onPressed: () => _start(day, i),
                            child: const Text('Start'),
                          ),
                    onTap: () => _start(day, i),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// Plays one session: shows each step with a countdown and moves on by itself.
class _SessionPlayer extends StatefulWidget {
  const _SessionPlayer({required this.session, required this.dayTitle});
  final WellnessSession session;
  final String dayTitle;

  @override
  State<_SessionPlayer> createState() => _SessionPlayerState();
}

class _SessionPlayerState extends State<_SessionPlayer> with SingleTickerProviderStateMixin {
  int _step = 0;
  int _left = 0;
  bool _paused = false;
  Timer? _timer;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _left = widget.session.steps.first.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_paused || !mounted) return;
    setState(() {
      if (_left > 1) {
        _left--;
      } else if (_step < widget.session.steps.length - 1) {
        _step++;
        _left = widget.session.steps[_step].seconds;
      } else {
        _left = 0;
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  bool get _finished => _left == 0 && _step == widget.session.steps.length - 1;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final step = s.steps[_step];
    final elapsed = s.steps.take(_step).fold(0, (a, x) => a + x.seconds) + (step.seconds - _left);
    return Scaffold(
      backgroundColor: const Color(0xFF2E2A5C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('${widget.dayTitle} · ${s.title}'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            LinearProgressIndicator(
              value: elapsed / s.seconds,
              backgroundColor: Colors.white12,
              color: const Color(0xFFB9AEFF),
              minHeight: 6,
              borderRadius: BorderRadius.circular(6),
            ),
            const Spacer(),
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final size = 150 + 40 * Curves.easeInOut.transform(_pulse.value);
                return Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [const Color(0xFFB9AEFF), AppColors.mind.withAlpha(60)]),
                  ),
                  alignment: Alignment.center,
                  child: Icon(_finished ? Icons.check : s.icon, color: Colors.white, size: 48),
                );
              },
            ),
            const SizedBox(height: 32),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _finished ? 'Session complete. Take a moment before you go on.' : step.text,
                key: ValueKey('$_step$_finished'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.45, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 14),
            if (!_finished)
              Text('${_left}s · step ${_step + 1} of ${s.steps.length}',
                  style: const TextStyle(color: Colors.white60)),
            const Spacer(),
            if (_finished)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2E2A5C),
                      padding: const EdgeInsets.symmetric(vertical: 15)),
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.check),
                  label: const Text('Mark as done'),
                ),
              )
            else
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.white24),
                  iconSize: 34,
                  onPressed: () => setState(() => _paused = !_paused),
                  icon: Icon(_paused ? Icons.play_arrow : Icons.pause, color: Colors.white),
                ),
                const SizedBox(width: 18),
                TextButton(
                  onPressed: () => setState(() {
                    if (_step < s.steps.length - 1) {
                      _step++;
                      _left = s.steps[_step].seconds;
                    } else {
                      _left = 0;
                    }
                  }),
                  child: const Text('Next step', style: TextStyle(color: Colors.white70)),
                ),
              ]),
          ]),
        ),
      ),
    );
  }
}
