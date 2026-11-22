import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/drug_repository.dart';
import '../../services/lab_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/state_views.dart';
import '../labs/lab_options_screen.dart' show CityPickerScreen;

/// Feature 28: pharmacies in the user's city — real ones found online, the government hospital pharmacy
/// (free medicines for registered patients) and demo entries (labelled). Stock is not live: call to check.
class PharmacyFinderScreen extends StatefulWidget {
  const PharmacyFinderScreen({super.key});

  @override
  State<PharmacyFinderScreen> createState() => _PharmacyFinderScreenState();
}

class _PharmacyFinderScreenState extends State<PharmacyFinderScreen> {
  late final ApiClient _api = context.read<AuthProvider>().repository.api;
  late final DrugRepository _repo = DrugRepository(_api);
  late final LabRepository _labs = LabRepository(_api);
  final _search = TextEditingController();
  String? _city;
  bool _cityLoaded = false;
  String _filter = 'all'; // all / 24h / govt
  Future<List<Pharmacy>>? _future;

  @override
  void initState() {
    super.initState();
    _labs.myCity().then((c) {
      if (!mounted) return;
      setState(() {
        _city = c;
        _cityLoaded = true;
      });
      if (c == null) {
        _pickCity();
      } else {
        _reload();
      }
    }).catchError((_) {
      if (mounted) setState(() => _cityLoaded = true);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    if (_city == null) return;
    // All pharmacies of the city are loaded once; the filter chips work on this list instantly.
    setState(() => _future = _repo.pharmacies(_city!, q: _search.text));
  }

  Future<void> _pickCity() async {
    final c = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => CityPickerScreen(repository: _labs)));
    if (c == null || !mounted) return;
    setState(() {
      _city = c;
      _cityLoaded = true;
    });
    _labs.saveCity(c).catchError((_) {});
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pharmacies')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Material(
            color: AppColors.deep,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _pickCity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.location_on_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Your city', style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 12)),
                      Text(_city ?? 'Choose city',
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: const Text('Change',
                        style: TextStyle(color: AppColors.deep, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _reload(),
            decoration: InputDecoration(
              hintText: 'Search pharmacy name',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _reload),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Row(children: [
            for (final (k, label, icon) in const [
              ('all', 'All', Icons.apps_rounded),
              ('24h', 'Open 24 hours', Icons.schedule_rounded),
              ('govt', 'Govt hospital (free)', Icons.local_hospital_outlined),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(icon, size: 16, color: _filter == k ? Colors.white : AppColors.primary),
                  label: Text(label),
                  selected: _filter == k,
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: _filter == k ? AppColors.primary : AppColors.border),
                  labelStyle: TextStyle(
                      color: _filter == k ? Colors.white : AppColors.deep, fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _filter = k),
                ),
              ),
          ]),
        ),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (!_cityLoaded) return const LoadingView();
    if (_city == null) {
      return EmptyView(
          icon: Icons.location_city_outlined,
          title: 'Choose your city',
          message: 'See pharmacies in your city.',
          actionLabel: 'Choose city',
          onAction: _pickCity);
    }
    return FutureBuilder<List<Pharmacy>>(
      future: _future,
      builder: (context, snap) {
        if (_future == null || snap.connectionState != ConnectionState.done) return const LoadingView();
        if (snap.hasError) {
          final e = snap.error;
          return ErrorView(message: e is ApiException ? e.message : 'Could not load pharmacies.', onRetry: _reload);
        }
        final all = snap.data!;
        final list = switch (_filter) {
          'govt' => all.where((p) => p.kind == 'government').toList(),
          '24h' => all.where((p) => p.open24h).toList(),
          _ => all,
        };
        if (list.isEmpty) {
          return EmptyView(
              icon: Icons.local_pharmacy_outlined,
              title: 'No pharmacy found',
              message: _filter == 'all' ? 'Try another search or city.' : 'None with this filter in $_city.');
        }
        return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Text('${list.length} pharmac${list.length == 1 ? 'y' : 'ies'} in $_city',
                style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          for (final p in list) _PharmacyCard(pharmacy: p),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
                'Stock is not shown live — call the pharmacy to check your medicine.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ]);
      },
    );
  }
}

class _PharmacyCard extends StatelessWidget {
  const _PharmacyCard({required this.pharmacy});
  final Pharmacy pharmacy;

  @override
  Widget build(BuildContext context) {
    final p = pharmacy;
    final govt = p.kind == 'government';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: govt ? AppColors.recordsTint : AppColors.mint, borderRadius: BorderRadius.circular(12)),
            child: Icon(govt ? Icons.local_hospital_outlined : Icons.local_pharmacy_outlined,
                color: govt ? AppColors.records : AppColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: AppColors.deep)),
              const SizedBox(height: 2),
              Text(p.address, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (p.open24h) _tag('24 hours', AppColors.success, AppColors.mint),
                if (!p.open24h && p.hours.isNotEmpty) _tag(p.hours, AppColors.textMuted, AppColors.primaryTint),
                if (p.kind == 'chain') _tag('Pharmacy chain', AppColors.deep, AppColors.primaryTint),
                if (govt) _tag('Free for registered patients', AppColors.records, AppColors.recordsTint),
              ]),
            ]),
          ),
        ]),
        if (p.phone.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.call_outlined, size: 18),
              label: Text(p.phone),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: p.phone));
                showMessage(context, 'Number copied: ${p.phone}');
              },
            ),
          ),
      ]),
    );
  }

  static Widget _tag(String t, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: TextStyle(fontSize: 11.5, color: fg, fontWeight: FontWeight.w600)),
      );
}
