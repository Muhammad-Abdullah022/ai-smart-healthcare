import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

DateTime _date(dynamic v) => DateTime.tryParse('$v')?.toLocal() ?? DateTime.now();

class ConsultMessage {
  ConsultMessage.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        sender = j['sender'] as String,
        kind = j['kind'] as String,
        text = j['text'] as String? ?? '',
        meta = (j['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt = _date(j['created_at']);

  final String id;
  final String sender; // patient / doctor / system
  final String kind; // text, summary, status, payment, payment_ok, payment_rejected, prescription, clinic_visit
  final String text;
  final Map<String, dynamic> meta;
  final DateTime createdAt;
}

class ConsultSummary {
  ConsultSummary.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        status = j['status'] as String,
        statusText = j['status_text'] as String? ?? '',
        doctorName = j['doctor_name'] as String? ?? '',
        specialty = j['specialty'] as String? ?? '',
        patientName = j['patient_name'] as String? ?? '',
        reason = j['reason'] as String? ?? '',
        fee = (j['fee_pkr'] as num?)?.toDouble(),
        paid = j['paid'] as bool? ?? false,
        unread = j['unread'] as int? ?? 0,
        lastMessage = j['last_message'] as String? ?? '',
        updatedAt = _date(j['updated_at']);

  final String id;
  final String status;
  final String statusText;
  final String doctorName;
  final String specialty;
  final String patientName;
  final String reason;
  final double? fee;
  final bool paid;
  final int unread;
  final String lastMessage;
  final DateTime updatedAt;

  bool get open => const {'requested', 'awaiting_payment', 'payment_submitted', 'paid', 'advised', 'visit_clinic'}
      .contains(status);
}

class ConsultDetail {
  ConsultDetail.fromJson(Map<String, dynamic> j)
      : summary = ConsultSummary.fromJson(j),
        role = j['role'] as String,
        messages = [for (final m in j['messages'] as List) ConsultMessage.fromJson(m as Map<String, dynamic>)],
        doctor = (j['doctor'] as Map).cast<String, dynamic>(),
        patient = (j['patient'] as Map?)?.cast<String, dynamic>(),
        payment = (j['payment'] as Map?)?.cast<String, dynamic>();

  final ConsultSummary summary;
  final String role; // patient / doctor
  final List<ConsultMessage> messages;
  final Map<String, dynamic> doctor;
  final Map<String, dynamic>? patient;
  final Map<String, dynamic>? payment;

  bool get isDoctor => role == 'doctor';
  String get status => summary.status;
}

class DoctorPanelData {
  DoctorPanelData.fromJson(Map<String, dynamic> j)
      : doctor = (j['doctor'] as Map).cast<String, dynamic>(),
        stats = (j['stats'] as Map).cast<String, dynamic>(),
        consultations = [for (final c in j['consultations'] as List) ConsultSummary.fromJson(c as Map<String, dynamic>)];

  final Map<String, dynamic> doctor;
  final Map<String, dynamic> stats;
  final List<ConsultSummary> consultations;
}

/// Online consultations (patient side) and the doctor panel.
class ConsultationRepository {
  ConsultationRepository(this.api);

  final ApiClient api;

  Future<ConsultSummary> request({required String doctorId, required String reason, required bool shareAssessment,
          String source = 'doctor_list'}) async =>
      ConsultSummary.fromJson(await api.post('/consultations', body: {
        'doctor_id': doctorId,
        'reason': reason,
        'share_assessment': shareAssessment,
        'source': source,
      }) as Map<String, dynamic>);

  Future<List<ConsultSummary>> mine() async =>
      [for (final c in await api.get('/consultations') as List) ConsultSummary.fromJson(c as Map<String, dynamic>)];

  Future<ConsultDetail> get(String id) async =>
      ConsultDetail.fromJson(await api.get('/consultations/$id') as Map<String, dynamic>);

  Future<void> send(String id, String text) => api.post('/consultations/$id/messages', body: {'text': text});
  Future<void> accept(String id) => api.post('/consultations/$id/accept');
  Future<void> decline(String id, String reason) => api.post('/consultations/$id/decline', body: {'reason': reason});
  Future<void> cancel(String id) => api.post('/consultations/$id/cancel');
  Future<void> complete(String id) => api.post('/consultations/$id/complete');

  Future<void> uploadPayment(String id, List<int> bytes, String filename, String mime, String tid) =>
      api.postFile('/consultations/$id/payment',
          bytes: bytes, filename: filename, mimeType: mime, fields: {'transaction_id': tid});

  Future<List<int>> file(String id, String fileId) => api.getBytes('/consultations/$id/files/$fileId');

  Future<void> verifyPayment(String id, bool ok, {String note = ''}) =>
      api.post('/consultations/$id/payment/verify', body: {'ok': ok, 'note': note});

  Future<Map<String, dynamic>> prescribe(String id, Map<String, dynamic> body) async =>
      (await api.post('/consultations/$id/prescribe', body: body) as Map).cast<String, dynamic>();

  Future<void> visitClinic(String id, {required String urgency, required String reason, String date = ''}) =>
      api.post('/consultations/$id/visit-clinic', body: {'urgency': urgency, 'reason': reason, 'date': date});

  // Doctor panel
  Future<Map<String, dynamic>?> myDoctorProfile() async {
    try {
      return (await api.get('/doctor-panel/me') as Map).cast<String, dynamic>();
    } on ApiException catch (e) {
      if (e.statusCode == 403) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> saveDoctorProfile(Map<String, dynamic> body) async =>
      (await api.put('/doctor-panel/me', body: body) as Map).cast<String, dynamic>();

  Future<DoctorPanelData> panel() async =>
      DoctorPanelData.fromJson(await api.get('/doctor-panel/consultations') as Map<String, dynamic>);
}

/// One live connection to the backend (WebSocket). Screens listen to [events];
/// it reconnects by itself and sends a ping every 25 seconds.
class LiveEvents {
  LiveEvents._();

  static final LiveEvents instance = LiveEvents._();

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  WebSocketChannel? _channel;
  Timer? _ping;
  Timer? _retry;
  ApiClient? _api;
  bool _connecting = false;

  /// True while the socket is open (shown as "Live" in the chat).
  bool connected = false;

  Stream<Map<String, dynamic>> get events => _controller.stream;

  Future<void> ensureConnected(ApiClient api) async {
    _api = api;
    if (connected || _connecting) return;
    _connecting = true;
    try {
      await api.get('/auth/me'); // refreshes the login token if it expired
      final token = await api.tokens.readAccessToken();
      if (token == null) return;
      final base = Uri.parse(api.baseUrl);
      final uri = base.replace(
          scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/ws', queryParameters: {'token': token});
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;
      _channel = channel;
      connected = true;
      _controller.add({'type': 'connected'});
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => _channel?.sink.add('ping'));
      channel.stream.listen((data) {
        try {
          _controller.add((jsonDecode('$data') as Map).cast<String, dynamic>());
        } catch (_) {}
      }, onDone: _lost, onError: (_) => _lost(), cancelOnError: true);
    } catch (_) {
      _lost();
    } finally {
      _connecting = false;
    }
  }

  void _lost() {
    connected = false;
    _ping?.cancel();
    _channel = null;
    _controller.add({'type': 'disconnected'});
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 4), () {
      if (_api != null) ensureConnected(_api!);
    });
  }

  void disconnect() {
    _api = null;
    _retry?.cancel();
    _ping?.cancel();
    _channel?.sink.close();
    _channel = null;
    connected = false;
  }
}
