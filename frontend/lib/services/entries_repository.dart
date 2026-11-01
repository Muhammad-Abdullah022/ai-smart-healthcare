import 'api_client.dart';

class Entry {
  const Entry(this.id, this.data, this.createdAt);

  final String id;
  final Map<String, dynamic> data;
  final DateTime createdAt;

  factory Entry.fromJson(Map<String, dynamic> j) =>
      Entry(j['id'] as String, j['data'] as Map<String, dynamic>, DateTime.parse(j['created_at'] as String).toLocal());
}

/// Saves what the user enters on any feature screen (POST /entries/{feature}).
class EntriesRepository {
  EntriesRepository(this.api);

  final ApiClient api;

  Future<List<Entry>> list(int feature) async {
    final data = await api.get('/entries/$feature') as List<dynamic>;
    return data.map((e) => Entry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Entry> add(int feature, Map<String, dynamic> values) async {
    final data = await api.post('/entries/$feature', body: {'data': values}) as Map<String, dynamic>;
    return Entry.fromJson(data);
  }

  Future<void> archive(int feature, String id) => api.post('/entries/$feature/$id/archive');
}
