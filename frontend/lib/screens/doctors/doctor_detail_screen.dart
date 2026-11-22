import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../services/doctor_repository.dart';
import '../consult/doctor_panel_screens.dart';
import 'doctors_screens.dart';

/// Doctor profile: large avatar on soft circles, name, fee, experience, details and "Get Appointment".
class DoctorDetailScreen extends StatelessWidget {
  const DoctorDetailScreen(
      {super.key, required this.doctor, required this.repository, this.reason, this.fromChat = false});

  final Doctor doctor;
  final DoctorRepository repository;
  final String? reason;
  final bool fromChat;

  @override
  Widget build(BuildContext context) {
    final d = doctor;
    final fee = d.fee != null ? 'Rs ${d.fee!.toStringAsFixed(0)}' : (d.government ? 'Govt' : '—');
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              // Header: soft concentric circles behind the doctor's avatar.
              SizedBox(
                height: 290,
                child: Stack(alignment: Alignment.center, children: [
                  for (final (size, alpha) in const [(280.0, 60), (220.0, 90), (165.0, 140)])
                    Container(
                      width: size,
                      height: size,
                      decoration:
                          BoxDecoration(shape: BoxShape.circle, color: AppColors.softGreen.withAlpha(alpha)),
                    ),
                  DoctorAvatar(doctor: d, size: 150),
                  Positioned(
                    left: 12,
                    top: 8,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 1,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.deep),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ]),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: AppColors.softShadow,
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(d.name,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.deep)),
                        const SizedBox(height: 2),
                        Text(d.specialty,
                            style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(fee, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.deep)),
                      Text(d.fee != null ? 'Fees' : 'Hospital OPD',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ]),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _pill(Icons.work_outline_rounded,
                        d.experienceYears != null ? '${d.experienceYears} years' : 'Consultant'),
                    if (d.government) _pill(Icons.account_balance_outlined, 'Govt. of Punjab'),
                    if (d.online) _pill(Icons.forum_outlined, 'Online consultation'),
                  ]),
                  const SizedBox(height: 16),
                  if (d.qualification.isNotEmpty) _row(Icons.school_outlined, 'Qualification', d.qualification),
                  if (d.clinic.isNotEmpty) _row(Icons.local_hospital_outlined, 'Clinic / hospital', d.clinic),
                  if (d.address.isNotEmpty) _row(Icons.place_outlined, 'Address', d.address),
                  if (d.timings.isNotEmpty) _row(Icons.schedule, 'Timings', d.timings),
                  if (d.phone.isNotEmpty)
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: d.phone));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Number copied: ${d.phone}')));
                      },
                      child: _row(Icons.call_outlined, 'Phone · tap to copy',
                          d.phone),
                    ),
                  const SizedBox(height: 6),
                  const Text('About', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.deep)),
                  const SizedBox(height: 6),
                  Text(
                    d.about.isNotEmpty
                        ? d.about
                        : '${d.name} is a ${d.specialty.toLowerCase()} at ${d.clinic.isEmpty ? 'a hospital in ${d.city}' : d.clinic}. '
                            'Listed in the Punjab Health Department consultants list. OPD timings and fees are set by the hospital.',
                    style: const TextStyle(color: AppColors.text, height: 1.5, fontSize: 13.5),
                  ),
                  if (d.sourceUrl.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                        'Source: ${Uri.tryParse(d.sourceUrl)?.host ?? d.sourceUrl}'
                        '${d.checked.isNotEmpty ? ' · checked ${d.checked}' : ''}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ]),
              ),
            ]),
          ),
          // Big "Get Appointment" button, like the design.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(colors: [AppColors.green, AppColors.deep]),
                boxShadow: [BoxShadow(color: AppColors.green.withAlpha(80), blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                  onPressed: () async {
                    if (d.online || d.hasAccount) {
                      await showConsultRequestSheet(context, doctor: d, reason: reason, fromChat: fromChat);
                      return;
                    }
                    final booked = await showDoctorBookingSheet(context,
                        repository: repository, doctor: d, reason: reason, fromChat: fromChat);
                    // From the chat: go back to the chat (profile and list) after booking.
                    if (booked && fromChat && context.mounted) {
                      Navigator.of(context)
                        ..pop()
                        ..pop();
                    }
                  },
                  child: Text(d.online ? 'Consult online now' : d.hasAccount ? 'Book & chat with doctor' : 'Get Appointment',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
          if (d.online || d.hasAccount)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextButton(
                onPressed: () => showDoctorBookingSheet(context,
                    repository: repository, doctor: d, reason: reason, fromChat: fromChat),
                child: const Text('Or request a clinic appointment'),
              ),
            ),
        ]),
      ),
    );
  }

  static Widget _pill(IconData icon, String text, {bool warn = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: warn ? const Color(0xFFFFEDD5) : AppColors.mint, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: warn ? const Color(0xFFC2410C) : AppColors.green),
          const SizedBox(width: 5),
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: warn ? const Color(0xFFC2410C) : AppColors.deep)),
        ]),
      );

  static Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: AppColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              Text(value, style: const TextStyle(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      );
}
