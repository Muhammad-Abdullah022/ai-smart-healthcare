import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/doctor_repository.dart';
import '../../services/lab_repository.dart';
import '../../widgets/state_views.dart';
import 'doctor_detail_screen.dart';
import '../labs/lab_options_screen.dart' show CityPickerScreen;

const _lime = AppColors.softGreen;

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
      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _lime)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('See all $what', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.deep)),
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.deep, shape: const StadiumBorder()),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text('Open ${l.site}'),
              onPressed: () => openExternal(context, l.url),
            ),
        ]),
      ]),
    );
  }
}

/// Feature 10 entry: opens the doctor list for the user's city.
class DoctorsIntroScreen extends StatelessWidget {
  const DoctorsIntroScreen({super.key});

  @override
  Widget build(BuildContext context) => const DoctorListScreen();
}

String greeting() {
  final h = DateTime.now().hour;
  return h < 12 ? 'Good Morning' : (h < 17 ? 'Good Afternoon' : 'Good Evening');
}

/// The doctor directory for the user's city: greeting, search + filter, and doctor cards.
/// Tapping a doctor opens the profile screen with "Get Appointment".
/// With [specialty] and [reason] (from the chat), the list is pre-filtered and booking carries the reason.
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
  final _search = TextEditingController();
  String? _city;
  String? _specialty;
  bool _cityLoaded = false;
  Future<List<Doctor>>? _future;
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
      _pickCity();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _future = _repo.doctors(city: _city, specialty: _specialty, search: _search.text);
      });

  Future<void> _pickCity() async {
    final c = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => CityPickerScreen(repository: _labs)));
    if (c == null || !mounted) return;
    _city = c;
    _labs.saveCity(c).catchError((_) {});
    _reload();
  }

  Future<void> _filters() async {
    final specs = await _repo.specialties(city: _city).catchError((_) => <({String name, int doctors})>[]);
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Filter doctors', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Specialty${_city == null ? '' : ' in $_city'}', style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _FilterChip(label: 'All specialists', selected: _specialty == null, onTap: () => Navigator.pop(ctx, '')),
                for (final sp in specs.where((x) => x.doctors > 0))
                  _FilterChip(
                      label: '${sp.name} (${sp.doctors})',
                      selected: _specialty == sp.name,
                      onTap: () => Navigator.pop(ctx, sp.name)),
              ]),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                icon: const Icon(Icons.location_on_outlined),
                label: Text(_city == null ? 'Choose city' : 'Change city ($_city)'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _pickCity();
                },
              ),
            ]),
          ),
        ),
      ),
    );
    if (picked == null) return;
    _specialty = picked.isEmpty ? null : picked;
    _reload();
  }

  void _open(Doctor d) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DoctorDetailScreen(
          doctor: d, repository: _repo, reason: widget.reason, fromChat: widget.fromChat)));

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthProvider>().user?.fullName ?? '';
    final first = name.trim().isEmpty ? 'there' : name.trim();
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 16, 6),
            child: Row(children: [
              if (Navigator.of(context).canPop())
                IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context))
              else
                const SizedBox(width: 8),
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [AppColors.green, AppColors.deep]),
                ),
                alignment: Alignment.center,
                child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Hello, ${greeting()}!', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  Text(first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.deep)),
                ]),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _pickCity,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.location_on, size: 16, color: AppColors.green),
                    const SizedBox(width: 4),
                    Text(_city ?? 'City', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.deep, fontSize: 13)),
                  ]),
                ),
              ),
            ]),
          ),
          // Search pill with filter button (like the design).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.softGreen),
              ),
              child: Row(children: [
                const SizedBox(width: 18),
                const Icon(Icons.search, color: AppColors.deep),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search doctor, clinic or area',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _reload(),
                  ),
                ),
                IconButton(
                  tooltip: 'Filter',
                  icon: const Icon(Icons.tune_rounded, color: AppColors.deep),
                  onPressed: _filters,
                ),
                const SizedBox(width: 6),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
            child: Row(children: [
              Expanded(
                child: Text(_specialty == null ? 'All Doctors List' : '${_specialty}s',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.deep)),
              ),
              if (_specialty != null)
                TextButton.icon(
                  onPressed: () {
                    _specialty = null;
                    _reload();
                  },
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Clear'),
                ),
            ]),
          ),
          Expanded(child: _list()),
        ]),
      ),
    );
  }

  Widget _list() {
    if (!_cityLoaded) return const LoadingView();
    if (_city == null) {
      return EmptyView(
        icon: Icons.location_city_outlined,
        title: 'Choose your city',
        message: 'See doctors and specialists in your city with their check-up fee.',
        actionLabel: 'Choose city',
        onAction: _pickCity,
      );
    }
    return FutureBuilder<List<Doctor>>(
      future: _future,
      builder: (context, snap) {
        if (_future == null || snap.connectionState != ConnectionState.done) return const LoadingView();
        if (snap.hasError) {
          final e = snap.error;
          return ErrorView(message: e is ApiException ? e.message : 'Could not load doctors.', onRetry: _reload);
        }
        final list = snap.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text('${list.length} doctor${list.length == 1 ? '' : 's'} in $_city',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
            for (final d in list) DoctorCard(doctor: d, onTap: () => _open(d)),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 4, 14),
                child: Text('No doctors in the app\'s list here yet — see all doctors below.',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            const SizedBox(height: 6),
            ExternalDoctorsCard(city: _city, specialty: _specialty, district: _districtOf[_city?.toLowerCase()]),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.softGreen,
        backgroundColor: Colors.white,
        labelStyle: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: AppColors.deep),
        shape: const StadiumBorder(),
      );
}

/// One doctor in the list: photo-style avatar, name, specialty, experience and "See details".
class DoctorCard extends StatelessWidget {
  const DoctorCard({super.key, required this.doctor, required this.onTap});
  final Doctor doctor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = doctor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(children: [
              DoctorAvatar(doctor: d, size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.deep)),
                    ),
                    const Text('See details',
                        style: TextStyle(fontSize: 11.5, color: AppColors.green, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 2),
                  Text(d.specialty,
                      style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w500, fontSize: 13.5)),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.work_outline_rounded, size: 16, color: AppColors.green),
                    const SizedBox(width: 6),
                    Text(
                        d.experienceYears != null
                            ? '${d.experienceYears} years'
                            : (d.government ? 'Govt. consultant' : 'Consultant'),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
                    const Spacer(),
                    Text(d.fee != null ? 'Rs ${d.fee!.toStringAsFixed(0)}' : (d.government ? 'Govt OPD' : ''),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.deep)),
                  ]),
                  if (d.demo)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Demo profile', style: TextStyle(fontSize: 10.5, color: Color(0xFFC2410C))),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Doctor "photo": no real photos are stored, so a clean illustrated avatar with initials.
class DoctorAvatar extends StatelessWidget {
  const DoctorAvatar({super.key, required this.doctor, this.size = 72});
  final Doctor doctor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final female = doctor.gender == 'female';
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.white, width: size * 0.05),
          boxShadow: const [BoxShadow(color: Color(0x14013237), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: female
                  ? const [Color(0xFFC0E6BA), Color(0xFF7FC59A)]
                  : const [Color(0xFFD5EFD0), Color(0xFF4CA771)],
            ),
          ),
          alignment: Alignment.center,
          child: Text(doctor.initials,
              style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w700, color: AppColors.deep)),
        ),
      ),
      Positioned(
        right: -2,
        bottom: -2,
        child: Container(
          width: size * 0.36,
          height: size * 0.36,
          decoration: BoxDecoration(
              color: AppColors.deep, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          child: Icon(Icons.medical_services_rounded, size: size * 0.18, color: Colors.white),
        ),
      ),
    ]);
  }
}

/// Confirm and send an appointment request. If the doctor has an email, it is sent to them.
/// Returns true when a request was sent or saved.
Future<bool> showDoctorBookingSheet(BuildContext context,
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.deep, minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
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
  if (result == null || !context.mounted) return false;
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
  return true;
}
