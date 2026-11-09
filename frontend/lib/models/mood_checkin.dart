import 'package:flutter/material.dart';

/// Moods for the MindEase-style check-in, with our own affirmation and tips in three languages.
class CheckInMood {
  const CheckInMood({
    required this.key,
    required this.emoji,
    required this.label,
    required this.score,
    required this.color,
    required this.affirmation,
    required this.tips,
    required this.opener,
  });

  final String key;
  final String emoji;
  final Map<String, String> label; // en / ur / roman_ur
  final int score; // saved to the mood tracker: 1 (very low) … 5 (very good)
  final Color color;
  final Map<String, String> affirmation;
  final Map<String, List<String>> tips;

  /// First message sent to the companion when the user chooses "Talk about it".
  final Map<String, String> opener;

  String t(Map<String, String> m, String lang) => m[lang] ?? m['en']!;
}

const checkInMoods = [
  CheckInMood(
    key: 'happy',
    emoji: '😊',
    score: 5,
    color: Color(0xFF16A34A),
    label: {'en': 'Happy', 'ur': 'خوش', 'roman_ur': 'Khush'},
    affirmation: {
      'en': 'It is good to notice the bright moments. Let yourself enjoy this one fully.',
      'ur': 'خوشی کے لمحوں کو محسوس کرنا اچھا ہے۔ اس لمحے کا پورا لطف اٹھائیں۔',
      'roman_ur': 'Khushi ke lamhon ko mehsoos karna acha hai. Is lamhe ka poora lutf uthayein.',
    },
    tips: {
      'en': ['Write down one thing that made today good', 'Share the good news with someone close', 'Save a little of this energy for tomorrow'],
      'ur': ['آج کی ایک اچھی بات لکھ لیں', 'یہ خوشی کسی قریبی سے بانٹیں', 'کچھ توانائی کل کے لیے بھی بچا رکھیں'],
      'roman_ur': ['Aaj ki aik achi baat likh lein', 'Yeh khushi kisi qareebi se baantein', 'Kuch energy kal ke liye bhi bacha rakhein'],
    },
    opener: {'en': 'I feel happy today.', 'ur': 'میں آج خوش ہوں۔', 'roman_ur': 'Main aaj khush hoon.'},
  ),
  CheckInMood(
    key: 'calm',
    emoji: '😌',
    score: 4,
    color: Color(0xFF14B8A6),
    label: {'en': 'Calm', 'ur': 'پرسکون', 'roman_ur': 'Pursukoon'},
    affirmation: {
      'en': 'Calm is a strength. You can return to this feeling whenever you need it.',
      'ur': 'سکون ایک طاقت ہے۔ جب ضرورت ہو آپ اس احساس کی طرف لوٹ سکتے ہیں۔',
      'roman_ur': 'Sukoon aik taqat hai. Jab zaroorat ho aap is ehsaas ki taraf laut sakte hain.',
    },
    tips: {
      'en': ['Notice what helped you feel calm today', 'Take a slow walk or sit outside for a while', 'Plan one small kind thing for yourself'],
      'ur': ['دیکھیں آج کس چیز نے سکون دیا', 'آہستہ چہل قدمی کریں یا کچھ دیر باہر بیٹھیں', 'اپنے لیے ایک چھوٹا اچھا کام سوچیں'],
      'roman_ur': ['Dekhein aaj kis cheez ne sukoon diya', 'Aahista chehal qadmi karein ya kuch der bahar baithein', 'Apne liye aik chhota acha kaam sochein'],
    },
    opener: {'en': 'I feel calm right now.', 'ur': 'میں ابھی پرسکون ہوں۔', 'roman_ur': 'Main abhi pursukoon hoon.'},
  ),
  CheckInMood(
    key: 'okay',
    emoji: '🙂',
    score: 3,
    color: Color(0xFF3B82C4),
    label: {'en': 'Okay', 'ur': 'ٹھیک', 'roman_ur': 'Theek'},
    affirmation: {
      'en': 'Not every day has to be great. Okay is a perfectly fine place to be.',
      'ur': 'ہر دن بہترین ہونا ضروری نہیں۔ ٹھیک ہونا بھی بالکل اچھا ہے۔',
      'roman_ur': 'Har din behtareen hona zaroori nahi. Theek hona bhi bilkul acha hai.',
    },
    tips: {
      'en': ['Drink a glass of water and stretch', 'Pick one small task and finish it', 'Message a friend you have not talked to'],
      'ur': ['ایک گلاس پانی پئیں اور جسم کو کھینچیں', 'ایک چھوٹا کام چن کر مکمل کریں', 'کسی دوست کو پیغام بھیجیں'],
      'roman_ur': ['Aik glass pani piyein aur stretch karein', 'Aik chhota kaam chun kar mukammal karein', 'Kisi dost ko message bhejein'],
    },
    opener: {'en': 'I feel okay today.', 'ur': 'میں آج ٹھیک ہوں۔', 'roman_ur': 'Main aaj theek hoon.'},
  ),
  CheckInMood(
    key: 'tired',
    emoji: '😴',
    score: 3,
    color: Color(0xFF64748B),
    label: {'en': 'Tired', 'ur': 'تھکا ہوا', 'roman_ur': 'Thaka hua'},
    affirmation: {
      'en': 'Your body and mind are asking for rest. Resting is not lazy; it is how you recharge.',
      'ur': 'آپ کا جسم اور ذہن آرام مانگ رہے ہیں۔ آرام سستی نہیں، دوبارہ توانائی پانے کا طریقہ ہے۔',
      'roman_ur': 'Aap ka jism aur zehan aaraam maang rahe hain. Aaraam susti nahi, dobara energy paane ka tareeqa hai.',
    },
    tips: {
      'en': ['Take a 15-minute break away from screens', 'Try to sleep at the same time tonight', 'Eat something simple and drink water'],
      'ur': ['15 منٹ اسکرین سے دور وقفہ لیں', 'آج رات ایک ہی وقت پر سونے کی کوشش کریں', 'کچھ ہلکا کھائیں اور پانی پئیں'],
      'roman_ur': ['15 minute screen se door break lein', 'Aaj raat aik hi waqt par sone ki koshish karein', 'Kuch halka khayein aur pani piyein'],
    },
    opener: {'en': 'I feel really tired.', 'ur': 'میں بہت تھکا ہوا محسوس کر رہا ہوں۔', 'roman_ur': 'Main bohat thaka hua mehsoos kar raha hoon.'},
  ),
  CheckInMood(
    key: 'stressed',
    emoji: '😣',
    score: 2,
    color: Color(0xFFE29A2D),
    label: {'en': 'Stressed', 'ur': 'دباؤ میں', 'roman_ur': 'Stress mein'},
    affirmation: {
      'en': 'You are carrying a lot right now. You do not have to solve everything at once.',
      'ur': 'آپ اس وقت بہت کچھ اٹھائے ہوئے ہیں۔ سب کچھ ایک ساتھ حل کرنا ضروری نہیں۔',
      'roman_ur': 'Aap is waqt bohat kuch uthaye hue hain. Sab kuch aik saath hal karna zaroori nahi.',
    },
    tips: {
      'en': ['Breathe in for 4, hold for 4, out for 6 — five times', 'Write your worries down, then pick just one to act on', 'Step away for a few minutes, then come back'],
      'ur': ['4 تک سانس لیں، 4 تک روکیں، 6 تک چھوڑیں — پانچ بار', 'پریشانیاں لکھیں اور صرف ایک پر کام شروع کریں', 'چند منٹ کے لیے ہٹ جائیں پھر واپس آئیں'],
      'roman_ur': ['4 tak saans lein, 4 tak rokein, 6 tak chhorein — paanch baar', 'Pareshaniyan likhein aur sirf aik par kaam shuru karein', 'Chand minute ke liye hat jayein phir wapas aayein'],
    },
    opener: {'en': 'I feel stressed.', 'ur': 'میں دباؤ میں ہوں۔', 'roman_ur': 'Main stress mein hoon.'},
  ),
  CheckInMood(
    key: 'anxious',
    emoji: '😟',
    score: 2,
    color: Color(0xFF7C6BD9),
    label: {'en': 'Anxious', 'ur': 'گھبراہٹ', 'roman_ur': 'Ghabrahat'},
    affirmation: {
      'en': 'Anxious feelings are uncomfortable, but they pass. You are safe in this moment.',
      'ur': 'گھبراہٹ تکلیف دہ ہوتی ہے لیکن گزر جاتی ہے۔ اس لمحے آپ محفوظ ہیں۔',
      'roman_ur': 'Ghabrahat takleef deh hoti hai lekin guzar jati hai. Is lamhe aap mehfooz hain.',
    },
    tips: {
      'en': ['Name 5 things you can see and 4 you can hear', 'Put your feet flat on the floor and breathe slowly', 'Try the guided breathing exercise in the app'],
      'ur': ['5 چیزیں جو دیکھ سکتے ہیں اور 4 جو سن سکتے ہیں، ان کا نام لیں', 'پاؤں زمین پر رکھیں اور آہستہ سانس لیں', 'ایپ میں سانس کی مشق آزمائیں'],
      'roman_ur': ['5 cheezein jo dekh sakte hain aur 4 jo sun sakte hain, unka naam lein', 'Paon zameen par rakhein aur aahista saans lein', 'App mein saans ki mashq aazmayein'],
    },
    opener: {'en': 'I feel anxious.', 'ur': 'مجھے گھبراہٹ ہو رہی ہے۔', 'roman_ur': 'Mujhe ghabrahat ho rahi hai.'},
  ),
  CheckInMood(
    key: 'sad',
    emoji: '😢',
    score: 1,
    color: Color(0xFF3B82C4),
    label: {'en': 'Sad', 'ur': 'اداس', 'roman_ur': 'Udaas'},
    affirmation: {
      'en': 'It is okay to feel sad. Your feelings matter, and you do not have to carry them alone.',
      'ur': 'اداس ہونا ٹھیک ہے۔ آپ کے احساسات اہم ہیں اور آپ کو انہیں اکیلے نہیں اٹھانا۔',
      'roman_ur': 'Udaas hona theek hai. Aap ke ehsaasaat ahem hain aur aap ko inhein akelay nahi uthana.',
    },
    tips: {
      'en': ['Talk to someone you trust, even briefly', 'Get some daylight or fresh air', 'Be gentle with yourself today'],
      'ur': ['کسی بھروسے والے سے بات کریں، چاہے تھوڑی سی', 'کچھ دیر دھوپ یا تازہ ہوا میں جائیں', 'آج خود سے نرمی سے پیش آئیں'],
      'roman_ur': ['Kisi bharosay wale se baat karein, chahe thori si', 'Kuch der dhoop ya taaza hawa mein jayein', 'Aaj khud se narmi se pesh aayein'],
    },
    opener: {'en': 'I feel sad.', 'ur': 'میں اداس ہوں۔', 'roman_ur': 'Main udaas hoon.'},
  ),
  CheckInMood(
    key: 'lonely',
    emoji: '🥺',
    score: 1,
    color: Color(0xFF0F766E),
    label: {'en': 'Lonely', 'ur': 'تنہا', 'roman_ur': 'Tanha'},
    affirmation: {
      'en': 'Feeling lonely does not mean you are alone in this. Reaching out is a brave first step.',
      'ur': 'تنہائی محسوس کرنے کا مطلب یہ نہیں کہ آپ اکیلے ہیں۔ کسی سے رابطہ کرنا ایک بہادر قدم ہے۔',
      'roman_ur': 'Tanhai mehsoos karne ka matlab yeh nahi ke aap akelay hain. Kisi se rabta karna aik bahadur qadam hai.',
    },
    tips: {
      'en': ['Send a short message to someone you miss', 'Spend time in a shared space — a park or a café', 'Tell me about your day — I am here to listen'],
      'ur': ['کسی ایسے شخص کو مختصر پیغام بھیجیں جسے آپ یاد کرتے ہیں', 'کسی عام جگہ جیسے پارک میں کچھ وقت گزاریں', 'مجھے اپنے دن کے بارے میں بتائیں — میں سن رہا ہوں'],
      'roman_ur': ['Kisi aisay shakhs ko mukhtasar message bhejein jise aap yaad karte hain', 'Kisi aam jagah jaise park mein kuch waqt guzarein', 'Mujhe apne din ke baare mein batayein — main sun raha hoon'],
    },
    opener: {'en': 'I feel lonely.', 'ur': 'میں تنہا محسوس کر رہا ہوں۔', 'roman_ur': 'Main tanha mehsoos kar raha hoon.'},
  ),
];
