import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../widgets/signup_widgets.dart';
import 'otp_verification_screen.dart' show OtpCodeField;

const _kAccent = Color(0xFF1DB584);
const _kInk = Color(0xFF01291E);
const _kError = Color(0xFFFF5C6A);

/// Self-service password reset: request a code by email, then set a new password.
class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  int _step = 1;
  bool _busy = false;
  bool _obscure = true;
  bool _devDelivery = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_emailCtrl, _codeCtrl, _passwordCtrl, _confirmCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _startCooldown(int s) {
    _timer?.cancel();
    setState(() => _cooldown = s);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _requestCode() async {
    if (_busy) return;
    final email = _emailCtrl.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Enter the email address on your account.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await AuthService.instance.requestPasswordReset(email: email);
      if (!mounted) return;
      if (res.debugCode.isNotEmpty) _codeCtrl.text = res.debugCode;
      _startCooldown(res.resendCooldown);
      setState(() {
        _step = 2;
        _devDelivery = res.devDelivery || res.debugCode.isNotEmpty;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReset() async {
    if (_busy) return;
    final code = _codeCtrl.text.trim();
    final pw = _passwordCtrl.text;
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    if (pw.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (pw != _confirmCtrl.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final detail = await AuthService.instance.confirmPasswordReset(
        email: _emailCtrl.text.trim(), code: code, newPassword: pw);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(detail), behavior: SnackBarBehavior.floating));
      context.go(AppRoutes.login);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _busy) return;
    await _requestCode();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _kInk,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Reset password',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              _step == 2 ? setState(() => _step = 1) : context.go(AppRoutes.login),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          child: _step == 1 ? _stepEmail() : _stepReset(),
        ),
      ),
    );
  }

  Widget _stepEmail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Forgot your password?',
            style: TextStyle(color: _kInk, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          'Enter your account email and we will send you a 6-digit code to '
          'reset it.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        _field(_emailCtrl, 'Email', Icons.email_outlined,
            keyboard: TextInputType.emailAddress),
        if (_error != null) _errorText(),
        const SizedBox(height: 24),
        SignupSubmitButton(
            label: 'Send code', submitting: _busy, onPressed: _requestCode),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => context.go(AppRoutes.login),
            child: Text('Back to sign in',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _stepReset() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Choose a new password',
            style: TextStyle(color: _kInk, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Enter the code sent to ${_emailCtrl.text.trim()} and your new password.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.5)),
        if (_devDelivery) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD8A8)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.terminal_rounded, size: 18, color: Color(0xFF9A5B00)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Development mode: no mail provider is configured. The code is '
                    'in the backend terminal (and filled in below).',
                    style: TextStyle(
                        color: Color(0xFF9A5B00), fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        OtpCodeField(controller: _codeCtrl, hasError: _error != null),
        const SizedBox(height: 16),
        _field(_passwordCtrl, 'New password', Icons.lock_outline,
            obscure: _obscure,
            suffix: IconButton(
              icon: Icon(
                  _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20, color: Colors.grey.shade400),
              onPressed: () => setState(() => _obscure = !_obscure),
            )),
        const SizedBox(height: 12),
        _field(_confirmCtrl, 'Confirm new password', Icons.lock_outline,
            obscure: _obscure),
        if (_error != null) _errorText(),
        const SizedBox(height: 24),
        SignupSubmitButton(
            label: 'Reset password', submitting: _busy, onPressed: _confirmReset),
        const SizedBox(height: 12),
        Center(
          child: _cooldown > 0
              ? Text('Resend code in ${_cooldown}s',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
              : TextButton(
                  onPressed: _resend,
                  child: const Text('Resend code',
                      style: TextStyle(color: _kAccent, fontWeight: FontWeight.w600))),
        ),
      ],
    );
  }

  Widget _errorText() => Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Text(_error!, style: const TextStyle(color: _kError, fontSize: 13)),
      );

  Widget _field(TextEditingController c, String hint, IconData icon,
      {TextInputType? keyboard, bool obscure = false, Widget? suffix}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      obscureText: obscure,
      style: const TextStyle(color: _kInk, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFFF7F7F7),
        prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kAccent, width: 1.5)),
      ),
    );
  }
}
