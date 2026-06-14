class AuditEntry {
  final String id;
  final DateTime timestamp;
  final String actorName;
  final String actorRole;
  final String module;
  final String action;
  final String target;
  final String? details;

  const AuditEntry({
    required this.id,
    required this.timestamp,
    required this.actorName,
    required this.actorRole,
    required this.module,
    required this.action,
    required this.target,
    this.details,
  });
}
