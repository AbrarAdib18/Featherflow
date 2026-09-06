class AuditEntry {
  final String id;
  final DateTime timestamp;
  final String actorName;
  final String actorRole;
  final String module;
  final String action;
  final String actionType;
  final String target;
  final String? targetId;
  final String reason;
  final String ipAddress;
  final Map<String, dynamic>? oldValue;
  final Map<String, dynamic>? newValue;
  final String? details;

  const AuditEntry({
    required this.id,
    required this.timestamp,
    required this.actorName,
    required this.actorRole,
    required this.module,
    required this.action,
    this.actionType = '',
    required this.target,
    this.targetId,
    this.reason = '',
    this.ipAddress = '',
    this.oldValue,
    this.newValue,
    this.details,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    final created = json['created_at']?.toString();
    return AuditEntry(
      id: json['id']?.toString() ?? '',
      timestamp: created != null
          ? (DateTime.tryParse(created) ?? DateTime.now())
          : DateTime.now(),
      actorName: json['admin']?.toString() ?? 'System',
      actorRole: json['admin_role']?.toString() ?? '',
      module: json['module']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      actionType: json['action_type']?.toString() ?? '',
      target: json['target_type']?.toString() ?? '',
      targetId: json['target_id']?.toString(),
      reason: json['reason']?.toString() ?? '',
      ipAddress: json['ip_address']?.toString() ?? '',
      oldValue: (json['old_value'] as Map?)?.cast<String, dynamic>(),
      newValue: (json['new_value'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
