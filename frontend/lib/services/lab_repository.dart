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
        notes = j['notes'] as String? ?? '';

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
        note = j['note'] as String? ?? '',
        directoryUrl = j['directory_url'] as String? ?? '';

  final String city;
  final bool knownCity;
  final List<TestLabs> tests;
  final List<LabOffer> otherLabs;
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

  Future<LabOptions> options(String city, List<String> tests) async {
    final q = [
      'city=${Uri.encodeQueryComponent(city)}',
      for (final t in tests) 'tests=${Uri.encodeQueryComponent(t)}',
    ].join('&');
    return LabOptions.fromJson(await api.get('/labs/options?$q') as Map<String, dynamic>);
  }

  Future<String?> myCity() async {
    final p = await api.get('/profile') as Map<String, dynamic>;
    final c = p['city'] as String?;
    return c == null || c.isEmpty ? null : c;
  }

  Future<void> saveCity(String city) => api.patch('/profile', body: {'city': city});
}
