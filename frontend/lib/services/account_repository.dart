import 'api_client.dart';

class AppNotification {
  const AppNotification(this.id, this.title, this.body, this.read, this.createdAt, this.link);

  final String id;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;
  final String? link;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        j['id'] as String,
        j['title'] as String,
        j['body'] as String,
        j['read'] as bool,
        DateTime.parse(j['created_at'] as String).toLocal(),
        j['link'] as String?,
      );
}

class ConsentItem {
  const ConsentItem(this.category, this.description, this.granted);

  final String category;
  final String description;
  final bool granted;

  String get title => switch (category) {
        'ai_processing' => 'AI processing',
        'mental_health' => 'Mental health data',
        'location' => 'Location',
        'camera' => 'Camera',
        'microphone' => 'Microphone',
        'caregiver_sharing' => 'Share with caregivers',
        _ => category,
      };

  factory ConsentItem.fromJson(Map<String, dynamic> j) =>
      ConsentItem(j['category'] as String, j['description'] as String, j['granted'] as bool);
}

/// Notifications and consent settings.
class AccountRepository {
  AccountRepository(this.api);

  final ApiClient api;

  Future<List<AppNotification>> notifications() async {
    final data = await api.get('/notifications') as List<dynamic>;
    return data.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> markRead(String id) => api.post('/notifications/$id/read');

  Future<void> markAllRead() => api.post('/notifications/read-all');

  Future<List<ConsentItem>> consents() async {
    final data = await api.get('/consents') as List<dynamic>;
    return data.map((e) => ConsentItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setConsent(String category, bool granted) =>
      api.post('/consents', body: {'category': category, 'granted': granted});
}
