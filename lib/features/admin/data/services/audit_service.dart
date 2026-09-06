import '../models/audit_log.dart';
import 'admin_api_service.dart';

/// Audit is now recorded server-side (`activity_logs`, immutable) for every
/// admin mutation. This shim keeps the old `log()` call sites compiling as
/// no-ops and exposes [fetch] for the Audit Trail viewer.
class AuditService {
  static final AuditService _instance = AuditService._();
  AuditService._();
  static AuditService get instance => _instance;

  /// Deprecated: the backend writes the audit row. Kept as a no-op so existing
  /// screens don't need touching in this pass.
  @Deprecated('Audit is recorded server-side; this is a no-op.')
  void log(String module, String action, String target, {String? details}) {}

  Future<({List<AuditEntry> entries, int total})> fetch({
    Map<String, String>? filters,
    int limit = 100,
    int offset = 0,
  }) async {
    final data = await AdminApiService.instance.auditLogs(filters: {
      ...?filters,
      'limit': '$limit',
      'offset': '$offset',
    });
    final rows = (data['results'] as List? ?? const [])
        .map((e) => AuditEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return (entries: rows, total: (data['total'] as num?)?.toInt() ?? rows.length);
  }
}
