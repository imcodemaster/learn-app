import 'json.dart';

class FaqItem {
  const FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;
}

/// Organisation details managed from the admin panel (Site settings).
class AppInfo {
  const AppInfo({
    required this.orgName,
    required this.tagline,
    required this.heroTitle,
    required this.about,
    required this.phone,
    required this.email,
    required this.address,
    required this.hours,
    required this.website,
    required this.youtube,
    required this.instagram,
    required this.linkedin,
    required this.privacyUrl,
    required this.termsUrl,
    required this.faq,
    required this.paymentsMode,
    required this.googleEnabled,
  });

  final String orgName;
  final String tagline;
  final String heroTitle;
  final String about;
  final String phone;
  final String email;
  final String address;
  final String hours;
  final String website;
  final String youtube;
  final String instagram;
  final String linkedin;
  final String privacyUrl;
  final String termsUrl;
  final List<FaqItem> faq;
  final String paymentsMode;
  final bool googleEnabled;

  /// Used until the server answers (or when offline).
  static const fallback = AppInfo(
    orgName: 'LearnInCreation',
    tagline: 'Learn Create & Innovate',
    heroTitle: 'Learn Coding, Build Your Future',
    about: '',
    phone: '+91 6395677914',
    email: 'thevinaybhatt@gmail.com',
    address: 'Rudrapur, Uttarakhand, India',
    hours: 'Mon–Sat, 10:00 AM – 6:00 PM',
    website: 'https://learnincreation.com',
    youtube: 'https://www.youtube.com/@LearnincreationIndia',
    instagram: 'https://www.instagram.com/learnincreation/',
    linkedin: 'https://www.linkedin.com/company/13744828/',
    privacyUrl: 'https://learnincreation.com/privacy.html',
    termsUrl: 'https://learnincreation.com/terms.html',
    faq: <FaqItem>[],
    paymentsMode: 'razorpay',
    googleEnabled: false,
  );

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    final social = jMap(json['social']);
    final payments = jMap(json['payments']);
    final auth = jMap(json['auth']);
    return AppInfo(
      orgName: jStr(json['org_name'], fallback.orgName),
      tagline: jStr(json['tagline'], fallback.tagline),
      heroTitle: jStr(json['hero_title'], fallback.heroTitle),
      about: jStr(json['about']),
      phone: jStr(json['phone']),
      email: jStr(json['email']),
      address: jStr(json['address']),
      hours: jStr(json['hours']),
      website: jStr(json['website']),
      youtube: jStr(social['youtube']),
      instagram: jStr(social['instagram']),
      linkedin: jStr(social['linkedin']),
      privacyUrl: jStr(json['privacy_url']),
      termsUrl: jStr(json['terms_url']),
      faq: jList(json['faq'])
          .map((item) => FaqItem(question: jStr(item['q']), answer: jStr(item['a'])))
          .toList(),
      paymentsMode: jStr(payments['mode'], 'razorpay'),
      googleEnabled: jBool(auth['google_enabled']),
    );
  }
}
