class AppValidators {
  /// Validates 10-digit Indian mobile number (TRAI standard, starts with 6, 7, 8, 9)
  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Mobile number required';
    }
    final clean = value.replaceAll(RegExp(r'[\s\-+()]'), '');
    final number = clean.startsWith('91') && clean.length == 12 ? clean.substring(2) : clean;
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(number)) {
      return 'Enter valid 10-digit mobile number (starts with 6-9)';
    }
    return null;
  }

  /// Cleans phone to standard 10 digits
  static String cleanPhone(String value) {
    final clean = value.replaceAll(RegExp(r'[\s\-+()]'), '');
    return clean.startsWith('91') && clean.length == 12 ? clean.substring(2) : clean;
  }

  /// Validates 4-digit or 6-digit OTP
  static String? validateOtp(String? value, {int length = 4}) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter OTP';
    }
    if (value.trim().length != length || !RegExp(r'^\d+$').hasMatch(value.trim())) {
      return 'Enter valid $length-digit OTP';
    }
    return null;
  }

  /// Validates Indian UPI VPA (e.g. 9876543210@paytm, store@okaxis)
  static String? validateUpi(String? value, {bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'UPI ID required for billing QR' : null;
    }
    if (!RegExp(r'^[a-zA-Z0-9.\-_]{2,64}@[a-zA-Z]{2,32}$').hasMatch(value.trim())) {
      return 'Enter valid UPI ID (e.g. name@paytm)';
    }
    return null;
  }

  /// Validates 15-character Indian GSTIN
  static String? validateGstin(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'GSTIN is required' : null;
    }
    final clean = value.trim().toUpperCase();
    if (!RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$').hasMatch(clean)) {
      return 'Invalid 15-digit GSTIN (e.g. 27AAAAA0000A1Z5)';
    }
    return null;
  }

  /// Validates 6-digit Indian PIN code
  static String? validatePincode(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Pincode is required' : null;
    }
    if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(value.trim())) {
      return 'Enter valid 6-digit Pincode';
    }
    return null;
  }

  /// Validates 14-digit FSSAI License number
  static String? validateFssai(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'FSSAI license required' : null;
    }
    if (!RegExp(r'^[0-9]{14}$').hasMatch(value.trim())) {
      return 'Enter valid 14-digit FSSAI number';
    }
    return null;
  }

  /// Validates Email address
  static String? validateEmail(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Email is required' : null;
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }
}
