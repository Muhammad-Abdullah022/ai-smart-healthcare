import 'api_client.dart';

class DrugBrand {
  DrugBrand.fromJson(Map<String, dynamic> j)
      : brand = j['brand'] as String? ?? '',
        generic = j['generic'] as String? ?? '',
        company = j['company'] as String? ?? '',
        forms = ((j['forms'] as List<dynamic>?) ?? const []).cast<String>(),
        strengths = ((j['strengths'] as List<dynamic>?) ?? const []).cast<String>();

  final String brand;
  final String generic;
  final String company;
  final List<String> forms;
  final List<String> strengths;
}

class GenericInfo {
  GenericInfo.fromJson(Map<String, dynamic> j)
      : generic = j['generic'] as String? ?? '',
        drugClass = j['drug_class'] as String? ?? '',
        uses = j['uses'] as String? ?? '',
        sideEffects = j['side_effects'] as String? ?? '',
        warnings = j['warnings'] as String? ?? '';

  final String generic;
  final String drugClass;
  final String uses;
  final String sideEffects;
  final String warnings;
}

class DrugDetail {
  DrugDetail.fromJson(Map<String, dynamic> j)
      : medicine = j['medicine'] == null ? null : DrugBrand.fromJson(j['medicine'] as Map<String, dynamic>),
        generic = j['generic'] == null ? null : GenericInfo.fromJson(j['generic'] as Map<String, dynamic>),
        alternatives = ((j['alternatives'] as List<dynamic>?) ?? const [])
            .map((e) => DrugBrand.fromJson(e as Map<String, dynamic>))
            .toList(),
        aiGuess = j['ai_guess'] as bool? ?? false,
        note = j['note'] as String? ?? '';

  final DrugBrand? medicine;
  final GenericInfo? generic;
  final List<DrugBrand> alternatives;
  final bool aiGuess;
  final String note;
}

class Pharmacy {
  Pharmacy.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String? ?? '',
        address = j['address'] as String? ?? '',
        phone = j['phone'] as String? ?? '',
        hours = j['hours'] as String? ?? '',
        kind = j['kind'] as String? ?? 'independent',
        open24h = j['open_24h'] as bool? ?? false,
        source = j['source'] as String? ?? '',
        demo = j['demo'] as bool? ?? false;

  final String name;
  final String address;
  final String phone;
  final String hours;
  final String kind; // chain / independent / government
  final bool open24h;
  final String source;
  final bool demo;
}

/// Medicine database (brands, salts, same-salt alternatives) and the pharmacy directory.
class DrugRepository {
  DrugRepository(this.api);
  final ApiClient api;

  Future<List<DrugBrand>> search(String q, {int limit = 30}) async {
    if (q.trim().isEmpty) return [];
    final data = await api.get('/drugs/search?q=${Uri.encodeQueryComponent(q.trim())}&limit=$limit')
        as Map<String, dynamic>;
    return (data['results'] as List<dynamic>).map((e) => DrugBrand.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DrugDetail> detail(String name) async => DrugDetail.fromJson(
      await api.get('/drugs/detail?name=${Uri.encodeQueryComponent(name)}') as Map<String, dynamic>);

  Future<({int brands, int generics})> stats() async {
    final d = await api.get('/drugs/stats') as Map<String, dynamic>;
    return (brands: d['brands'] as int, generics: d['generics'] as int);
  }

  Future<List<Pharmacy>> pharmacies(String city, {String? q, bool open24h = false}) async {
    final params = [
      'city=${Uri.encodeQueryComponent(city)}',
      if (q != null && q.trim().isNotEmpty) 'q=${Uri.encodeQueryComponent(q.trim())}',
      if (open24h) 'open_24h=true',
    ].join('&');
    final data = await api.get('/pharmacies?$params') as Map<String, dynamic>;
    return (data['pharmacies'] as List<dynamic>).map((e) => Pharmacy.fromJson(e as Map<String, dynamic>)).toList();
  }
}
