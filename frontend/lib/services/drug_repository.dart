import 'api_client.dart';

class DrugBrand {
  DrugBrand.fromJson(Map<String, dynamic> j)
      : brand = j['brand'] as String? ?? '',
        generic = j['generic'] as String? ?? '',
        company = j['company'] as String? ?? '',
        forms = ((j['forms'] as List<dynamic>?) ?? const []).cast<String>(),
        strengths = ((j['strengths'] as List<dynamic>?) ?? const []).cast<String>(),
        source = j['source'] as String? ?? '';

  final String brand;
  final String source;
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

  /// Photo of a medicine box/strip -> its name (read by AI).
  Future<({String search, String brand, String generic, String strength})> identify(
      List<int> bytes, String filename, String mime) async {
    final d = await api.postFile('/drugs/identify', bytes: bytes, filename: filename, mimeType: mime)
        as Map<String, dynamic>;
    return (
      search: d['search'] as String? ?? '',
      brand: d['brand'] as String? ?? '',
      generic: d['generic'] as String? ?? '',
      strength: d['strength'] as String? ?? '',
    );
  }

  /// Feature 29: every brand of the same medicine with official prices, plus pharmacies in the city.
  Future<PriceComparison> prices(String name, {String strength = '', String city = ''}) async {
    final params = [
      'name=${Uri.encodeQueryComponent(name.trim())}',
      if (strength.trim().isNotEmpty) 'strength=${Uri.encodeQueryComponent(strength.trim())}',
      if (city.trim().isNotEmpty) 'city=${Uri.encodeQueryComponent(city.trim())}',
    ].join('&');
    return PriceComparison.fromJson(await api.get('/drugs/prices?$params') as Map<String, dynamic>);
  }
}

class PriceItem {
  PriceItem.fromJson(Map<String, dynamic> j)
      : brand = j['brand'] as String? ?? '',
        company = j['company'] as String? ?? '',
        formulation = j['formulation'] as String? ?? '',
        pack = j['pack'] as String? ?? '',
        form = j['form'] as String? ?? '',
        mrp = (j['mrp'] as num?)?.toDouble(),
        units = (j['units'] as num?)?.toInt(),
        perUnit = (j['per_unit'] as num?)?.toDouble(),
        sameStrength = j['same_strength'] as bool? ?? false,
        combo = j['combo'] as bool? ?? false;

  final String brand;
  final String company;
  final String formulation;
  final String pack;
  final String form;
  final double? mrp;
  final int? units;
  final double? perUnit;
  final bool sameStrength;
  final bool combo;
}

class PriceComparison {
  PriceComparison.fromJson(Map<String, dynamic> j)
      : generic = j['generic'] as String? ?? '',
        items = [for (final i in j['items'] as List? ?? const []) PriceItem.fromJson(i as Map<String, dynamic>)],
        cheapest = j['cheapest'] == null ? null : PriceItem.fromJson(j['cheapest'] as Map<String, dynamic>),
        otherBrands = [
          for (final b in j['other_brands'] as List? ?? const [])
            (
              brand: (b as Map)['brand'] as String? ?? '',
              company: b['company'] as String? ?? '',
              strengths: [for (final s in b['strengths'] as List? ?? const []) '$s'],
            )
        ],
        pharmacies = [
          for (final p in j['pharmacies'] as List? ?? const []) Pharmacy.fromJson(p as Map<String, dynamic>)
        ],
        loaded = j['price_list_loaded'] as bool? ?? false,
        note = j['note'] as String? ?? '',
        sourceName = (j['source'] as Map?)?['name'] as String? ?? '',
        sourceUrl = (j['source'] as Map?)?['url'] as String? ?? '';

  final String generic;
  final List<PriceItem> items;
  final PriceItem? cheapest;
  final List<({String brand, String company, List<String> strengths})> otherBrands;
  final List<Pharmacy> pharmacies;
  final bool loaded;
  final String note;
  final String sourceName;
  final String sourceUrl;
}
