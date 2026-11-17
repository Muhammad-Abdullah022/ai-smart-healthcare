import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/health_repository.dart';
import '../../services/medicine_repository.dart';
import '../../widgets/confirm_dialog.dart';

/// Feature 42: connect a smartwatch / fitness band over Bluetooth (BLE).
/// * Reads live heart rate (standard Heart Rate service 0x180D) and battery (0x180F) and saves
///   heart rate to Health Trends every minute.
/// * Medicine reminders: when a dose is due, the watch vibrates (Immediate Alert service 0x1802,
///   supported by most bands) and the app shows the reminder — while this screen/app is open.
class SmartwatchScreen extends StatefulWidget {
  const SmartwatchScreen({super.key});

  @override
  State<SmartwatchScreen> createState() => _SmartwatchScreenState();
}

bool _isUuid(Guid g, String short) {
  final s = g.toString().toLowerCase();
  return s == short || s.startsWith('0000$short-');
}

class _SmartwatchScreenState extends State<SmartwatchScreen> {
  late final HealthRepository _health = HealthRepository(context.read<AuthProvider>().repository.api);
  late final MedicineRepository _meds = MedicineRepository(context.read<AuthProvider>().repository.api);

  bool? _supported;
  bool _scanning = false;
  List<ScanResult> _results = [];
  BluetoothDevice? _device;
  BluetoothCharacteristic? _alert;
  int? _bpm;
  int? _battery;
  DateTime? _lastSaved;
  int _saved = 0;
  bool _remindersOn = true;
  final Set<String> _alerted = {};
  String? _lastReminder;
  final List<StreamSubscription> _subs = [];
  Timer? _reminderTimer;

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  Future<void> _checkSupport() async {
    bool ok = false;
    try {
      ok = !kIsWeb && await FlutterBluePlus.isSupported;
    } catch (_) {}
    if (mounted) setState(() => _supported = ok);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _reminderTimer?.cancel();
    _device?.disconnect();
    super.dispose();
  }

