import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/lab_repository.dart';
import '../../widgets/state_views.dart';
import 'lab_options_screen.dart';

/// Feature 6 — Nearby Laboratory Finder: the user's city, then every lab there with address and phone.
/// (Test prices are compared in feature 7, Lab Test Price Comparison.)
class LabFinderScreen extends StatefulWidget {
  const LabFinderScreen({super.key, this.repository});
  final LabRepository? repository;

  @override
  State<LabFinderScreen> createState() => _LabFinderScreenState();
}

class _LabFinderScreenState extends State<LabFinderScreen> {
  late final LabRepository _repo =
      widget.repository ?? LabRepository(context.read<AuthProvider>().repository.api);
  String? _city;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo.myCity().then((c) {
      if (!mounted) return;
      setState(() {
        _city = c;
        _loading = false;
      });
      if (c == null) _chooseCity();
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _chooseCity() async {
    final c = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => CityPickerScreen(repository: _repo)));
    if (c == null || !mounted) return;
    setState(() => _city = c);
    _repo.saveCity(c).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_city != null) {
      return AllLabsScreen(key: ValueKey(_city), repository: _repo, city: _city!, onChangeCity: _chooseCity);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby labs')),
      body: _loading
          ? const LoadingView()
          : EmptyView(
              icon: Icons.location_city_outlined,
              title: 'Choose your city',
              message: 'See every registered lab in your city with address and phone.',
              actionLabel: 'Choose city',
              onAction: _chooseCity,
            ),
    );
  }
}

/// "Find a test & prices": choose the city and the test, then see every lab's price for it.
/// Used by Lab Test Price Comparison (feature 7) and by "Find a test" in the lab finder.
class TestPickerScreen extends StatefulWidget {
  const TestPickerScreen({super.key, this.repository, this.city});
  final LabRepository? repository;
  final String? city;

  @override
  State<TestPickerScreen> createState() => _TestPickerScreenState();
}

class _TestPickerScreenState extends State<TestPickerScreen> {
  late final LabRepository _repo =
      widget.repository ?? LabRepository(context.read<AuthProvider>().repository.api);
  String? _cityValue;
  Future<List<({String key, String name, int labsWithPrice})>>? _tests;
  String _q = '';

  String get _city => _cityValue ?? '';

  @override
  void initState() {
    super.initState();
    if (widget.city != null) {
      _setCity(widget.city!);
    } else {
      _repo.myCity().then((c) {
        if (!mounted) return;
        if (c == null) {
          _chooseCity();
        } else {
          _setCity(c);
        }
      }).catchError((_) => _chooseCity());
    }
  }

  void _setCity(String c) => setState(() {
        _cityValue = c;
        _tests = _repo.tests(c);
      });

  Future<void> _chooseCity() async {
    final c = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => CityPickerScreen(repository: _repo)));
    if (c == null || !mounted) return;
    _repo.saveCity(c).catchError((_) {});
    _setCity(c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare test prices'),
        actions: [
          TextButton.icon(
            onPressed: _chooseCity,
            icon: const Icon(Icons.location_on_outlined, size: 18),
            label: Text(_cityValue ?? 'Choose city'),
          ),
        ],
      ),
      body: _tests == null
          ? EmptyView(
              icon: Icons.location_city_outlined,
              title: 'Choose your city',
              message: 'Then pick a test to see every lab\'s price.',
              actionLabel: 'Choose city',
              onAction: _chooseCity,
            )
          : _testList(),
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
              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEDF1F4)),
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
