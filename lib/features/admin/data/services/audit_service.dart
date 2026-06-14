import 'dart:math';
import '../models/audit_log.dart';
import 'admin_session.dart';

class AuditService {
  static final AuditService _instance = AuditService._();
  AuditService._();
  static AuditService get instance => _instance;

  final List<AuditEntry> _entries = [];
  List<AuditEntry> get entries => List.unmodifiable(_entries);

  void log(String module, String action, String target, {String? details}) {
    final session = AdminSession.instance;
    _entries.insert(
      0,
      AuditEntry(
        id: 'A${Random().nextInt(99999).toString().padLeft(5, '0')}',
        timestamp: DateTime.now(),
        actorName: session.name,
        actorRole: session.roleDisplayName,
        module: module,
        action: action,
        target: target,
        details: details,
      ),
    );
  }
}
