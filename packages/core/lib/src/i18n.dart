import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App language. English by default, Hindi optional.
/// Hindi uses everyday spoken words (पेमेंट, बिल, रूम) rather than formal/literary Hindi.
class Lang extends ChangeNotifier {
  Lang._();
  static final instance = Lang._();
  static const _prefKey = 'lang';

  String _code = 'en';
  String get code => _code;
  bool get isHindi => _code == 'hi';

  final Map<String, Map<String, String>> _strings = {'en': {..._en}, 'hi': {..._hi}};

  /// Apps add their own screen strings on top of the shared ones.
  void register(Map<String, String> en, Map<String, String> hi) {
    _strings['en']!.addAll(en);
    _strings['hi']!.addAll(hi);
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _code = p.getString(_prefKey) ?? 'en';
  }

  Future<void> set(String code) async {
    if (code != 'en' && code != 'hi') return;
    _code = code;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefKey, code);
  }

  /// Keys present in English but missing in Hindi (used by tests).
  Iterable<String> missingHindi() => _strings['en']!.keys.where((k) => !_strings['hi']!.containsKey(k));

  Iterable<String> allKeys() => _strings['en']!.keys;
  String? raw(String lang, String key) => _strings[lang]?[key];

  String t(String key, [Map<String, Object?> args = const {}]) {
    var s = _strings[_code]![key] ?? _strings['en']![key] ?? key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
    return s;
  }
}

/// Translate: tr('save'), tr('room_n', {'n': '101'}).
String tr(String key, [Map<String, Object?> args = const {}]) => Lang.instance.t(key, args);

const _en = <String, String>{
  'app_owner': 'Kiraya Owner',
  'app_tenant': 'Kiraya',
  'ok': 'OK',
  'cancel': 'Cancel',
  'save': 'Save',
  'done': 'Done',
  'yes': 'Yes',
  'no': 'No',
  'undo': 'Undo',
  'retry': 'Try again',
  'next': 'Next',
  'back': 'Back',
  'add': 'Add',
  'edit': 'Edit',
  'delete': 'Delete',
  'remove': 'Remove',
  'close': 'Close',
  'search': 'Search',
  'loading': 'Loading…',
  'nothing_here': 'Nothing here yet',
  'saved': 'Saved',
  'are_you_sure': 'Are you sure?',
  'error': 'Something went wrong',
  'required': 'Please fill this',
  'invalid_number': 'Enter a valid number',
  'language': 'Language',
  'english': 'English',
  'hindi': 'हिंदी',
  'logout': 'Log out',
  'login': 'Log in',
  'phone': 'Mobile number',
  'pin': '6-digit PIN',
  'pin_hint': 'Ask the owner if you forgot it',
  'wrong_login': 'Wrong mobile number or PIN',
  'not_configured': 'App is not set up yet. Build it with SUPABASE_URL and SUPABASE_ANON_KEY.',
  'no_access': 'This login cannot use this app',
  'update_available': 'New version {v} is available',
  'update_now': 'Update',
  'later': 'Later',
  // money & words
  'rent': 'Rent',
  'electricity': 'Electricity',
  'units': 'Units',
  'rate': 'Rate',
  'amount': 'Amount',
  'total': 'Total',
  'balance': 'Balance',
  'due': 'Due',
  'to_pay': 'To pay',
  'extra_paid': 'Paid extra',
  'all_clear': 'All paid',
  'advance': 'Advance',
  'date': 'Date',
  'note': 'Note',
  'room': 'Room',
  'room_n': 'Room {n}',
  'from_to': '{a} to {b}',
  'bill': 'Bill',
  'bills': 'Bills',
  'bill_no': 'Bill #{n}',
  'due_on': 'Pay by {d}',
  'ledger': 'Hisaab',
  'payments': 'Payments',
  'payment': 'Payment',
  'paid': 'Paid',
  'partly_paid': 'Part paid',
  'unpaid': 'Not paid',
  'draft': 'Draft',
  'pending': 'Waiting',
  'rejected': 'Rejected',
  'cancelled': 'Cancelled',
  'received': 'Received',
  'complaints': 'Complaints',
  'complaint': 'Complaint',
  'notices': 'Notices',
  'reading': 'Meter reading',
  'previous_reading': 'Last reading',
  'settings': 'Settings',
  'home': 'Home',
  'more': 'More',
  'mode_CASH': 'Cash',
  'mode_PHONEPE': 'PhonePe',
  'mode_GPAY': 'GPay',
  'mode_UPI_OTHER': 'Other UPI',
  'mode_BANK': 'Bank',
  'kind_OPENING': 'Old balance',
  'kind_BILL': 'Bill',
  'kind_PAYMENT': 'Paid',
  'kind_PAYMENT_VOID': 'Payment cancelled',
  'kind_ADJUSTMENT': 'Adjustment',
  'kind_ADVANCE_ADJ': 'From advance',
  'kind_REFUND': 'Refund',
  'kind_WRITE_OFF': 'Waived',
  'kind_TRANSFER': 'Moved from other room',
  'line_RENT': 'Rent',
  'line_ELECTRICITY': 'Electricity',
  'line_CHARGE': 'Charge',
  'line_LATE_FEE': 'Late fee',
  'line_CLEANING': 'Cleaning',
  'line_NOTICE_SHORTFALL': 'Short notice',
  'line_OTHER': 'Other',
  'cstatus_OPEN': 'Open',
  'cstatus_IN_PROGRESS': 'Working on it',
  'cstatus_RESOLVED': 'Fixed',
  'cat_WATER': 'Water',
  'cat_LIGHT': 'Light / Power',
  'cat_CLEANING': 'Cleaning',
  'cat_REPAIR': 'Repair',
  'cat_OTHER': 'Other',
  'tstatus_ACTIVE': 'Staying',
  'tstatus_ON_NOTICE': 'Leaving',
  'tstatus_CLOSED': 'Left',
  'tstatus_ABSCONDED': 'Left without paying',
  'tstatus_SHIFTED': 'Shifted room',
  'leaving_on': 'Leaving on {d}',
  'debit': 'Added',
  'credit': 'Paid / less',
};

