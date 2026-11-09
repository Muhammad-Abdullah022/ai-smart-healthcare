import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/lab_repository.dart';
import '../../widgets/state_views.dart';
import 'lab_options_screen.dart';

enum _Mode { labs, test }

/// Features 6 and 7: first ask what the user wants —
///   "Find labs"            -> city -> all labs in that city
///   "Find a test & prices" -> city -> test -> labs with that test's price (cheapest first)
class LabFinderScreen extends StatefulWidget {
  const LabFinderScreen({super.key, this.repository});
  final LabRepository? repository;

  @override
  State<LabFinderScreen> createState() => _LabFinderScreenState();
}

class _LabFinderScreenState extends State<LabFinderScreen> {
  late final LabRepository _repo =
      widget.repository ?? LabRepository(context.read<AuthProvider>().repository.api);
  _Mode? _mode;
  String? _city;

  @override
  void initState() {
    super.initState();
    _repo.myCity().then((c) {
      if (mounted && c != null) setState(() => _city = c);
    }).catchError((_) {});
  }

  Future<void> _chooseCity({bool andContinue = false}) async {
    final c = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => CityPickerScreen(repository: _repo)));
    if (c == null || !mounted) return;
    setState(() => _city = c);
    _repo.saveCity(c).catchError((_) {});
    if (andContinue) _next();
  }

  /// Move on once mode and city are known.
  void _next() {
    if (_mode == null) return;
    if (_city == null) {
      _chooseCity(andContinue: true);
      return;
    }
    final page = _mode == _Mode.labs
        ? AllLabsScreen(repository: _repo, city: _city!)
        : TestPickerScreen(repository: _repo, city: _city!) as Widget;
    // Back from the next page returns to the choice.
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)).then((_) {
      if (mounted) setState(() => _mode = null);
    });
  }

  void _pickMode(_Mode m) {
    setState(() => _mode = m);
    _next();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Labs & tests'),
        actions: [
          TextButton.icon(
            onPressed: () => _chooseCity(),
            icon: const Icon(Icons.location_on_outlined, size: 18),
            label: Text(_city ?? 'Choose city'),
          ),
        ],
      ),
      body: _choice(),
    );
  }

  Widget _choice() {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      const Text('What would you like to find?',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary)),
      const SizedBox(height: 4),
      Text(_city == null ? 'You will choose your city next.' : 'City: $_city — tap the city above to change it.',
          style: const TextStyle(color: AppColors.textMuted)),
      const SizedBox(height: 18),
      _OptionCard(
        icon: Icons.location_on_outlined,
        title: 'Find labs',
        subtitle: 'All registered labs in your city, with address and phone. Search by name or area.',
        onTap: () => _pickMode(_Mode.labs),
      ),
      const SizedBox(height: 12),
      _OptionCard(
        icon: Icons.price_check,
        title: 'Find a test & compare prices',
        subtitle: 'Choose a test (e.g. CBC, HbA1c) and see labs in your city with its price, cheapest first.',
        onTap: () => _pickMode(_Mode.test),
      ),
    ]);
  }
}

/// "Find a test" step: search the standard tests; each shows how many labs in the city have a price.
class TestPickerScreen extends StatefulWidget {
  const TestPickerScreen({super.key, required this.repository, required this.city});
  final LabRepository repository;
  final String city;

  @override
  State<TestPickerScreen> createState() => _TestPickerScreenState();
}

class _TestPickerScreenState extends State<TestPickerScreen> {
  late Future<List<({String key, String name, int labsWithPrice})>> _tests = widget.repository.tests(widget.city);
  String _q = '';

  LabRepository get _repo => widget.repository;
  String get _city => widget.city;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Choose a test · $_city')),
      body: _testList(),
    );
  }

  Widget _testList() {
    return FutureBuilder<List<({String key, String name, int labsWithPrice})>>(
      future: _tests,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingView();
        if (snap.hasError) {
          final e = snap.error;
          return ErrorView(
            message: e is ApiException ? e.message : 'Could not load tests.',
            onRetry: () => setState(() => _tests = _repo.tests(_city)),
          );
        }
        final q = _q.toLowerCase();
        final list = snap.data!.where((t) => q.isEmpty || t.name.toLowerCase().contains(q)).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Search a test, e.g. CBC, sugar, thyroid'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F6)),
              itemBuilder: (_, i) {
                final t = list[i];
                return ListTile(
                  leading: const Icon(Icons.biotech_outlined, color: AppColors.accent),
                  title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    t.labsWithPrice == 0
                        ? 'No published price in $_city yet'
                        : '${t.labsWithPrice} lab${t.labsWithPrice == 1 ? '' : 's'} with a price in $_city',
                    style: TextStyle(color: t.labsWithPrice == 0 ? AppColors.textMuted : AppColors.success),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LabOptionsScreen(tests: [t.name], city: _city, repository: _repo))),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE9EEF4))),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: AppColors.diagnosisTint, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: AppColors.diagnosis, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: AppColors.textMuted, height: 1.35)),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
