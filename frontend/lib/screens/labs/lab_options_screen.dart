import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/lab_repository.dart';
import '../../widgets/state_views.dart';

/// After a symptom check: each suggested test in English, and labs in the user's city
/// with their published prices (cheapest first). Only sourced data, with source and date.
class LabOptionsScreen extends StatefulWidget {
  const LabOptionsScreen({super.key, required this.tests, this.repository, this.city});

  final List<String> tests;

  /// Show this city instead of the one saved in the profile.
  final String? city;
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
    if (widget.city != null) {
      setState(() {
        _loadingCity = false;
        _city = widget.city;
        _future = _repo.options(widget.city!, widget.tests);
      });
      return;
    }
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
        title: Text(widget.tests.length == 1 ? 'Labs & prices' : 'Tests & labs'),
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
          const SizedBox(height: 4),
          Text('More labs in ${o.city}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
          const SizedBox(height: 2),
          const Text('These labs have not published a price — call to ask.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE9EEF4))),
            child: Column(children: [
              for (var i = 0; i < o.otherLabs.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFEEF2F6)),
                _LabRow(offer: o.otherLabs[i], priceText: 'Ask price'),
              ],
            ]),
          ),
          const SizedBox(height: 10),
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
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
          SizedBox(width: 6),
          Expanded(
            child: Text('Prices come from each lab\'s own published list and can change. '
                'Please confirm with the lab before you go. Tap "Details" to see the source.',
                style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textMuted)),
          ),
        ]),
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
    final priced = test.offers.where((o) => o.price != null).toList();
    final cheapest = priced.isEmpty ? null : priced.first.price;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9EEF4)),
        boxShadow: const [BoxShadow(color: Color(0x0A16324F), blurRadius: 14, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: AppColors.diagnosisTint,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.biotech_outlined, color: AppColors.diagnosis, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(test.nameEn,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary)),
                const SizedBox(height: 2),
                Text(
                  cheapest == null
                      ? 'No published price in $city yet'
                      : '${priced.length} lab${priced.length == 1 ? '' : 's'} · from ${rs(cheapest)}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ]),
            ),
          ]),
        ),
        if (test.offers.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Text('Ask the labs listed below for this test\'s price.',
                style: TextStyle(color: AppColors.textMuted)),
          )
        else
          for (var i = 0; i < test.offers.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFEEF2F6)),
            _LabRow(
              offer: test.offers[i],
              priceText: test.offers[i].price == null ? 'Ask price' : rs(test.offers[i].price!),
              showTestName: true,
              best: i == 0 && priced.length > 1,
            ),
          ],
      ]),
    );
  }
}

/// One lab: name and price first, then area and phone; source and notes behind "Details".
class _LabRow extends StatelessWidget {
  const _LabRow({required this.offer, required this.priceText, this.showTestName = false, this.best = false});
  final LabOffer offer;
  final String priceText;
  final bool showTestName;
  final bool best;

  static String _cleanAddress(String a) => a
      .replaceAll(' (one of the branches)', '')
      .replaceAll(RegExp(r'\s*\((street )?address not (listed|stated) in source\)'), '')
      .trim();

  void _copyPhone(BuildContext context) {
    final first = offer.phone.split(',').first.trim();
    Clipboard.setData(ClipboardData(text: first));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Number copied: $first')));
  }

  void _details(BuildContext context) {
    final o = offer;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.lab, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (o.branch.isNotEmpty) Text(o.branch, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 12),
            if (o.publishedName.isNotEmpty) _kv('Lab calls this test', o.publishedName),
            if (o.address.isNotEmpty) _kv('Address', _cleanAddress(o.address)),
            if (o.phone.isNotEmpty) _kv('Phone', o.phone),
            if (o.notes.isNotEmpty) _kv('Note', o.notes),
            if (o.sourceUrl.isNotEmpty)
              _kv('Source', '${Uri.tryParse(o.sourceUrl)?.host ?? o.sourceUrl} · checked ${o.checked}'),
            const SizedBox(height: 6),
            const Text('Prices can change — please confirm with the lab before you go.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
      ),
    );
  }

  static Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          SelectableText(v, style: const TextStyle(fontSize: 14)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final gov = o.labType.toLowerCase().contains('govern') || o.labType.toLowerCase().contains('public');
    final area = _cleanAddress(o.address);
    final initials = o.lab.trim().isEmpty ? '?' : o.lab.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: gov ? const Color(0xFFE7F6EC) : AppColors.primaryTint,
            child: Text(initials,
                style: TextStyle(fontWeight: FontWeight.w800, color: gov ? AppColors.success : AppColors.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.lab, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (best) const _Tag('Lowest price', AppColors.success, Color(0xFFE7F6EC)),
                if (o.branches > 1) _Tag('${o.branches} branches', AppColors.primary, AppColors.primaryTint),
                if (gov) const _Tag('Government', AppColors.success, Color(0xFFE7F6EC)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          if (priceText.isNotEmpty)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(priceText,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: o.price == null ? 13 : 18,
                      color: o.price == null ? AppColors.textMuted : AppColors.success)),
              if (o.discountPrice != null)
                Text('Rs ${o.discountPrice!.toStringAsFixed(0)} online',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
        ]),
        if (area.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 52, top: 8),
            child: Row(children: [
              const Icon(Icons.place_outlined, size: 15, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(o.branches > 1 ? '$area  (+${o.branches - 1} more)' : area,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 44, top: 2),
          child: Row(children: [
            if (o.phone.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.call_outlined, size: 16),
                label: Text(o.phone.split(',').first.trim()),
                onPressed: () => _copyPhone(context),
              ),
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.textMuted),
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('Details'),
              onPressed: () => _details(context),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.fg, this.bg);
  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
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
