import 'api_client.dart';

class LabOffer {
  LabOffer.fromJson(Map<String, dynamic> j)
      : lab = j['lab'] as String? ?? '',
        branch = j['branch'] as String? ?? '',
        address = j['address'] as String? ?? '',
        phone = j['phone'] as String? ?? '',
        labType = j['lab_type'] as String? ?? '',
        publishedName = j['published_name'] as String? ?? '',
        price = (j['price_pkr'] as num?)?.toDouble(),
        discountPrice = (j['discount_price_pkr'] as num?)?.toDouble(),
        sourceUrl = j['source_url'] as String? ?? '',
        checked = j['checked'] as String? ?? '',
        notes = j['notes'] as String? ?? '',
        branches = j['branches'] as int? ?? 1;

  final String lab;
  final String branch;
  final String address;
  final String phone;
  final String labType;
  final String publishedName;
  final double? price;

  /// Lower price some listings show for online booking (e.g. InstaCare).
  final double? discountPrice;
  final String sourceUrl;
  final String checked;
  final String notes;

  /// How many branches this lab has in the city.
  final int branches;
}

class TestLabs {
  TestLabs.fromJson(Map<String, dynamic> j)
      : asked = j['asked'] as String,
        nameEn = j['name_en'] as String,
        offers = (j['offers'] as List<dynamic>).map((o) => LabOffer.fromJson(o as Map<String, dynamic>)).toList();

  final String asked;
  final String nameEn;
  final List<LabOffer> offers;
}

class LabOptions {
  LabOptions.fromJson(Map<String, dynamic> j)
      : city = j['city'] as String,
        knownCity = j['known_city'] as bool? ?? false,
        tests = (j['tests'] as List<dynamic>).map((t) => TestLabs.fromJson(t as Map<String, dynamic>)).toList(),
        otherLabs = (j['labs_without_prices'] as List<dynamic>)
            .map((o) => LabOffer.fromJson(o as Map<String, dynamic>))
            .toList(),
        otherTotal = j['other_total'] as int? ?? 0,
        note = j['note'] as String? ?? '',
        directoryUrl = j['directory_url'] as String? ?? '';

  final String city;
  final bool knownCity;
  final List<TestLabs> tests;
  final List<LabOffer> otherLabs;

  /// How many labs in the city have no published price for these tests (only some are in [otherLabs]).
  final int otherTotal;
  final String note;
  final String directoryUrl;
}

class CityOption {
  CityOption.fromJson(Map<String, dynamic> j)
      : city = j['city'] as String,
        district = j['district'] as String? ?? '',
        labs = j['labs'] as int? ?? 0;

  final String city;
  final String district;
  final int labs;
}

/// Labs, published test prices and the user's city (features 5–7).
class LabRepository {
  LabRepository(this.api);

  final ApiClient api;

  Future<List<CityOption>> cities() async {
    final data = await api.get('/labs/cities') as List<dynamic>;
    return data.map((c) => CityOption.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<LabOptions> options(String city, List<String> tests, {int otherLimit = 8}) async {
    final q = [
      'city=${Uri.encodeQueryComponent(city)}',
      'other_limit=$otherLimit',
      for (final t in tests) 'tests=${Uri.encodeQueryComponent(t)}',
    ].join('&');
    return LabOptions.fromJson(await api.get('/labs/options?$q') as Map<String, dynamic>);
  }

  /// Standard tests (English names) and how many labs in the city publish a price for each.
  Future<List<({String key, String name, int labsWithPrice})>> tests(String city) async {
    final data = await api.get('/labs/tests?city=${Uri.encodeQueryComponent(city)}') as List<dynamic>;
    return [
      for (final t in data.cast<Map<String, dynamic>>())
        (key: t['key'] as String, name: t['name'] as String, labsWithPrice: t['labs_with_price'] as int? ?? 0)
    ];
  }

  Future<String?> myCity() async {
    final p = await api.get('/profile') as Map<String, dynamic>;
    final c = p['city'] as String?;
    return c == null || c.isEmpty ? null : c;
  }

  Future<void> saveCity(String city) => api.patch('/profile', body: {'city': city});
}
