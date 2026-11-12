import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/doctor_repository.dart';
import '../../services/lab_repository.dart';
import '../../widgets/state_views.dart';
import '../labs/lab_options_screen.dart' show CityPickerScreen;

const _lime = Color(0xFFD9F35B);

String _slug(String text) => text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

/// Search pages on Marham and oladoc for a city and specialty. The app only links to them
/// (nothing is copied), so the user always sees their current doctors, fees and booking.
List<({String site, Uri url})> externalDoctorSearch(String? city, String? specialty) {
  final c = city == null ? 'lahore' : _slug(city);
  final sp = specialty == null ? 'general-physician' : _slug(specialty);
  return [
    (site: 'Marham', url: Uri.parse('https://www.marham.pk/doctors/$c/$sp')),
    (site: 'oladoc', url: Uri.parse('https://oladoc.com/pakistan/$c/$sp')),
  ];
}

Future<void> openExternal(BuildContext context, Uri url) async {
  try {
    if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open $url')));
  }
}

/// "More doctors" card: opens the same city + specialty on Marham or oladoc.
class ExternalDoctorsCard extends StatelessWidget {
  const ExternalDoctorsCard({super.key, required this.city, required this.specialty, this.district});
  final String? city;
  final String? specialty;

  /// The city's district. Doctor websites list doctors by district city, not by small tehsil,
  /// so e.g. Pir Mahal opens Toba Tek Singh.
  final String? district;

  @override
  Widget build(BuildContext context) {
    final linkCity = district ?? city;
    final nearby = district != null && city != null && district!.toLowerCase() != city!.toLowerCase();
    final what = '${specialty ?? 'doctors'}${linkCity == null ? '' : ' in $linkCity'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFF7FBE6), borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _lime)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('See all $what', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 4),
        Text(
            nearby
                ? 'Nearest listings for $city are in $district district: current doctors, fees and online booking.'
                : 'Current doctors, fees and online booking on these Pakistani doctor websites.',
            style: const TextStyle(color: AppColors.textMuted, height: 1.35)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 8, children: [
          for (final l in externalDoctorSearch(linkCity, specialty))
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _ink, shape: const StadiumBorder()),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text('Open ${l.site}'),
              onPressed: () => openExternal(context, l.url),
            ),
        ]),
      ]),
    );
  }
}
const _ink = Color(0xFF111827);

