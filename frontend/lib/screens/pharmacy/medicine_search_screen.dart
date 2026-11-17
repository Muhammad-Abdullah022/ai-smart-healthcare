import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/drug_repository.dart';
import '../../widgets/state_views.dart';
import 'pharmacy_finder_screen.dart';

/// Feature 30 (+37): search any medicine by brand or salt; open it to see what it is for,
/// side effects, warnings and every other brand with the SAME salt (e.g. Naprox -> Naprosyn, Neoprox).
class MedicineSearchScreen extends StatefulWidget {
  const MedicineSearchScreen({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  State<MedicineSearchScreen> createState() => _MedicineSearchScreenState();
}

class _MedicineSearchScreenState extends State<MedicineSearchScreen> {
  late final DrugRepository _repo = DrugRepository(context.read<AuthProvider>().repository.api);
  late final _ctrl = TextEditingController(text: widget.initialQuery ?? '');
  Timer? _debounce;
  List<DrugBrand> _results = [];
  bool _loading = false;
  String? _error;
  ({int brands, int generics})? _stats;

  static const _popular = ['Panadol', 'Brufen', 'Augmentin', 'Risek', 'Naprox', 'Glucophage', 'Norvasc', 'Zyrtec'];

  @override
  void initState() {
    super.initState();
    _repo.stats().then((s) {
      if (mounted) setState(() => _stats = s);
    }).catchError((_) {});
    if (_ctrl.text.isNotEmpty) _run(_ctrl.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(v));
  }

  Future<void> _run(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await _repo.search(q);
      if (mounted && q == _ctrl.text) {
        setState(() {
          _results = r;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(String name) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => MedicineDetailScreen(repository: _repo, name: name)));

  @override
  Widget build(BuildContext context) {
    final q = _ctrl.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Medicine search')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _ctrl,
            autofocus: widget.initialQuery == null,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (v) => v.trim().length >= 2 ? _open(v.trim()) : null,
            decoration: InputDecoration(
              hintText: 'Medicine or salt name, e.g. Naprox or Naproxen',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _ctrl.clear();
                        _run('');
                      }),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: q.isEmpty ? _intro() : _list(q)),
      ]),
    );
  }

  Widget _intro() => ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            const Icon(Icons.swap_horiz_rounded, color: AppColors.green, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Find what a medicine is for and other brands with the same salt.'
                '${_stats == null ? '' : '\n${_stats!.brands} brands · ${_stats!.generics} salts in the app'}',
                style: const TextStyle(height: 1.4, color: AppColors.deep),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        const Text('Popular', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.deep)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in _popular) ActionChip(label: Text(p), onPressed: () => _open(p)),
        ]),
      ]);

  Widget _list(String q) {
    if (_error != null) return ErrorView(message: _error!, onRetry: () => _run(q));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      for (final b in _results) _BrandTile(brand: b, onTap: () => _open(b.brand)),
      if (!_loading)
        Card(
          elevation: 0,
          color: AppColors.primaryTint,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: const Icon(Icons.auto_awesome_outlined, color: AppColors.deep),
            title: Text(_results.isEmpty ? 'Not in the list? Look up "$q"' : 'Look up "$q" anyway'),
            subtitle: const Text('The AI will try to find its salt'),
            onTap: q.length >= 2 ? () => _open(q) : null,
          ),
        ),
    ]);
  }
}

class _BrandTile extends StatelessWidget {
  const _BrandTile({required this.brand, required this.onTap});
  final DrugBrand brand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
        child: ListTile(
          onTap: onTap,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: AppColors.medicineTint, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.medication_outlined, color: AppColors.medicine),
          ),
          title: Text(brand.brand, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            [brand.generic, if (brand.strengths.isNotEmpty) brand.strengths.take(3).join(', ')].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}

/// One medicine: what it is, uses, side effects, warnings and same-salt alternatives.
class MedicineDetailScreen extends StatefulWidget {
  const MedicineDetailScreen({super.key, required this.repository, required this.name});
  final DrugRepository repository;
  final String name;

  @override
  State<MedicineDetailScreen> createState() => _MedicineDetailScreenState();
}

class _MedicineDetailScreenState extends State<MedicineDetailScreen> {
  late Future<DrugDetail> _future = widget.repository.detail(widget.name);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: FutureBuilder<DrugDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) {
            final e = snap.error;
            return ErrorView(
                message: e is ApiException ? e.message : 'Could not load this medicine.',
                onRetry: () => setState(() => _future = widget.repository.detail(widget.name)));
          }
          final d = snap.data!;
          final m = d.medicine;
          final g = d.generic;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(colors: [AppColors.deep, AppColors.green]),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m?.brand ?? widget.name,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Salt: ${g?.generic ?? m?.generic ?? '—'}',
                    style: TextStyle(color: Colors.white.withAlpha(230), fontSize: 15, fontWeight: FontWeight.w600)),
                if (m != null && m.company.isNotEmpty)
                  Text(m.company, style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in [...?m?.strengths, ...?m?.forms])
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration:
                          BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(8)),
                      child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                ]),
              ]),
            ),
            if (d.aiGuess)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.warningTint, borderRadius: BorderRadius.circular(14)),
                child: const Text(
                    'This brand is not in the app\'s list. The salt above is the AI\'s best guess — please confirm with '
                    'your pharmacist.',
                    style: TextStyle(color: Color(0xFF92400E))),
              ),
            if (g != null) ...[
              const SizedBox(height: 14),
              _info(Icons.category_outlined, 'Type', g.drugClass),
              _info(Icons.healing_outlined, 'Used for', g.uses),
              _info(Icons.sick_outlined, 'Common side effects', g.sideEffects),
              _info(Icons.warning_amber_rounded, 'Important', g.warnings, warn: true),
            ],
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.swap_horiz_rounded, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Same salt, other brands (${d.alternatives.length})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.deep)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(d.note, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            const SizedBox(height: 8),
            if (d.alternatives.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No other brand with exactly the same salt in the app\'s list.',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            for (final a in d.alternatives)
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 8),
                color: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
                child: ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: AppColors.mint, child: Icon(Icons.medication, color: AppColors.green)),
                  title: Text(a.brand, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    if (a.company.isNotEmpty) a.company,
                    if (a.strengths.isNotEmpty) a.strengths.take(4).join(', '),
                    if (a.forms.isNotEmpty) a.forms.join(', '),
                  ].join(' · ')),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MedicineDetailScreen(repository: widget.repository, name: a.brand))),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.local_pharmacy_outlined),
              label: const Text('Find a pharmacy near me'),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const PharmacyFinderScreen())),
            ),
          ]);
        },
      ),
    );
  }

  Widget _info(IconData icon, String label, String text, {bool warn = false}) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn ? AppColors.warningTint : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: warn ? const Color(0xFFF2C46D) : AppColors.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: warn ? const Color(0xFFB45309) : AppColors.green),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 2),
            Text(text, style: const TextStyle(height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}
