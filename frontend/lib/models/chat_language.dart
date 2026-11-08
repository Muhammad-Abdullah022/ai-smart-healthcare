/// Languages the health assistant can talk in.
class ChatLanguage {
  const ChatLanguage({
    required this.code,
    required this.label,
    required this.ttsLocale,
    required this.speechLocale,
    required this.greeting,
    required this.hint,
    required this.listening,
    required this.reportReading,
    required this.checkIntro,
    required this.describeSymptoms,
    this.rtl = false,
  });

  /// Sent to the backend: en / ur / roman_ur.
  final String code;
  final String label;

  /// Voice used to read replies aloud.
  final String ttsLocale;

  /// Language the microphone listens for.
  final String speechLocale;
  final String greeting;
  final String hint;
  final String listening;
  final String reportReading;

  /// Said before the symptom-check follow-up questions.
  final String checkIntro;

  /// Asked when the user starts a symptom check from the tools menu.
  final String describeSymptoms;
  final bool rtl;

  static ChatLanguage byCode(String code) =>
      chatLanguages.firstWhere((l) => l.code == code, orElse: () => chatLanguages.first);
}

const chatLanguages = [
  ChatLanguage(
    code: 'en',
    label: 'English',
    ttsLocale: 'en-US',
    speechLocale: 'en_US',
    greeting: 'Great, we will talk in English. Ask me any health question, send a voice message, '
        'or upload a medical report and I will explain it in simple words.',
    hint: 'Ask a health question…',
    listening: 'Listening… speak now',
    reportReading: 'Reading your report… this can take a few seconds.',
    checkIntro: 'Let me check your symptoms. A few quick questions:',
    describeSymptoms: 'Tell me what you are feeling, in your own words.',
  ),
  ChatLanguage(
    code: 'ur',
    label: 'اردو',
    ttsLocale: 'ur-PK',
    speechLocale: 'ur_PK',
    greeting: 'ٹھیک ہے، ہم اردو میں بات کریں گے۔ صحت سے متعلق کوئی بھی سوال پوچھیں، آواز میں پیغام بھیجیں، '
        'یا اپنی میڈیکل رپورٹ اپ لوڈ کریں، میں آسان الفاظ میں سمجھاؤں گا۔',
    hint: 'صحت کا سوال لکھیں…',
    listening: 'سن رہا ہوں… بولیں',
    reportReading: 'آپ کی رپورٹ پڑھ رہا ہوں… چند سیکنڈ لگ سکتے ہیں۔',
    checkIntro: 'آپ کی علامات کو بہتر سمجھنے کے لیے چند سوال:',
    describeSymptoms: 'اپنے الفاظ میں بتائیں کہ آپ کیا محسوس کر رہے ہیں۔',
    rtl: true,
  ),
  ChatLanguage(
    code: 'roman_ur',
    label: 'Roman Urdu',
    // Roman Urdu is written in English letters, so an English (India) voice reads it best.
    ttsLocale: 'en-IN',
    speechLocale: 'ur_PK',
    greeting: 'Theek hai, hum Roman Urdu mein baat karein ge. Sehat ka koi bhi sawal poochein, '
        'voice message bhejein, ya apni medical report upload karein, main asaan alfaaz mein samjhaun ga.',
    hint: 'Sehat ka sawal likhein…',
    listening: 'Sun raha hoon… bolein',
    reportReading: 'Aap ki report parh raha hoon… kuch second lag sakte hain.',
    checkIntro: 'Aap ki alamaat behtar samajhne ke liye chand sawal:',
    describeSymptoms: 'Apne alfaaz mein batayein aap kya mehsoos kar rahe hain.',
  ),
];
