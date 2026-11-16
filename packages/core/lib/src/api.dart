import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'format.dart';

typedef Json = Map<String, dynamic>;

/// Thin wrapper over the Supabase tables, views and RPCs (see supabase/migrations).
/// Json-level security decides what each login can see, so the same calls work
/// for both the owner and the tenant app.
class KirayaApi {
  KirayaApi([SupabaseClient? client]) : _sb = client ?? Supabase.instance.client;
  final SupabaseClient _sb;

  static final instance = KirayaApi();

  List<Json> _rows(dynamic v) => (v as List).cast<Json>();
  Future<T> _rpc<T>(String fn, [Map<String, dynamic>? params]) async => await _sb.rpc(fn, params: params) as T;

  // ---------------- reads ----------------
  Future<List<Json>> roomBoard() async => _rows(await _sb.from('v_room_board').select().order('number'));

  Future<List<Json>> tenancySummaries({bool liveOnly = true}) async {
    var q = _sb.from('v_tenancy_summary').select();
    if (liveOnly) q = q.inFilter('status', ['ACTIVE', 'ON_NOTICE']);
    return _rows(await q.order('room_number'));
  }

  Future<Json?> tenancySummary(String tenancyId) async =>
      await _sb.from('v_tenancy_summary').select().eq('tenancy_id', tenancyId).maybeSingle();

  Future<Json> tenancy(String id) async => await _sb.from('tenancy').select('*, room(number)').eq('id', id).single();

  Future<List<Json>> occupants(String tenancyId) async =>
      _rows(await _sb.from('occupant').select('*, tenant(*)').eq('tenancy_id', tenancyId).order('is_primary', ascending: false));

  Future<Json> tenant(String id) async => await _sb.from('tenant').select().eq('id', id).single();

  Future<List<Json>> bills(String tenancyId) async => _rows(await _sb
      .from('bill')
      .select('*, bill_line(*)')
      .eq('tenancy_id', tenancyId)
      .order('cycle_start', ascending: false));

  Future<List<Json>> draftBills() async => _rows(await _sb
      .from('bill')
      .select('*, bill_line(*), tenancy(room(number))')
      .eq('status', 'DRAFT')
      .order('bill_date'));

  Future<List<Json>> ledger(String tenancyId) async => _rows(await _sb
      .from('ledger_entry')
      .select()
      .eq('tenancy_id', tenancyId)
      .order('entry_date')
      .order('id'));

  Future<List<Json>> payments(String tenancyId) async => _rows(await _sb
      .from('payment')
      .select('*, payment_split(*)')
      .eq('tenancy_id', tenancyId)
      .order('paid_on', ascending: false));

  Future<List<Json>> pendingClaims() async => _rows(await _sb
      .from('payment')
      .select('*, payment_split(*), tenancy(room(number))')
      .eq('status', 'PENDING_CONFIRM')
      .order('created_at'));

  Future<List<Json>> charges(String tenancyId) async =>
      _rows(await _sb.from('charge').select().eq('tenancy_id', tenancyId).order('start_date'));

  Future<List<Json>> advance(String tenancyId) async =>
      _rows(await _sb.from('advance').select().eq('tenancy_id', tenancyId).order('txn_date'));

  Future<List<Json>> complaints({bool openOnly = false}) async {
    var q = _sb.from('complaint').select('*, room(number)');
    if (openOnly) q = q.neq('status', 'RESOLVED');
    return _rows(await q.order('created_at', ascending: false));
  }

  Future<List<Json>> notices() async =>
      _rows(await _sb.from('notice').select('*, room(number)').order('created_at', ascending: false).limit(50));

  Future<List<Json>> rooms() async => _rows(await _sb.from('room').select().order('number'));

  Future<List<Json>> monthlyCollection() async =>
      _rows(await _sb.from('v_monthly_collection').select().order('month', ascending: false).limit(60));

  Future<List<Json>> logins() async => _rows(await _sb.from('app_user').select().order('role').order('name'));

  Future<List<Json>> kycDocs(String tenantId) async =>
      _rows(await _sb.from('kyc_document').select().eq('tenant_id', tenantId).order('created_at'));

  Future<Json?> settlement(String tenancyId) async =>
      await _sb.from('settlement').select().eq('tenancy_id', tenancyId).maybeSingle();