/// Feature 10 entry: a friendly intro card, then the doctor directory.
class DoctorsIntroScreen extends StatelessWidget {
  const DoctorsIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                Expanded(
                  flex: 6,
                  child: Container(
                    color: const Color(0xFFF7F8FA),
                    child: Stack(alignment: Alignment.center, children: [
                      Positioned(
                        right: -30,
                        top: -30,
                        child: Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, border: Border.all(color: _lime, width: 10)),
                        ),
                      ),
                      Positioned(
                        left: -40,
                        bottom: 30,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: const BoxDecoration(color: _lime, shape: BoxShape.circle),
                        ),
                      ),
                      Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppColors.accent.withAlpha(70), blurRadius: 30)],
                        ),
                        child: const Icon(Icons.medical_services_rounded, size: 80, color: Colors.white),
                      ),
                    ]),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                    child: Column(children: [
                      const Text('Find the right doctor',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _ink)),
                      const SizedBox(height: 10),
                      const Text(
                        'Specialists across Punjab with clinic address and check-up fee. '
                        'Send an appointment request in one tap.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, height: 1.45),
                      ),
                      const SizedBox(height: 14),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                            width: 22,
                            height: 6,
                            decoration: BoxDecoration(color: _lime, borderRadius: BorderRadius.circular(3))),
                        const SizedBox(width: 5),
                        for (var i = 0; i < 2; i++) ...[
                          Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(color: Color(0xFFD1D5DB), shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                        ],
                      ]),
                      const Spacer(),
                      SizedBox(
                        width: 200,
                        height: 50,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: _ink, shape: const StadiumBorder(), foregroundColor: Colors.white),
                          onPressed: () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const DoctorListScreen())),
                          child: const Text('Get Started', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The doctor directory: city, specialty chips, search, doctor cards.
/// With [specialty] and [reason] (from the chat), tapping a doctor opens the booking sheet directly.
class DoctorListScreen extends StatefulWidget {
  const DoctorListScreen({super.key, this.specialty, this.reason, this.fromChat = false});

  final String? specialty;
  final String? reason;
  final bool fromChat;

  @override
  State<DoctorListScreen> createState() => _DoctorListScreenState();
}

class _DoctorListScreenState extends State<DoctorListScreen> {
  late final ApiClient _api = context.read<AuthProvider>().repository.api;
  late final DoctorRepository _repo = DoctorRepository(_api);
  late final LabRepository _labs = LabRepository(_api);
  String? _city;
  String? _specialty;
  String _q = '';
  Future<List<Doctor>>? _future;
  Future<List<({String name, int doctors})>>? _specs;
  Map<String, String> _districtOf = {};

  @override
  void initState() {
    super.initState();
    _specialty = widget.specialty;
    _labs.cities().then((list) {
      if (mounted) setState(() => _districtOf = {for (final c in list) c.city.toLowerCase(): c.district});
    }).catchError((_) {});
    _labs.myCity().then((c) {
      if (!mounted) return;
      setState(() => _city = c);
      _reload();
    }).catchError((_) => _reload());
  }

  void _reload() => setState(() {
        _future = _repo.doctors(city: _city, specialty: _specialty, search: _q);
        _specs = _repo.specialties(city: _city);
      });

  Future<void> _pickCity() async {
    final c = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => CityPickerScreen(repository: _labs)));
    if (c == null || !mounted) return;
    _city = c;
    _labs.saveCity(c).catchError((_) {});
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fromChat ? 'Choose a doctor' : 'Doctors'),
        actions: [
          TextButton.icon(
            onPressed: _pickCity,
            icon: const Icon(Icons.location_on_outlined, size: 18),
            label: Text(_city ?? 'All Punjab'),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search doctor, clinic or area'),
            onSubmitted: (v) {
              _q = v;
              _reload();
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: FutureBuilder<List<({String name, int doctors})>>(
            future: _specs,
            builder: (context, snap) {
              final specs = snap.data ?? const [];
              return ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                _chip('All', _specialty == null, () {
                  _specialty = null;
                  _reload();
                }),
                for (final s in specs)
                  _chip(s.doctors > 0 ? '${s.name} · ${s.doctors}' : s.name, _specialty == s.name, () {
                    _specialty = s.name;
                    _reload();
                  }),
              ]);
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Doctor>>(
            future: _future,
            builder: (context, snap) {
              if (_future == null || snap.connectionState != ConnectionState.done) return const LoadingView();
              if (snap.hasError) {
                final e = snap.error;
                return ErrorView(message: e is ApiException ? e.message : 'Could not load doctors.', onRetry: _reload);
              }
              final list = snap.data!;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  for (final d in list)
                    DoctorCard(
                      doctor: d,
                      onBook: () => showDoctorBookingSheet(context,
                          repository: _repo, doctor: d, reason: widget.reason, fromChat: widget.fromChat),
                    ),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 8, 4, 14),
                      child: Text('No doctors in the app\'s own list here yet — see all doctors below.',
                          style: TextStyle(color: AppColors.textMuted)),
                    ),
                  ExternalDoctorsCard(
                      city: _city, specialty: _specialty, district: _districtOf[_city?.toLowerCase()]),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: _lime,
          labelStyle: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: _ink),
          shape: const StadiumBorder(),
        ),
      );
}