  Future<void> _scan() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android &&
          FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn();
      }
      setState(() {
        _scanning = true;
        _results = [];
      });
      _subs.add(FlutterBluePlus.scanResults.listen((r) {
        if (mounted) {
          setState(() => _results = r
              .where((x) => x.device.platformName.isNotEmpty || x.advertisementData.advName.isNotEmpty)
              .toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi)));
        }
      }));
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
    } catch (e) {
      if (mounted) showMessage(context, 'Bluetooth scan failed. Turn on Bluetooth and allow "Nearby devices".', error: true);
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(BluetoothDevice d) async {
    try {
      await FlutterBluePlus.stopScan();
      await d.connect(timeout: const Duration(seconds: 15));
      final services = await d.discoverServices();
      BluetoothCharacteristic? hr;
      for (final s in services) {
        for (final c in s.characteristics) {
          if (_isUuid(s.uuid, '180d') && _isUuid(c.uuid, '2a37')) hr = c;
          if (_isUuid(s.uuid, '1802') && _isUuid(c.uuid, '2a06')) _alert = c;
          if (_isUuid(s.uuid, '180f') && _isUuid(c.uuid, '2a19')) {
            final b = await c.read();
            if (b.isNotEmpty) _battery = b.first;
          }
        }
      }
      if (hr != null) {
        await hr.setNotifyValue(true);
        _subs.add(hr.onValueReceived.listen(_onHeartRate));
      }
      _subs.add(d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && mounted) {
          setState(() => _device = null);
        }
      }));
      setState(() => _device = d);
      _startReminders();
      if (hr == null && mounted) {
        showMessage(context, 'Connected. This watch does not share heart rate over standard Bluetooth.');
      }
    } catch (e) {
      if (mounted) showMessage(context, 'Could not connect to ${d.platformName}. Try again near the phone.', error: true);
    }
  }

  void _onHeartRate(List<int> data) {
    if (data.length < 2) return;
    final wide = (data[0] & 0x01) == 1;
    final bpm = wide && data.length >= 3 ? data[1] | (data[2] << 8) : data[1];
    if (bpm <= 0) return;
    setState(() => _bpm = bpm);
    final now = DateTime.now();
    if (_lastSaved == null || now.difference(_lastSaved!) >= const Duration(minutes: 1)) {
      _lastSaved = now;
      _health.addVital('heart_rate', bpm.toDouble(), source: 'watch').then((_) {
        if (mounted) setState(() => _saved++);
      }).catchError((_) {});
    }
  }

  Future<void> _vibrate() async {
    final c = _alert;
    if (c == null) return;
    try {
      await c.write([2], withoutResponse: c.properties.writeWithoutResponse);
    } catch (_) {}
  }

  void _startReminders() {
    _reminderTimer?.cancel();
    _checkDoses();
    _reminderTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkDoses());
  }

  Future<void> _checkDoses() async {
    if (!_remindersOn || _device == null) return;
    try {
      final doses = await _meds.today();
      for (final d in doses.where((d) => d.status == 'due')) {
        final key = '${d.medicineId}-${d.time}';
        if (_alerted.add(key)) {
          await _vibrate();
          if (mounted) {
            setState(() => _lastReminder = '${d.name} at ${d.time}');
            showMessage(context, 'Time for ${d.name} (${d.time}) — your watch was alerted.');
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smartwatch')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
        if (_supported == false) _unsupported() else if (_device != null) _connected() else _scanner(),
        const SizedBox(height: 16),
        _howItWorks(),
      ]),
    );
  }

  Widget _unsupported() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(20)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.bluetooth_disabled, size: 36, color: AppColors.deep),
          SizedBox(height: 8),
          Text('Bluetooth is not available here',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.deep)),
          SizedBox(height: 4),
          Text('Open the app on your Android or iPhone to connect a smartwatch. You can still add readings by hand in '
              'Health Trends.'),
        ]),
      );

  Widget _scanner() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(colors: [AppColors.deep, AppColors.green]),
          ),
          child: Column(children: [
            const Icon(Icons.watch_outlined, color: Colors.white, size: 54),
            const SizedBox(height: 8),
            const Text('Connect your smartwatch',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Turn on Bluetooth and keep the watch close to the phone.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withAlpha(220))),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.deep),
              onPressed: _scanning || _supported != true ? null : _scan,
              icon: _scanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bluetooth_searching),
              label: Text(_scanning ? 'Searching…' : 'Search for watches'),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        for (final r in _results)
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
            child: ListTile(
              leading: const Icon(Icons.watch, color: AppColors.green),
              title: Text(r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName),
              subtitle: Text('Signal ${r.rssi} dBm'),
              trailing: FilledButton(onPressed: () => _connect(r.device), child: const Text('Connect')),
            ),
          ),
        if (!_scanning && _results.isEmpty && _supported == true)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No watch found yet. Tap search. Some watches must be in "pairing" mode.',
                style: TextStyle(color: AppColors.textMuted)),
          ),
      ]);

  Widget _connected() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: AppColors.softShadow),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.bluetooth_connected, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_device!.platformName.isEmpty ? 'Smartwatch' : _device!.platformName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              if (_battery != null) Text('🔋 $_battery%'),
            ]),
            const SizedBox(height: 18),
            const Icon(Icons.favorite, color: AppColors.critical, size: 40),
            Text(_bpm == null ? '--' : '$_bpm',
                style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w800, color: AppColors.deep)),
            const Text('heart rate (bpm)', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Text('$_saved reading${_saved == 1 ? '' : 's'} saved to Health Trends',
                style: const TextStyle(fontSize: 12, color: AppColors.green)),
          ]),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: _remindersOn,
          onChanged: (v) => setState(() => _remindersOn = v),
          title: const Text('Medicine reminders on the watch'),
          subtitle: Text(_alert == null
              ? 'This watch has no alert service; reminders show in the app only'
              : (_lastReminder == null ? 'The watch vibrates when a dose is due' : 'Last: $_lastReminder')),
        ),
        if (_alert != null)
          OutlinedButton.icon(onPressed: _vibrate, icon: const Icon(Icons.vibration), label: const Text('Test vibration')),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            await _device?.disconnect();
            _reminderTimer?.cancel();
            if (mounted) setState(() => _device = null);
          },
          icon: const Icon(Icons.link_off, color: AppColors.critical),
          label: const Text('Disconnect', style: TextStyle(color: AppColors.critical)),
        ),
      ]);

  Widget _howItWorks() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(16)),
        child: const Text(
          'Works with watches and bands that use standard Bluetooth heart-rate and alert services (many fitness '
          'bands, Polar/Garmin heart-rate broadcast, Wear OS apps). Some brands (e.g. Apple Watch, some Mi/Huawei '
          'models) only share data through their own app. Reminders and saving work while the app is open.',
          style: TextStyle(fontSize: 12.5, color: AppColors.deep, height: 1.4),
        ),
      );
}
