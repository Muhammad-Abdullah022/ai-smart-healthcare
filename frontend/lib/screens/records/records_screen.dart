import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/state_views.dart';

/// Medical records tab. Uploading and storing records comes with
/// feature 38 (EHR) and backend task C-12 (secure file storage).
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Medical records')),
      body: EmptyView(
        icon: Icons.folder_open_outlined,
        title: 'No records yet',
        message: 'Your reports, prescriptions and documents will appear here once '
            'secure record storage is ready.',
        actionLabel: 'Learn more',
        onAction: () => context.push('/feature/38'),
      ),
    );
  }
}