const _hi = <String, String>{
  'app_owner': 'किराया मालिक',
  'app_tenant': 'किराया',
  'ok': 'ठीक है',
  'cancel': 'रहने दो',
  'save': 'सेव करें',
  'done': 'हो गया',
  'yes': 'हाँ',
  'no': 'नहीं',
  'undo': 'वापस लो',
  'retry': 'फिर से कोशिश करें',
  'next': 'आगे',
  'back': 'पीछे',
  'add': 'जोड़ें',
  'edit': 'बदलें',
  'delete': 'हटाएँ',
  'remove': 'हटाएँ',
  'close': 'बंद करें',
  'search': 'खोजें',
  'loading': 'लोड हो रहा है…',
  'nothing_here': 'अभी कुछ नहीं है',
  'saved': 'सेव हो गया',
  'are_you_sure': 'पक्का?',
  'error': 'कुछ गड़बड़ हो गई',
  'required': 'यह भरना ज़रूरी है',
  'invalid_number': 'सही नंबर डालें',
  'language': 'भाषा',
  'english': 'English',
  'hindi': 'हिंदी',
  'logout': 'लॉग आउट',
  'login': 'लॉगिन करें',
  'phone': 'मोबाइल नंबर',
  'pin': '6 अंकों का पिन',
  'pin_hint': 'पिन भूल गए तो मालिक से पूछें',
  'wrong_login': 'मोबाइल नंबर या पिन गलत है',
  'not_configured': 'ऐप अभी सेट नहीं है।',
  'no_access': 'यह लॉगिन इस ऐप के लिए नहीं है',
  'update_available': 'नया वर्ज़न {v} आ गया है',
  'update_now': 'अपडेट करें',
  'later': 'बाद में',
  'rent': 'किराया',
  'electricity': 'बिजली',
  'units': 'यूनिट',
  'rate': 'रेट',
  'amount': 'रकम',
  'total': 'कुल',
  'balance': 'बाकी',
  'due': 'बाकी',
  'to_pay': 'देना है',
  'extra_paid': 'ज़्यादा दिया है',
  'all_clear': 'सब चुका दिया',
  'advance': 'एडवांस',
  'date': 'तारीख',
  'note': 'नोट',
  'room': 'रूम',
  'room_n': 'रूम {n}',
  'from_to': '{a} से {b}',
  'bill': 'बिल',
  'bills': 'बिल',
  'bill_no': 'बिल #{n}',
  'due_on': '{d} तक दें',
  'ledger': 'हिसाब',
  'payments': 'पेमेंट',
  'payment': 'पेमेंट',
  'paid': 'दे दिया',
  'partly_paid': 'थोड़ा दिया',
  'unpaid': 'नहीं दिया',
  'draft': 'कच्चा बिल',
  'pending': 'रुका है',
  'rejected': 'मना किया',
  'cancelled': 'कैंसल',
  'received': 'मिल गया',
  'complaints': 'शिकायत',
  'complaint': 'शिकायत',
  'notices': 'सूचना',
  'reading': 'मीटर रीडिंग',
  'previous_reading': 'पिछली रीडिंग',
  'settings': 'सेटिंग',
  'home': 'होम',
  'more': 'और',
  'mode_CASH': 'नकद',
  'mode_PHONEPE': 'PhonePe',
  'mode_GPAY': 'GPay',
  'mode_UPI_OTHER': 'दूसरा UPI',
  'mode_BANK': 'बैंक',
  'kind_OPENING': 'पुराना बाकी',
  'kind_BILL': 'बिल',
  'kind_PAYMENT': 'दिया',
  'kind_PAYMENT_VOID': 'पेमेंट कैंसल',
  'kind_ADJUSTMENT': 'हिसाब ठीक किया',
  'kind_ADVANCE_ADJ': 'एडवांस से काटा',
  'kind_REFUND': 'वापस दिया',
  'kind_WRITE_OFF': 'माफ़ किया',
  'kind_TRANSFER': 'दूसरे रूम से आया',
  'line_RENT': 'किराया',
  'line_ELECTRICITY': 'बिजली',
  'line_CHARGE': 'चार्ज',
  'line_LATE_FEE': 'देरी का चार्ज',
  'line_CLEANING': 'सफ़ाई',
  'line_NOTICE_SHORTFALL': 'नोटिस कम',
  'line_OTHER': 'अन्य',
  'cstatus_OPEN': 'खुली है',
  'cstatus_IN_PROGRESS': 'काम चल रहा है',
  'cstatus_RESOLVED': 'ठीक हो गया',
  'cat_WATER': 'पानी',
  'cat_LIGHT': 'लाइट / बिजली',
  'cat_CLEANING': 'सफ़ाई',
  'cat_REPAIR': 'रिपेयर',
  'cat_OTHER': 'अन्य',
  'tstatus_ACTIVE': 'रह रहे हैं',
  'tstatus_ON_NOTICE': 'जा रहे हैं',
  'tstatus_CLOSED': 'चले गए',
  'tstatus_ABSCONDED': 'बिना दिए चले गए',
  'tstatus_SHIFTED': 'रूम बदला',
  'leaving_on': '{d} को जा रहे हैं',
  'debit': 'जुड़ा',
  'credit': 'दिया / कम',
};
