/// Shared Bangladeshi-taka formatter (thousand separators, ৳ prefix).
///
/// Originally lived in `cost_management_screen.dart` and got imported with
/// `show taka` from several unrelated screens, which meant pulling in an
/// entire Cost Management screen just for a formatting function — and every
/// screen outside that import chain hand-rolled its own `'৳$value'` with no
/// thousand separators instead. Moved here so it can be imported directly;
/// `cost_management_screen.dart` re-exports it so existing `show taka`
/// imports keep working unchanged.
String taka(num v) {
  final s = v.abs().toStringAsFixed(0);
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}৳$buf';
}
