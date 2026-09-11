import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/auth_service.dart';
import '../../../../core/router/app_router.dart';
import '../widgets/signup_widgets.dart';

const _kAccent = Color(0xFF1DB584);
const _kInk = Color(0xFF01291E);
const _kError = Color(0xFFFF5C6A);

/// Enter the 6-digit code sent to an email address or phone number to finish
/// signup (or to unblock a login that was gated on verification).
class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.email,
    this.channel = 'email',
    this.initialMessage = '',
    this.debugCode = '',
    this.devDelivery = false,
  });

  final String email;
  final String channel;
  final String initialMessage;
  final String debugCode;

  /// The server has no real email/SMS provider — the code is only in the
  /// backend terminal (and auto-filled from [debugCode]).
  final bool devDelivery;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _codeCtrl = TextEditingController();
  late String _channel;
  bool _submitting = false;
  bool _resending = false;
  bool _devDelivery = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _devDelivery = widget.devDelivery || widget.debugCode.isNotEmpty;
    if (widget.debugCode.isNotEmpty) _codeCtrl.text = widget.debugCode;
    _startCooldown(60); // a code was just sent before this screen opened
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown = _cooldown - 1);
      if (_cooldown <= 0) t.cancel();
    });
  }

  String get _destinationLabel => _channel == 'phone'
      ? 'your phone'
      : (widget.email.isEmpty ? 'your email' : widget.email);

  Future<void> _submit() async {
    if (_submitting) return;
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await AuthService.instance.confirmVerificationCode(
        email: widget.email, code: code, channel: _channel);
      if (!mounted) return;

      if (result.verificationRequired) {
        // e.g. email done, phone still required.
        setState(() {
          _channel = result.channel;
          _codeCtrl.clear();
          _error = null;
          _devDelivery = result.devDelivery || result.debugCode.isNotEmpty;
        });
        if (result.debugCode.isNotEmpty) _codeCtrl.text = result.debugCode;
        _startCooldown(60);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Now verify $_destinationLabel.'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      if (result.session != null) {
        final roles = result.session!.user.roles;
        final dest = await AuthService.instance
            .getRoleDestination(roles.isNotEmpty ? roles.first : 'farmer');
        if (!mounted) return;
        context.go(dest);
        return;
      }
      // Verified, awaiting admin review.
      context.go(AppRoutes.registrationPending, extra: result.message);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'Could not reach the server. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resend() async {
    if (_resending || _cooldown > 0) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final res = await AuthService.instance
          .requestVerificationCode(email: widget.email, channel: _channel);
      if (!mounted) return;
      if (res.debugCode.isNotEmpty) _codeCtrl.text = res.debugCode;
      setState(() =>
          _devDelivery = res.devDelivery || res.debugCode.isNotEmpty);
      _startCooldown(res.resendCooldown);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('A new code was sent to $_destinationLabel.'),
        behavior: SnackBarBehavior.floating,
      ));
    } on AuthException catch (e) {
      if (!mounted) return;
      final retry = (e.data['retry_after'] as num?)?.toInt() ?? 0;
      if (retry > 0) _startCooldown(retry);
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not resend the code right now.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _kInk,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_channel == 'phone' ? 'Verify your phone' : 'Verify your email',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.login),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(
                    _channel == 'phone'
                        ? Icons.sms_outlined
                        : Icons.mark_email_unread_outlined,
                    color: _kAccent, size: 34),
              ),
              const SizedBox(height: 20),
              const Text(
                'Enter the 6-digit code',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _kInk, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                widget.initialMessage.isNotEmpty
                    ? widget.initialMessage
                    : 'We sent a code to $_destinationLabel. It expires in 10 minutes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.5),
              ),
              if (_devDelivery) ...[
                const SizedBox(height: 16),
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
                      Icon(Icons.terminal_rounded,
                          size: 18, color: Color(0xFF9A5B00)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Development mode: no email/SMS provider is configured, '
                          'so nothing was actually sent. The code is printed in '
                          'the backend terminal — and has been filled in below '
                          'for you.',
                          style: TextStyle(
                              color: Color(0xFF9A5B00), fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              OtpCodeField(
                controller: _codeCtrl,
                hasError: _error != null,
                onCompleted: (_) => _submit(),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _kError, fontSize: 13)),
                ),
              const SizedBox(height: 24),
              SignupSubmitButton(
                label: 'Verify',
                submitting: _submitting,
                onPressed: _submit,
              ),
              const SizedBox(height: 16),
              Center(
                child: _cooldown > 0
                    ? Text('Resend code in ${_cooldown}s',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
                    : TextButton(
                        onPressed: _resending ? null : _resend,
                        child: _resending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Resend code',
                                style: TextStyle(
                                    color: _kAccent, fontWeight: FontWeight.w600)),
                      ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => context.go(AppRoutes.login),
                  child: Text('Back to sign in',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single-field 6-digit code input styled as six boxes.
class OtpCodeField extends StatelessWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.hasError = false,
    this.onCompleted,
  });

  final TextEditingController controller;
  final bool hasError;
  final ValueChanged<String>? onCompleted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      style: const TextStyle(
          fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 12, color: _kInk),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        counterText: '',
        hintText: '••••••',
        hintStyle: TextStyle(
            color: Colors.grey.shade300, letterSpacing: 12, fontSize: 26),
        filled: true,
        fillColor: const Color(0xFFF7F7F7),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: hasError ? _kError : Colors.grey.shade200, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: hasError ? _kError : _kAccent, width: 1.6),
        ),
      ),
      onChanged: (v) {
        if (v.length == 6) onCompleted?.call(v);
      },
    );
  }
}