  /// Latest active (not withdrawn) leaving notice, if any.
  Future<Json?> activeNotice(String tenancyId) async => await _sb
      .from('notice_to_vacate')
      .select()
      .eq('tenancy_id', tenancyId)
      .eq('withdrawn', false)
      .order('created_at', ascending: false)
      .limit(1)
      .maybeSingle();

  Future<Map<String, dynamic>> settings() async => Map<String, dynamic>.from(await _rpc('current_settings') as Map);

  // ---------------- bills ----------------
  Future<int> generateDueBills([DateTime? asOf]) =>
      _rpc<int>('generate_due_bills', {'p_as_of': asOf == null ? null : isoDate(asOf)});
  Future<void> issueBill(String billId) => _rpc('issue_bill', {'p_bill': billId});
  Future<int> issueAllDrafts() => _rpc<int>('issue_all_drafts');
  Future<void> addBillLine(String billId, String label, num amount) =>
      _rpc('add_bill_line', {'p_bill': billId, 'p_label': label, 'p_amount': amount});
  Future<void> removeBillLine(String lineId) => _rpc('remove_bill_line', {'p_line': lineId});
  Future<void> discardDraft(String billId) => _rpc('discard_draft_bill', {'p_bill': billId});

  // ---------------- meter ----------------
  /// items: [{room_id, value, note?}]
  Future<int> addReadings(DateTime date, List<Json> items, {String kind = 'MONTHLY', bool force = false}) =>
      _rpc<int>('add_readings', {'p_date': isoDate(date), 'p_items': items, 'p_kind': kind, 'p_force': force});

  // ---------------- tenancy ----------------
  Future<String> onboard(Json payload) => _rpc<String>('onboard_tenant', {'p': payload});
  Future<String> addOccupant(String tenancyId, Json person, [DateTime? joined]) => _rpc<String>('add_occupant',
      {'p_tenancy': tenancyId, 'p_person': person, 'p_joined': joined == null ? null : isoDate(joined)});
  Future<void> removeOccupant(String tenancyId, String tenantId, [DateTime? left]) => _rpc('remove_occupant',
      {'p_tenancy': tenancyId, 'p_tenant': tenantId, 'p_left': left == null ? null : isoDate(left)});
  Future<String> addCharge(String tenancyId, String label, num amount,
          {String kind = 'ONE_OFF', DateTime? start, DateTime? end}) =>
      _rpc<String>('add_charge', {
        'p_tenancy': tenancyId,
        'p_label': label,
        'p_amount': amount,
        'p_kind': kind,
        'p_start': start == null ? null : isoDate(start),
        'p_end': end == null ? null : isoDate(end),
      });
  Future<void> stopCharge(String chargeId, [DateTime? end]) =>
      _rpc('stop_charge', {'p_charge': chargeId, 'p_end': end == null ? null : isoDate(end)});
  Future<void> adjust(String tenancyId, num amount, String reason, [DateTime? date]) => _rpc('adjust', {
        'p_tenancy': tenancyId,
        'p_amount': amount,
        'p_reason': reason,
        'p_date': date == null ? null : isoDate(date),
      });
  Future<void> updateTenancy(String id, Json values) => _sb.from('tenancy').update(values).eq('id', id);
  Future<void> updateTenant(String id, Json values) => _sb.from('tenant').update(values).eq('id', id);
  Future<void> updateRoom(String id, Json values) => _sb.from('room').update(values).eq('id', id);
  Future<void> addRoom(Json values) => _sb.from('room').insert(values);
  Future<void> setAppAccess(String tenancyId, String tenantId, bool access) =>
      _rpc('set_app_access', {'p_tenancy': tenancyId, 'p_tenant': tenantId, 'p_access': access});

  // ---------------- payments ----------------
  /// splits: [{mode: CASH|PHONEPE|GPAY|UPI_OTHER|BANK, amount, ref?}]
  Future<String> recordPayment(String tenancyId, DateTime paidOn, List<Json> splits,
          {String? note, String? idempotencyKey}) =>
      _rpc<String>('record_payment', {
        'p_tenancy': tenancyId,
        'p_paid_on': isoDate(paidOn),
        'p_splits': splits,
        'p_note': note,
        'p_idempotency_key': idempotencyKey,
      });
  Future<String> claimPayment(String tenancyId, DateTime paidOn, num amount, String mode,
          {String? ref, String? note, String? proofPath, String? idempotencyKey}) =>
      _rpc<String>('claim_payment', {
        'p_tenancy': tenancyId,
        'p_paid_on': isoDate(paidOn),
        'p_amount': amount,
        'p_mode': mode,
        'p_ref': ref,
        'p_note': note,
        'p_proof_path': proofPath,
        'p_idempotency_key': idempotencyKey,
      });
  Future<void> confirmPayment(String paymentId, bool approve, [String? reason]) =>
      _rpc('confirm_payment', {'p_payment': paymentId, 'p_approve': approve, 'p_reason': reason});
  Future<void> voidPayment(String paymentId, [String reason = 'Cancelled']) =>
      _rpc('void_payment', {'p_payment': paymentId, 'p_reason': reason});

