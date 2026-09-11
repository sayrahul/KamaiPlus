/// GST utility helper for KamaiPlus Native Android
/// Provides Indian State Code mappings, statutory GST tax slab calculations,
/// and Indian Currency (INR) Number-to-Words conversion.
class GstHelper {
  static const Map<String, String> stateCodes = {
    '01': 'Jammu & Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chhattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '26': 'Dadra and Nagar Haveli and Daman and Diu',
    '27': 'Maharashtra',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman and Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
    '97': 'Other Territory',
  };

  /// Extracts state description from 15-digit GSTIN (e.g. "27 - Maharashtra")
  static String getStateFromGstin(String? gstin) {
    if (gstin == null || gstin.trim().length < 2) return '';
    final code = gstin.trim().substring(0, 2);
    final stateName = stateCodes[code];
    if (stateName != null) {
      return '$code ($stateName)';
    }
    return code;
  }

  /// Converts integer paise amount to statutory Indian Currency words format
  /// Example: 1499000 -> "Indian Rupees Fourteen Thousand Nine Hundred Ninety Only."
  static String numberToWordsINR(int paise) {
    if (paise <= 0) return 'Zero Rupees Only.';
    final rupees = paise ~/ 100;
    final remainingPaise = paise % 100;

    String words = _convertRupees(rupees);
    if (words.trim().isEmpty) {
      words = 'Zero';
    }

    String result = 'Indian Rupees $words';
    if (remainingPaise > 0) {
      result += ' and ${_convertTens(remainingPaise)} Paise';
    }
    return '$result Only.';
  }

  static String _convertRupees(int n) {
    if (n == 0) return '';

    if (n >= 10000000) {
      return '${_convertRupees(n ~/ 10000000)} Crore ${_convertRupees(n % 10000000)}'.trim();
    }
    if (n >= 100000) {
      return '${_convertRupees(n ~/ 100000)} Lakh ${_convertRupees(n % 100000)}'.trim();
    }
    if (n >= 1000) {
      return '${_convertRupees(n ~/ 1000)} Thousand ${_convertRupees(n % 1000)}'.trim();
    }
    if (n >= 100) {
      return '${_convertRupees(n ~/ 100)} Hundred ${_convertRupees(n % 100)}'.trim();
    }
    return _convertTens(n);
  }

  static String _convertTens(int n) {
    const units = [
      '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
      'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
      'Seventeen', 'Eighteen', 'Nineteen'
    ];
    const tens = [
      '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
    ];

    if (n < 20) return units[n];
    return '${tens[n ~/ 10]} ${units[n % 10]}'.trim();
  }
}
