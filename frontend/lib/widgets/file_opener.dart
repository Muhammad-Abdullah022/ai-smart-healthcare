import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a downloaded file (PDF, Word, photo) with the phone's own viewer.
/// On the web it opens in a new browser tab instead.
Future<String?> openFileBytes(List<int> bytes, String fileName, String mimeType) async {
  if (kIsWeb) {
    final ok = await launchUrl(Uri.dataFromBytes(bytes, mimeType: mimeType), webOnlyWindowName: '_blank');
    return ok ? null : 'Could not open the file.';
  }
  final dir = await getTemporaryDirectory();
  final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._() -]'), '_');
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(bytes, flush: true);
  final result = await OpenFilex.open(file.path, type: mimeType);
  return result.type == ResultType.done ? null : 'No app found to open this file (${result.message}).';
}
