import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/lab_repository.dart';
import '../../widgets/state_views.dart';

/// After a symptom check: each suggested test in English, and labs in the user's city
/// with their published prices (cheapest first). Only sourced data, with source and date.
class LabOptionsScreen extends StatefulWidget {
  const LabOptionsScreen({super.key, required this.tests, this.repository});

  final List<String> tests;
  final LabRepository? repository;

  @override
  State<LabOptionsScreen> createState() => _LabOptionsScreenState();
}

class _LabOptionsScreenState extends State<LabOptionsScreen> {
  late final LabRepository _repo =
      widget.repository ?? LabRepository(context.read<AuthProvider>().repository.api);
  String? _city;
  Future<LabOptions>? _future;
  bool _loadingCity = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCity();
  }

  Future<void> _loadCity() async {
    try {
      final c = await _repo.myCity();
      if (!mounted) return;
      setState(() {
        _loadingCity = false;
        _city = c;
        if (c != null) _future = _repo.options(c, widget.tests);
      });
      if (c == null) await _pickCity();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loadingCity = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _pickCity() async {
    final chosen = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => CityPickerScreen(repository: _repo)));
    if (chosen == null || !mounted) return;
    setState(() {
      _city = chosen;
      _future = _repo.options(chosen, widget.tests);
    });
    try {
      await _repo.saveCity(chosen);
    } catch (_) {}
  }

  String _rs(double p) => p == 0 ? 'Free*' : 'Rs ${p.toStringAsFixed(p.truncateToDouble() == p ? 0 : 2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tests & labs'),
        actions: [
          if (_city != null)
            TextButton.icon(
              onPressed: _pickCity,
              icon: const Icon(Icons.location_on_outlined, size: 18),
              label: Text(_city!),
            ),
        ],
      ),
      body: _loadingCity
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: () {
                  setState(() {
                    _error = null;
                    _loadingCity = true;
                  });
                  _loadCity();
                })
              : _future == null
                  ? EmptyView(
                      icon: Icons.location_city_outlined,
                      title: 'Choose your city',
                      message: 'We show labs and prices for your city.',
                      actionLabel: 'Choose city',
                      onAction: _pickCity,
                    )
                  : FutureBuilder<LabOptions>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) return const LoadingView();
                        if (snap.hasError) {
                          final e = snap.error;
                          return ErrorView(
                            message: e is ApiException ? e.message : 'Could not load labs.',
                            onRetry: () => setState(() => _future = _repo.options(_city!, widget.tests)),
                          );
                        }
                        return _body(snap.data!);
                      },
                    ),
    );
  }

  Widget _body(LabOptions o) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final t in o.tests) _TestCard(test: t, city: o.city, rs: _rs),
        if (o.otherLabs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Other registered labs in ${o.city}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
          const Text('No published price found for these tests — call the lab to ask.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 6),
          for (final l in o.otherLabs) _LabRow(offer: l, priceText: 'Ask lab'),
          if (o.otherTotal > o.otherLabs.length)
            OutlinedButton.icon(
              icon: const Icon(Icons.list_alt_outlined),
              label: Text('See all ${o.otherTotal} labs in ${o.city}'),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => AllLabsScreen(repository: _repo, city: o.city))),
            ),
        ],
        if (o.tests.every((t) => t.offers.isEmpty) && o.otherLabs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'We have no verified labs for ${o.city} yet. You can find registered labs in the '
              'Punjab Healthcare Commission directory: ${o.directoryUrl}',
              style: const TextStyle(height: 1.4),
            ),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.warningTint, borderRadius: BorderRadius.circular(12)),
          child: Text('${o.note}\n* Free tests at government hospitals may apply only to some patients.',
              style: const TextStyle(fontSize: 12, height: 1.4)),
        ),
      ],
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({required this.test, required this.city, required this.rs});
  final TestLabs test;
  final String city;
  final String Function(double) rs;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9EEF4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            const Icon(Icons.biotech_outlined, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(test.nameEn,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
            ),
          ]),
        ),
        if (test.offers.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text('No published price for this test in $city yet. Ask the labs below.',
                style: const TextStyle(color: AppColors.textMuted)),
          )
        else
          for (final o in test.offers) _LabRow(offer: o, priceText: o.price == null ? 'Ask lab' : rs(o.price!), showTestName: true),
      ]),
    );
  }
}

class _LabRow extends StatelessWidget {
  const _LabRow({required this.offer, required this.priceText, this.showTestName = false});
  final LabOffer offer;
  final String priceText;
  final bool showTestName;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.branch.isEmpty ? o.lab : '${o.lab} — ${o.branch}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (showTestName && o.publishedName.isNotEmpty)
              Text('Listed as: ${o.publishedName}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            if (o.address.isNotEmpty) Text(o.address, style: const TextStyle(fontSize: 13)),
            if (o.phone.isNotEmpty) SelectableText('☎ ${o.phone}', style: const TextStyle(fontSize: 13)),
            if (o.notes.isNotEmpty && showTestName)
              Text(o.notes, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            if (o.sourceUrl.isNotEmpty)
              Text('Source: ${Uri.tryParse(o.sourceUrl)?.host ?? o.sourceUrl} · checked ${o.checked}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(priceText,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: o.price == null ? AppColors.textMuted : AppColors.success)),
          if (o.discountPrice != null)
            Text('Rs ${o.discountPrice!.toStringAsFixed(0)} online',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
      ]),
    );
  }
}

/// Searchable list of supported cities / tehsils (labs count shown).
class CityPickerScreen extends StatefulWidget {
  const CityPickerScreen({super.key, required this.repository});
  final LabRepository repository;

  @override
  State<CityPickerScreen> createState() => _CityPickerScreenState();
}

class _CityPickerScreenState extends State<CityPickerScreen> {
  late final Future<List<CityOption>> _future = widget.repository.cities();
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your city')),
      body: FutureBuilder<List<CityOption>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return const ErrorView(message: 'Could not load cities.');
          final list = snap.data!
              .where((c) => _q.isEmpty || '${c.city} ${c.district}'.toLowerCase().contains(_q.toLowerCase()))
              .toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search city or tehsil'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  return ListTile(
                    title: Text(c.city),
                    subtitle: Text(c.district),
                    trailing: Text(c.labs == 0 ? 'no labs yet' : '${c.labs} labs',
                        style: TextStyle(color: c.labs == 0 ? AppColors.textMuted : AppColors.accent, fontSize: 12)),
                    onTap: () => Navigator.of(context).pop(c.city),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}


/// Every registered lab in a city (PHC list and others), searchable by name or area.
class AllLabsScreen extends StatefulWidget {
  const AllLabsScreen({super.key, required this.repository, required this.city});
  final LabRepository repository;
  final String city;

  @override
  State<AllLabsScreen> createState() => _AllLabsScreenState();
}

class _AllLabsScreenState extends State<AllLabsScreen> {
  late final Future<LabOptions> _future = widget.repository.options(widget.city, const [], otherLimit: 2000);
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Labs in ${widget.city}')),
      body: FutureBuilder<LabOptions>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return const ErrorView(message: 'Could not load labs.');
          final q = _q.toLowerCase();
          final list = snap.data!.otherLabs
              .where((l) => q.isEmpty || '${l.lab} ${l.branch} ${l.address}'.toLowerCase().contains(q))
              .toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search lab name or area'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text('${list.length} labs · registered with the Punjab Healthcare Commission and other sources. '
                  'Prices are not published by most labs — please call or visit to ask.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F6)),
                itemBuilder: (_, i) => _LabRow(offer: list[i], priceText: ''),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