  // ---------------- notice / move-out / shift ----------------
  Future<Json> giveNotice(String tenancyId, DateTime leaveOn, {DateTime? givenOn, String? note}) async =>
      Json.from(await _rpc('give_notice', {
        'p_tenancy': tenancyId,
        'p_leave_on': isoDate(leaveOn),
        'p_given_on': givenOn == null ? null : isoDate(givenOn),
        'p_note': note,
      }) as Map);
  Future<void> withdrawNotice(String tenancyId) => _rpc('withdraw_notice', {'p_tenancy': tenancyId});
  Future<Json> settleMoveOut(String tenancyId, DateTime leaveDate,
          {num? finalReading,
          num noticeShortfall = 0,
          num? cleaning,
          List<Json> extra = const [],
          bool absconded = false,
          bool writeOffRest = false,
          String? note}) async =>
      Json.from(await _rpc('settle_move_out', {
        'p_tenancy': tenancyId,
        'p_leave_date': isoDate(leaveDate),
        'p_final_reading': finalReading,
        'p_notice_shortfall': noticeShortfall,
        'p_cleaning': cleaning,
        'p_extra': extra,
        'p_absconded': absconded,
        'p_write_off_rest': writeOffRest,
        'p_note': note,
      }) as Map);
  Future<String> shiftRoom(String tenancyId, String newRoomId, DateTime date,
          {num? oldReading, num? newReading, num? newRent}) =>
      _rpc<String>('shift_room', {
        'p_tenancy': tenancyId,
        'p_new_room': newRoomId,
        'p_shift_date': isoDate(date),
        'p_old_room_reading': oldReading,
        'p_new_room_reading': newReading,
        'p_new_rent': newRent,
      });

  // ---------------- settings & misc ----------------
  Future<void> updateSetting(String key, Object? value, [DateTime? from]) => _rpc('update_setting',
      {'p_key': key, 'p_value': value, 'p_effective_from': from == null ? null : isoDate(from)});
  Future<void> setMyLanguage(String lang) => _rpc('set_my_language', {'p_lang': lang});
  Future<int> importHistory(String tenancyId, List<Json> entries) =>
      _rpc<int>('import_history', {'p_tenancy': tenancyId, 'p_entries': entries});

  Future<void> addComplaint(Json values) => _sb.from('complaint').insert(values);
  Future<void> updateComplaint(String id, Json values) => _sb.from('complaint').update(values).eq('id', id);
  Future<void> addNotice(Json values) => _sb.from('notice').insert(values);
  Future<void> deleteNotice(String id) => _sb.from('notice').delete().eq('id', id);
  Future<void> addKycDoc(String tenantId, String kind, String path) =>
      _sb.from('kyc_document').insert({'tenant_id': tenantId, 'kind': kind, 'storage_path': path});

  // ---------------- files (private bucket) ----------------
  Future<String> upload(String path, Uint8List bytes, {String contentType = 'image/jpeg'}) async {
    await _sb.storage
        .from('private')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: true));
    return path;
  }

  Future<String> signedUrl(String path) => _sb.storage.from('private').createSignedUrl(path, 3600);

  // ---------------- logins (edge function) ----------------
  Future<Json> manageLogin(Json body) async {
    final res = await _sb.functions.invoke('manage-login', body: body);
    final data = res.data is Map ? Json.from(res.data as Map) : <String, dynamic>{};
    if (data['error'] != null) throw Exception(data['error']);
    return data;
  }
}

/// Short, human message from any exception (DB "raise exception" texts are already plain English).
String friendlyError(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) {
    return e.message.toLowerCase().contains('invalid') ? 'Wrong phone number or PIN' : e.message;
  }
  if (e is FunctionException) return (e.details is Map ? (e.details as Map)['error'] : null)?.toString() ?? e.toString();
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('ClientException')) return 'No internet. Please try again.';
  return s.replaceFirst('Exception: ', '');
}
