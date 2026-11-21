import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/doctor_repository.dart';
import '../consult/doctor_panel_screens.dart' show showConsultRequestSheet;
import 'doctor_detail_screen.dart';
import 'doctors_screens.dart';

/// When a doctor visit is advised: "Book an appointment?" Yes -> choose a doctor -> request is emailed.
/// Right after the AI names a specialist: only doctors of that specialty (user's city first),
/// each with "Book now". Online doctors open the live consultation straight away; others get the
/// appointment request sheet. The rest of the flow (chat, payment, prescription) continues from there.
class DoctorBookingCard extends StatefulWidget {
  const DoctorBookingCard({super.key, required this.specialty, required this.reason});
  final String specialty;
  final String reason;

  @override
  State<DoctorBookingCard> createState() => _DoctorBookingCardState();
}

class _DoctorBookingCardState extends State<DoctorBookingCard> {
  late final DoctorRepository _repo = DoctorRepository(context.read<AuthProvider>().repository.api);
  late Future<RecommendedDoctors> _future = _repo.recommended(widget.specialty);
  bool _dismissed = false;
  String? _bookedId;

  Future<void> _book(Doctor d) async {
    if (d.online || d.hasAccount) {
      final id = await showConsultRequestSheet(context, doctor: d, reason: widget.reason, fromChat: true);
      if (id != null && mounted) setState(() => _bookedId = d.id);
    } else {
      final ok = await showDoctorBookingSheet(context,
          repository: _repo, doctor: d, reason: widget.reason, fromChat: true);
      if (ok && mounted) setState(() => _bookedId = d.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<RecommendedDoctors>(
        future: _future,
        builder: (context, snap) {
          final r = snap.data;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryDeep])),
              child: Row(children: [
                const Icon(Icons.medical_services_outlined, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Book a ${r?.specialty ?? widget.specialty}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                        r == null
                            ? 'Finding doctors for this problem…'
                            : r.backup
                                ? 'No ${widget.specialty} listed yet — showing the backup the AI advised.'
                                : 'Only ${r.specialty}s${r.city != null ? ' in ${r.city}' : ''} for this problem',
                        style: const TextStyle(color: Color(0xFFCBD7E6), fontSize: 12.5)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Not now',
                  onPressed: () => setState(() => _dismissed = true),
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                ),
              ]),
            ),
            if (snap.hasError)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Expanded(child: Text('Could not load doctors.', style: TextStyle(color: AppColors.textMuted))),
                  TextButton(
                      onPressed: () => setState(() => _future = _repo.recommended(widget.specialty)),
                      child: const Text('Retry')),
                ]),
              )
            else if (r == null)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
              )
            else if (r.doctors.isEmpty)
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text('No doctor of this specialty is listed yet. Use "See all doctors" to search other cities.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              )
            else
              for (final d in r.doctors) _doctorRow(d, r.otherCity.contains(d.id)),
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DoctorListScreen(
                    specialty: r?.specialty ?? widget.specialty, reason: widget.reason, fromChat: true),
              )),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                      r != null && r.totalInCity > r.doctors.length
                          ? 'See all ${r.totalInCity} ${r.specialty}s'
                          : 'See all doctors',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, color: AppColors.primary, size: 20),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _doctorRow(Doctor d, bool otherCity) {
    final booked = _bookedId == d.id;
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(children: [
        InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DoctorDetailScreen(
                  doctor: d, repository: _repo, reason: widget.reason, fromChat: true))),
          child: DoctorAvatar(doctor: d, size: 46),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.text)),
            Text(
                [
                  d.city + (otherCity ? ' (other city)' : ''),
                  if (d.fee != null) 'Rs ${d.fee!.toStringAsFixed(0)}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 3),
            Wrap(spacing: 4, children: [
              if (d.online) _tag('Online now', AppColors.green),
              if (d.government) _tag('Govt. list', AppColors.primary),
              if (d.demo) _tag('Demo profile', AppColors.warning),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        booked
            ? const Chip(
                avatar: Icon(Icons.check_circle, color: AppColors.green, size: 18),
                label: Text('Booked'),
                visualDensity: VisualDensity.compact,
              )
            : FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: d.online ? AppColors.green : AppColors.primary,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: () => _book(d),
                child: Text(d.online ? 'Consult now' : 'Book now', style: const TextStyle(fontSize: 13)),
              ),
      ]),
    );
  }

  static Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
      );
}

