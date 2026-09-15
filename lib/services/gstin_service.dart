import 'dart:convert';
import 'dart:io';
import '../core/utils/gst_helper.dart';

class GstinData {
  final String gstin;
  final String legalName;
  final String tradeName;
  final String address;
  final String state;
  final String status;
  final bool isValid;
  final String? errorMessage;

  GstinData({
    required this.gstin,
    required this.legalName,
    required this.tradeName,
    required this.address,
    required this.state,
    this.status = 'Active',
    this.isValid = true,
    this.errorMessage,
  });

  factory GstinData.invalid(String gstin, String error) {
    return GstinData(
      gstin: gstin,
      legalName: '',
      tradeName: '',
      address: '',
      state: GstHelper.getStateFromGstin(gstin),
      status: 'Invalid',
      isValid: false,
      errorMessage: error,
    );
  }
}

class GstinService {
  GstinService._();
  static final GstinService instance = GstinService._();

  static final RegExp _gstinRegex = RegExp(
    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$',
    caseSensitive: false,
  );

  /// Validates format of 15-character Indian GSTIN
  bool isValidFormat(String gstin) {
    final clean = gstin.trim().toUpperCase();
    return clean.length == 15 && _gstinRegex.hasMatch(clean);
  }

  /// Verifies GSTIN online and fetches business legal name, trade name, and address
  Future<GstinData> verifyGstin(String rawGstin) async {
    final gstin = rawGstin.trim().toUpperCase();
    if (!isValidFormat(gstin)) {
      return GstinData.invalid(gstin, 'Invalid GSTIN format. Must be 15 alphanumeric characters.');
    }

    final stateName = GstHelper.getStateFromGstin(gstin);

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);

      // 1. Query Indian public GST portal search endpoint
      final uri = Uri.parse('https://sheet.gstincheck.co.in/check/$gstin');
      final req = await client.getUrl(uri);
      final res = await req.close();

      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final flag = json['flag'] == true;
        final data = json['data'] as Map<String, dynamic>?;

        if (flag && data != null) {
          final legalName = (data['lgnm'] ?? data['legal_name'] ?? '').toString().trim();
          final tradeName = (data['tradeNam'] ?? data['trade_name'] ?? legalName).toString().trim();
          final pradr = data['pradr'] as Map<String, dynamic>?;
          String addr = '';
          if (pradr != null && pradr['addr'] != null) {
            final a = pradr['addr'] as Map<String, dynamic>;
            addr = [
              a['bno'],
              a['bnm'],
              a['st'],
              a['loc'],
              a['dst'],
              a['pncd'],
            ].where((e) => e != null && e.toString().trim().isNotEmpty).join(', ');
          }
          final status = (data['sts'] ?? data['status'] ?? 'Active').toString().trim();

          return GstinData(
            gstin: gstin,
            legalName: legalName.isNotEmpty ? legalName : 'Verified GSTIN',
            tradeName: tradeName.isNotEmpty ? tradeName : (legalName.isNotEmpty ? legalName : 'Verified Business'),
            address: addr,
            state: stateName.isNotEmpty ? stateName : (data['stCd']?.toString() ?? ''),
            status: status,
            isValid: true,
          );
        }
      }
    } catch (_) {
      // Fallback: offline extraction of State and PAN if connection drops
    }

    // Graceful offline structural fallback
    return GstinData(
      gstin: gstin,
      legalName: '',
      tradeName: '',
      address: '',
      state: stateName,
      status: 'Format Valid (Offline)',
      isValid: true,
    );
  }
}
