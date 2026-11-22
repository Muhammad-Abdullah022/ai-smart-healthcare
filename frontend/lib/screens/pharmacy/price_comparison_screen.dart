import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/drug_repository.dart';
import '../../services/lab_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/state_views.dart';
import '../labs/lab_options_screen.dart' show CityPickerScreen;
import 'pharmacy_finder_screen.dart';

/// Feature 29: type a medicine, its strength (mg) and your city -> every brand of the same medicine with
/// DRAP's official price (cheapest first) and the pharmacies in that city.
class PriceComparisonScreen extends StatefulWidget {
  const PriceComparisonScreen({super.key, this.initialName});
  final String? initialName;

  @override
  State<PriceComparisonScreen> createState() => _PriceComparisonScreenState();
}

class _PriceComparisonScreenState extends State<PriceComparisonScreen> {
  late final ApiClient _api = context.read<AuthProvider>().repository.api;
  late final DrugRepository _repo = DrugRepository(_api);
  late final LabRepository _labs = LabRepository(_api);
  late final _name = TextEditingController(text: widget.initialName ?? '');
  final _mg = TextEditingController();
  String? _city;
  Future<PriceComparison>? _future;

  @override
  void initState() {
    super.initState();
    _labs.myCity().then((c) {
      if (mounted && c != null) setState(() => _city = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _mg.dispose();
    super.dispose();
  }

  Future<void> _pickCity() async {
    final c = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => CityPickerScreen(repository: _labs)));
    if (c == null || !mounted) return;
    setState(() => _city = c);
    _labs.saveCity(c).catchError((_) {});
    if (_future != null) _search();
  }

  void _search() {
    FocusScope.of(context).unfocus();
    if (_name.text.trim().length < 2) {
      showMessage(context, 'Type the medicine name, e.g. Panadol.', error: true);
      return;
    }
    setState(() => _future = _repo.prices(_name.text, strength: _mg.text, city: _city ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medicine prices')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
        _form(),
        const SizedBox(height: 16),
        if (_future == null) _hint() else _results(),
      ]),
    );
  }

