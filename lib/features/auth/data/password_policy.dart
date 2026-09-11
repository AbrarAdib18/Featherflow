/// Client-side mirror of the backend password rules so the signup form can
/// give feedback *as the user types* instead of only after they submit.
///
/// The backend is authoritative — Django's `AUTH_PASSWORD_VALIDATORS` in
/// `backend/featherflow_backend/settings.py`:
///   * `MinimumLengthValidator`        → at least 8 characters
///   * `NumericPasswordValidator`      → not entirely numeric
///   * `CommonPasswordValidator`       → not in the ~20k common-password list
///   * `UserAttributeSimilarityValidator` → not too similar to email / name / phone
///
/// These checks are kept **no stricter** than the server: a password the UI
/// marks valid must always pass `POST /api/auth/register/`. The optional
/// "add a number / symbol / mixed case" hints only feed the strength meter —
/// they never block submission, because the backend does not require them.
library;

/// Coarse strength buckets for the meter under the password field.
enum PasswordStrength { empty, weak, fair, good, strong }

extension PasswordStrengthInfo on PasswordStrength {
  String get label {
    switch (this) {
      case PasswordStrength.empty:
        return '';
      case PasswordStrength.weak:
        return 'Weak';
      case PasswordStrength.fair:
        return 'Fair';
      case PasswordStrength.good:
        return 'Good';
      case PasswordStrength.strong:
        return 'Strong';
    }
  }

  /// 0..1 fill fraction for the meter bar.
  double get fraction {
    switch (this) {
      case PasswordStrength.empty:
        return 0;
      case PasswordStrength.weak:
        return 0.25;
      case PasswordStrength.fair:
        return 0.5;
      case PasswordStrength.good:
        return 0.75;
      case PasswordStrength.strong:
        return 1;
    }
  }
}

/// Result of evaluating a candidate password.
class PasswordEvaluation {
  const PasswordEvaluation({
    required this.errors,
    required this.hints,
    required this.strength,
  });

  /// Blocking problems — must be empty for the password to be accepted.
  final List<String> errors;

  /// Non-blocking suggestions that would make the password stronger.
  final List<String> hints;

  final PasswordStrength strength;

  bool get isValid => errors.isEmpty;

  static const PasswordEvaluation empty = PasswordEvaluation(
    errors: <String>[],
    hints: <String>[],
    strength: PasswordStrength.empty,
  );
}

const int kMinPasswordLength = 8;

/// A trimmed copy of the most-hit entries in Django's `common-passwords.txt`,
/// plus a few keyboard walks. Matched case-insensitively, and also against the
/// password with trailing digits stripped ("password123" → "password").
const Set<String> _commonPasswords = <String>{
  'password', 'passw0rd', 'p@ssw0rd', 'passwordpassword', 'password1',
  '12345678', '123456789', '1234567890', '123123123', '12341234',
  'qwerty', 'qwertyuiop', 'qwerty123', 'qwertyui', 'asdfghjkl', 'zxcvbnm',
  '1q2w3e4r', '1qaz2wsx', 'zaq12wsx', 'qazwsxedc', 'qweasdzxc',
  'iloveyou', 'admin', 'administrator', 'welcome', 'welcome1', 'letmein',
  'monkey', 'dragon', 'sunshine', 'princess', 'football', 'baseball',
  'superman', 'batman', 'trustno1', 'whatever', 'changeme', 'default',
  'abcd1234', 'abcdefgh', 'aa123456', 'a1b2c3d4', 'test1234', 'temp1234',
  'featherflow', 'poultry', 'chicken', 'chickens', 'farm1234',
};

final RegExp _digitsOnly = RegExp(r'^[0-9]+$');
final RegExp _hasLetter = RegExp(r'[A-Za-z]');
final RegExp _hasLower = RegExp(r'[a-z]');
final RegExp _hasUpper = RegExp(r'[A-Z]');
final RegExp _hasDigit = RegExp(r'[0-9]');
final RegExp _hasSymbol = RegExp(r'[^A-Za-z0-9]');
final RegExp _trailingDigits = RegExp(r'[0-9]+$');

/// Evaluate [password]. [email], [name] and [phone] are used for the
/// similarity check (mirrors Django's `UserAttributeSimilarityValidator`).
PasswordEvaluation evaluatePassword(
  String password, {
  String email = '',
  String name = '',
  String phone = '',
}) {
  if (password.isEmpty) return PasswordEvaluation.empty;

  final errors = <String>[];
  final hints = <String>[];
  final lower = password.toLowerCase();

  if (password.length < kMinPasswordLength) {
    errors.add('Use at least $kMinPasswordLength characters.');
  }
  if (_digitsOnly.hasMatch(password)) {
    errors.add('Add letters — a password can’t be all numbers.');
  } else if (!_hasLetter.hasMatch(password)) {
    errors.add('Include at least one letter.');
  }

  final base = lower.replaceAll(_trailingDigits, '');
  if (_commonPasswords.contains(lower) ||
      (base.length >= 4 && _commonPasswords.contains(base))) {
    errors.add('This password is too common — pick something less guessable.');
  }

  if (_looksSimilarToPersonalInfo(lower, email: email, name: name, phone: phone)) {
    errors.add('Don’t reuse your name, email, or phone number.');
  }

  // Non-blocking strength hints.
  if (!_hasDigit.hasMatch(password)) hints.add('Add a number');
  if (!_hasSymbol.hasMatch(password)) hints.add('Add a symbol (! ? # …)');
  if (!(_hasLower.hasMatch(password) && _hasUpper.hasMatch(password))) {
    hints.add('Mix upper and lower case');
  }

  return PasswordEvaluation(
    errors: errors,
    hints: hints,
    strength: _strength(password, blocked: errors.isNotEmpty),
  );
}

bool _looksSimilarToPersonalInfo(
  String lowerPassword, {
  required String email,
  required String name,
  required String phone,
}) {
  final parts = <String>[
    if (email.contains('@')) email.split('@').first else email,
    ...name.split(RegExp(r'\s+')),
    phone.replaceAll(RegExp(r'[^0-9]'), ''),
  ];
  for (final raw in parts) {
    final part = raw.toLowerCase().trim();
    if (part.length < 4) continue;
    if (lowerPassword.contains(part) || part.contains(lowerPassword)) return true;
  }
  return false;
}

PasswordStrength _strength(String password, {required bool blocked}) {
  if (blocked) return PasswordStrength.weak;

  var score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (password.length >= 16) score++;
  if (_hasLower.hasMatch(password) && _hasUpper.hasMatch(password)) score++;
  if (_hasDigit.hasMatch(password)) score++;
  if (_hasSymbol.hasMatch(password)) score++;

  if (score <= 2) return PasswordStrength.weak;
  if (score == 3) return PasswordStrength.fair;
  if (score == 4) return PasswordStrength.good;
  return PasswordStrength.strong;
}

/// Real-time confirm-password check. Returns `null` when they match (or the
/// confirm field is still empty), otherwise the message to show inline.
String? confirmPasswordError(String password, String confirm) {
  if (confirm.isEmpty) return null;
  if (confirm != password) return 'Passwords do not match.';
  return null;
}