class DoctorCard extends StatelessWidget {
  const DoctorCard({super.key, required this.doctor, required this.onBook});
  final Doctor doctor;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final d = doctor;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x0F111827), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _lime, width: 3),
            ),
            alignment: Alignment.center,
            child: Text(d.initials,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.accent)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 2),
              Text([d.specialty, if (d.qualification.isNotEmpty) d.qualification].join(' · '),
                  style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (d.fee != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Rs ${d.fee!.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
              const Text('check-up fee', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
        ]),
        const SizedBox(height: 12),
        if (d.clinic.isNotEmpty) _line(Icons.local_hospital_outlined, d.clinic),
        if (d.address.isNotEmpty) _line(Icons.place_outlined, d.address),
        if (d.timings.isNotEmpty) _line(Icons.schedule, d.timings),
        const SizedBox(height: 10),
        Row(children: [
          if (d.phone.isNotEmpty)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
              icon: const Icon(Icons.call_outlined, size: 18),
              label: const Text('Copy number'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: d.phone));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Number copied: ${d.phone}')));
              },
            ),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _ink, shape: const StadiumBorder()),
            icon: const Icon(Icons.event_available_outlined, size: 18),
            label: const Text('Book'),
            onPressed: onBook,
          ),
        ]),
        if (d.sourceUrl.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Source: ${Uri.tryParse(d.sourceUrl)?.host ?? d.sourceUrl}'
                '${d.checked.isNotEmpty ? ' · checked ${d.checked}' : ''}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ),
      ]),
    );
  }

  static Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.text))),
        ]),
      );
}

/// Confirm and send an appointment request. If the doctor has an email, it is sent to them.
Future<void> showDoctorBookingSheet(BuildContext context,
    {required DoctorRepository repository, required Doctor doctor, String? reason, bool fromChat = false}) async {
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  var date = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
  var time = 'any';
  final reasonCtrl = TextEditingController(text: reason ?? '');
  final phoneCtrl = TextEditingController();
  var sending = false;
  String nice(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  final result = await showModalBottomSheet<BookingResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Book ${doctor.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text([doctor.specialty, if (doctor.clinic.isNotEmpty) doctor.clinic, doctor.city].join(' · '),
                style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text('Date: ${nice(date)}'),
              onPressed: () async {
                final d = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 60)));
                if (d != null) setSheet(() => date = d);
              },
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'morning', label: Text('Morning')),
                ButtonSegment(value: 'evening', label: Text('Evening')),
                ButtonSegment(value: 'any', label: Text('Any time')),
              ],
              selected: {time},
              onSelectionChanged: (v) => setSheet(() => time = v.first),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Reason for visit'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Your phone (optional, shared with the clinic)'),
            ),
            const SizedBox(height: 10),
            Text(
              doctor.canEmail
                  ? 'Your name, email${phoneCtrl.text.isEmpty ? '' : ', phone'} and reason will be emailed to the '
                      'clinic. They will reply to your email to confirm the time.'
                  : 'This clinic has no email on file: your request is saved and you can call them to confirm.',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _ink, minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
              icon: sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_outlined),
              label: Text(doctor.canEmail ? 'Send request to doctor' : 'Save request'),
              onPressed: sending
                  ? null
                  : () async {
                      if (reasonCtrl.text.trim().length < 3) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please add a short reason.')));
                        return;
                      }
                      setSheet(() => sending = true);
                      try {
                        final r = await repository.book(
                          doctorId: doctor.id,
                          date: date,
                          timeOfDay: time,
                          reason: reasonCtrl.text.trim(),
                          phone: phoneCtrl.text,
                          source: fromChat ? 'chat' : 'doctor_list',
                        );
                        if (ctx.mounted) Navigator.pop(ctx, r);
                      } on ApiException catch (e) {
                        setSheet(() => sending = false);
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    },
            ),
          ]),
        ),
      ),
    ),
  );
  reasonCtrl.dispose();
  phoneCtrl.dispose();
  if (result == null || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (d) => AlertDialog(
      icon: Icon(result.emailed ? Icons.mark_email_read_outlined : Icons.bookmark_added_outlined,
          color: result.emailed ? AppColors.success : AppColors.accent, size: 40),
      title: Text(result.emailed ? 'Request sent' : 'Request saved'),
      content: Text(result.message),
      actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
    ),
  );
  if (fromChat && context.mounted) Navigator.of(context).pop();
}