  Widget _form() => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.softShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Header strip
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.deep, AppColors.primaryDeep]),
            ),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.sell_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Compare prices',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('Same medicine, every brand, cheapest first',
                      style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _label('Medicine name'),
              _field(_name, 'e.g. Panadol or Paracetamol', Icons.medication_outlined),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 4,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _label('Strength (mg)'),
                    _field(_mg, 'e.g. 500', Icons.straighten_rounded,
                        keyboard: const TextInputType.numberWithOptions(decimal: true)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _label('City'),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickCity,
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          const Icon(Icons.location_on_outlined, color: AppColors.accent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_city ?? 'Choose',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _city == null ? AppColors.textMuted : AppColors.deep)),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                ),
                onPressed: _search,
                icon: const Icon(Icons.search_rounded),
                label: const Text('Show prices'),
              ),
            ]),
          ),
        ]),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
      );

  Widget _field(TextEditingController c, String hint, IconData icon, {TextInputType? keyboard}) => TextField(
        controller: c,
        keyboardType: keyboard,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.deep),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.background,
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          prefixIcon: Icon(icon, color: AppColors.accent, size: 20),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.accent, width: 1.6)),
        ),
      );

  Widget _hint() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Try', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (n, mg) in const [
            ('Panadol', '500'),
            ('Risek', '20'),
            ('Augmentin', '625'),
            ('Norvasc', '5'),
            ('Flagyl', '400'),
            ('Brufen', '400'),
          ])
            ActionChip(
              avatar: const Icon(Icons.medication_rounded, size: 16, color: AppColors.primary),
              label: Text('$n $mg mg'),
              onPressed: () {
                _name.text = n;
                _mg.text = mg;
                _search();
              },
            ),
        ]),
        const SizedBox(height: 16),
        const Text(
            'Prices come from DRAP, the government medicine authority. The official price is the same in every '
            'city; the city shows you where to buy.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4)),
      ]);

  Widget _results() => FutureBuilder<PriceComparison>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.only(top: 40), child: LoadingView());
          }
          if (snap.hasError) {
            final e = snap.error;
            return ErrorView(message: e is ApiException ? e.message : 'Could not load prices.', onRetry: _search);
          }
          final r = snap.data!;
          final priced = r.items.where((i) => i.mrp != null).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!r.loaded)
              _notice('The official price list is still loading on the server (it needs internet once). '
                  'Restart the backend with internet on and try again.'),
            if (r.generic.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Medicine (salt): ', style: TextStyle(color: AppColors.textMuted)),
                  TextSpan(text: r.generic, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.deep)),
                ])),
              ),
            if (r.cheapest != null) _cheapestCard(r.cheapest!),
            if (r.items.isEmpty && r.loaded)
              _notice('No official price found for "${_name.text.trim()}". Check the spelling or try the salt '
                  'name (e.g. Paracetamol).'),
            if (r.items.isNotEmpty) ...[
              _section('All brands (${r.items.length})', Icons.format_list_bulleted_rounded),
              for (final i in r.items) _PriceCard(item: i, cheapest: _same(i, r.cheapest)),
            ],
            if (r.otherBrands.isNotEmpty) ...[
              _section('Same medicine, price not in the official list', Icons.help_outline_rounded),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final b in r.otherBrands)
                  Chip(
                    label: Text('${b.brand}${b.strengths.isEmpty ? '' : ' · ${b.strengths.take(2).join(', ')}'}'),
                    backgroundColor: Colors.white,
                  ),
              ]),
              const SizedBox(height: 4),
              const Text('Ask the pharmacy for these prices.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
            if (_city != null) ...[
              _section('Where to buy in $_city', Icons.local_pharmacy_outlined),
              if (r.pharmacies.isEmpty)
                const Text('No pharmacy listed for this city yet.', style: TextStyle(color: AppColors.textMuted))
              else
                for (final p in r.pharmacies.take(6)) _pharmacyTile(p),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PharmacyFinderScreen())),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('All pharmacies'),
                ),
              ),
            ] else
              _notice('Choose your city above to see pharmacies near you.'),
            const SizedBox(height: 10),
            if (priced.isNotEmpty || r.items.isNotEmpty)
              Text(r.note, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
            if (r.sourceUrl.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => launchUrl(Uri.parse(r.sourceUrl), mode: LaunchMode.externalApplication),
                  child: Text('Source: ${r.sourceName}', style: const TextStyle(fontSize: 12)),
                ),
              ),
          ]);
        },
      );

  bool _same(PriceItem a, PriceItem? b) => b != null && a.brand == b.brand && a.pack == b.pack && a.mrp == b.mrp;

  Widget _cheapestCard(PriceItem c) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.mint,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.green.withAlpha(70)),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.savings_outlined, color: AppColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Cheapest option', style: TextStyle(fontSize: 12, color: AppColors.green, fontWeight: FontWeight.w700)),
              Text(c.brand, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.deep)),
              Text(
                  '${_rs(c.mrp)} for ${c.pack}'
                  '${c.perUnit != null ? '  ·  ${_rs(c.perUnit)} per ${_unitWord(c.form)}' : ''}',
                  style: const TextStyle(fontSize: 13, color: AppColors.text)),
            ]),
          ),
        ]),
      );

  Widget _section(String t, IconData icon) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppColors.deep))),
        ]),
      );

  Widget _notice(String t) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(14)),
        child: Text(t, style: const TextStyle(fontSize: 13, color: Color(0xFF7C4A03), height: 1.4)),
      );

  Widget _pharmacyTile(Pharmacy p) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Icon(p.kind == 'government' ? Icons.local_hospital_outlined : Icons.local_pharmacy_outlined,
              color: p.kind == 'government' ? AppColors.records : AppColors.green, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep)),
              Text(
                  [p.address, if (p.open24h) 'Open 24 hours', if (p.kind == 'government') 'Free for registered patients']
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
          if (p.phone.isNotEmpty)
            IconButton(
              tooltip: 'Copy number',
              icon: const Icon(Icons.call_outlined, color: AppColors.primary),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: p.phone));
                showMessage(context, 'Number copied: ${p.phone}');
              },
            ),
        ]),
      );
}

String _unitWord(String form) => switch (form) {
      'capsule' => 'capsule',
      'sachet' => 'sachet',
      'injection' => 'injection',
      'tablet' => 'tablet',
      _ => 'unit',
    };

String _rs(double? v) {
  if (v == null) return 'Price not listed';
  final whole = v == v.roundToDouble();
  final s = v.toStringAsFixed(whole ? 0 : 2);
  final parts = s.split('.');
  final head = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return 'Rs $head${parts.length > 1 ? '.${parts[1]}' : ''}';
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.item, required this.cheapest});
  final PriceItem item;
  final bool cheapest;

  @override
  Widget build(BuildContext context) {
    final i = item;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cheapest ? AppColors.green : AppColors.border, width: cheapest ? 1.5 : 1),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(i.brand, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.deep)),
            if (i.formulation.isNotEmpty)
              Text(i.formulation,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
            Text('${i.company}${i.pack.isEmpty ? '' : ' · Pack: ${i.pack}'}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (cheapest) _tag('Cheapest', AppColors.green, AppColors.mint),
              if (i.sameStrength) _tag('Same strength', AppColors.primary, AppColors.primaryTint),
              if (i.combo) _tag('Mixed with other medicine', const Color(0xFF7C4A03), const Color(0xFFFFF4E5)),
            ]),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_rs(i.mrp),
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: i.mrp == null ? 12 : 16,
                  color: i.mrp == null ? AppColors.textMuted : AppColors.deep)),
          if (i.perUnit != null)
            Text('${_rs(i.perUnit)} each', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ]),
      ]),
    );
  }

  static Widget _tag(String t, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w700)),
      );
}
