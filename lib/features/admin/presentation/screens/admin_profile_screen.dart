import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_session.dart';
import '../../data/services/admin_api_service.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';
import '../widgets/admin_dialogs.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  bool _editing = false;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _deptCtrl;
  late final TextEditingController _bioCtrl;

  @override
  void initState() {
    super.initState();
    final session = AdminSession.instance;
    _nameCtrl = TextEditingController(text: session.name);
    _phoneCtrl = TextEditingController(text: '+880 1700-000000');
    _deptCtrl = TextEditingController(text: 'IT & Operations');
    _bioCtrl = TextEditingController(
        text:
            'Admin managing the Featherflow platform and all user operations.');
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _deptCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await AdminApiService.instance.profile();
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = data['name']?.toString() ?? _nameCtrl.text;
        _phoneCtrl.text = data['phone']?.toString() ?? '';
        _deptCtrl.text = data['department']?.toString() ?? '';
        _bioCtrl.text = data['bio']?.toString() ?? '';
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    await AdminApiService.instance.updateProfile({
      'full_name': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'department': _deptCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
    });
    if (!mounted) return;
    await AdminSession.instance.refresh();
    if (!mounted) return;
    setState(() => _editing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile updated successfully'),
        backgroundColor: AColors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'My Profile',
      module: AdminModule.dashboard,
      appBarActions: [
        if (!_editing)
          TextButton.icon(
            onPressed: () => setState(() => _editing = true),
            icon: const Icon(Icons.edit_outlined,
                color: AColors.secondary, size: 16),
            label: const Text('Edit',
                style: TextStyle(
                    color: AColors.secondary, fontWeight: FontWeight.w600)),
          )
        else ...[
          TextButton(
            onPressed: () => setState(() => _editing = false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
          ),
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(
                    color: AColors.secondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
        ],
      ],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _AvatarSection(editing: _editing, nameCtrl: _nameCtrl),
            const SizedBox(height: 16),
            _StatsRow(),
            const SizedBox(height: 16),
            _InfoSection(
              editing: _editing,
              nameCtrl: _nameCtrl,
              phoneCtrl: _phoneCtrl,
              deptCtrl: _deptCtrl,
              bioCtrl: _bioCtrl,
            ),
            const SizedBox(height: 16),
            _SecuritySection(),
            const SizedBox(height: 16),
            _NotifSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Avatar section ────────────────────────────────────────────────────────────

class _AvatarSection extends StatelessWidget {
  final bool editing;
  final TextEditingController nameCtrl;

  const _AvatarSection({required this.editing, required this.nameCtrl});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AdminSession.instance,
      builder: (_, __) {
        final session = AdminSession.instance;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: aCard(),
          child: Column(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: AColors.primary,
                    child: Text(
                      session.name.isNotEmpty
                          ? session.name[0].toUpperCase()
                          : 'A',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (editing)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                            color: AColors.secondary, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 14),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(session.name,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AColors.textPrimary)),
              const SizedBox(height: 4),
              Text(session.email,
                  style: const TextStyle(
                      fontSize: 13, color: AColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  aChip(session.roleDisplayName, AColors.secondary,
                      AColors.secondary),
                  const SizedBox(width: 8),
                  aChip('Verified', AColors.green, AColors.green),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
            child: _StatCard('1,240', 'Users Managed', Icons.people_outline,
                AColors.secondary, AColors.greenLight)),
        SizedBox(width: 10),
        Expanded(
            child: _StatCard('38', 'Actions Today', Icons.bolt_outlined,
                AColors.amber, AColors.amberLight)),
        SizedBox(width: 10),
        Expanded(
            child: _StatCard('7', 'Open Tickets', Icons.support_agent_outlined,
                AColors.blue, AColors.blueLight)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color, bg;

  const _StatCard(this.value, this.label, this.icon, this.color, this.bg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: aCard(),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AColors.textPrimary)),
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: AColors.textSecondary),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ── Info section ──────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final bool editing;
  final TextEditingController nameCtrl, phoneCtrl, deptCtrl, bioCtrl;

  const _InfoSection({
    required this.editing,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.deptCtrl,
    required this.bioCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: aCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Profile Information',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AColors.textPrimary)),
          const SizedBox(height: 14),
          _Field('Full Name', nameCtrl, Icons.person_outline, editing),
          const SizedBox(height: 12),
          _ReadField(
              'Email', AdminSession.instance.email, Icons.email_outlined),
          const SizedBox(height: 12),
          _Field('Phone', phoneCtrl, Icons.phone_outlined, editing),
          const SizedBox(height: 12),
          _Field('Department', deptCtrl, Icons.business_outlined, editing),
          const SizedBox(height: 12),
          _Field('Bio', bioCtrl, Icons.info_outline, editing, maxLines: 3),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final IconData icon;
  final bool editing;
  final int maxLines;

  const _Field(this.label, this.ctrl, this.icon, this.editing,
      {this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    if (!editing) {
      return _InfoRow(icon: icon, label: label, value: ctrl.text);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AColors.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13, color: AColors.textPrimary),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: AColors.grey),
            filled: true,
            fillColor: AColors.surface2,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AColors.cardBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AColors.cardBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AColors.secondary, width: 1.5)),
          ),
        ),
      ],
    );
  }
}

class _ReadField extends StatelessWidget {
  final String label, value;
  final IconData icon;

  const _ReadField(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _InfoRow(icon: icon, label: label, value: value),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: AColors.surface2, borderRadius: BorderRadius.circular(4)),
          child: const Text('Cannot edit',
              style: TextStyle(fontSize: 9, color: AColors.grey)),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AColors.grey),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AColors.textSecondary)),
            Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AColors.textPrimary)),
          ],
        ),
      ],
    );
  }
}

// ── Security section ──────────────────────────────────────────────────────────

class _SecuritySection extends StatefulWidget {
  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  bool _twoFactorEnabled = true;

  @override
  void initState() {
    super.initState();
    AdminApiService.instance.profile().then((data) {
      if (mounted) {
        setState(() => _twoFactorEnabled = data['two_factor_enabled'] == true);
      }
    });
  }

  Future<void> _setTwoFactor(bool value) async {
    await AdminApiService.instance.updateProfile({'two_factor_enabled': value});
    if (!mounted) return;
    setState(() => _twoFactorEnabled = value);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(value
            ? 'Two-factor authentication enabled'
            : 'Two-factor authentication disabled'),
        backgroundColor: value ? AColors.green : AColors.orange));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: aCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Security',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AColors.textPrimary)),
          const SizedBox(height: 12),
          _SecurityTile(
            Icons.lock_outline,
            'Change Password',
            'Last changed 30 days ago',
            () => _showChangePasswordSheet(context),
          ),
          const Divider(height: 1, color: AColors.divider),
          _SecurityTile(
            Icons.shield_outlined,
            'Two-Factor Authentication',
            _twoFactorEnabled ? 'Enabled via email OTP' : 'Disabled',
            () => _setTwoFactor(!_twoFactorEnabled),
            trailing: Switch(
              value: _twoFactorEnabled,
              onChanged: _setTwoFactor,
              activeThumbColor: AColors.secondary,
            ),
          ),
          const Divider(height: 1, color: AColors.divider),
          _SecurityTile(
            Icons.history,
            'Login History',
            'Last login: Today, 09:00 AM',
            () => showAdminDetails(context,
                title: 'Login History',
                icon: Icons.history,
                fields: const [
                  MapEntry('Today, 09:00 AM', 'Dhaka, Bangladesh · Web'),
                  MapEntry(
                      'Yesterday, 06:42 PM', 'Dhaka, Bangladesh · Android'),
                  MapEntry('Jun 10, 08:15 AM', 'Dhaka, Bangladesh · Web'),
                ]),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordSheet(BuildContext context) {
    final currentPassword = TextEditingController();
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Change Password',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AColors.textPrimary)),
            const SizedBox(height: 16),
            _PwField('Current Password', controller: currentPassword),
            const SizedBox(height: 10),
            _PwField('New Password', controller: newPassword),
            const SizedBox(height: 10),
            _PwField('Confirm New Password', controller: confirmPassword),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (newPassword.text.length < 8 ||
                      newPassword.text != confirmPassword.text) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Passwords must match and contain at least 8 characters'),
                        backgroundColor: AColors.red));
                    return;
                  }
                  await AdminApiService.instance
                      .changePassword(currentPassword.text, newPassword.text);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Password updated successfully'),
                      backgroundColor: AColors.green));
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Update Password',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PwField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  const _PwField(this.label, {this.controller});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: true,
        style: const TextStyle(color: AColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AColors.grey, fontSize: 13),
          filled: true,
          fillColor: AColors.surface2,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AColors.cardBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AColors.cardBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AColors.secondary, width: 1.5)),
        ),
      );
}

class _SecurityTile extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SecurityTile(this.icon, this.title, this.sub, this.onTap,
      {this.trailing});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
            color: AColors.surface2, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: AColors.primary),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AColors.textPrimary)),
      subtitle: Text(sub,
          style: const TextStyle(fontSize: 11, color: AColors.textSecondary)),
      trailing: trailing ??
          const Icon(Icons.chevron_right, color: AColors.grey, size: 18),
      onTap: onTap,
    );
  }
}

// ── Notifications section ─────────────────────────────────────────────────────

class _NotifSection extends StatefulWidget {
  @override
  State<_NotifSection> createState() => _NotifSectionState();
}

class _NotifSectionState extends State<_NotifSection> {
  bool _userActivity = true;
  bool _systemAlerts = true;
  bool _weeklyReport = false;

  @override
  void initState() {
    super.initState();
    AdminApiService.instance.profile().then((data) {
      final prefs = data['notification_preferences'];
      if (!mounted || prefs is! Map) return;
      setState(() {
        _userActivity = prefs['user_activity'] != false;
        _systemAlerts = prefs['system_alerts'] != false;
        _weeklyReport = prefs['weekly_report'] == true;
      });
    });
  }

  Future<void> _savePreferences() => AdminApiService.instance.updateProfile({
        'notification_preferences': {
          'user_activity': _userActivity,
          'system_alerts': _systemAlerts,
          'weekly_report': _weeklyReport,
        }
      });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: aCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Notifications',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AColors.textPrimary)),
          const SizedBox(height: 12),
          _NotifTile('User Activity Alerts', _userActivity, (v) {
            setState(() => _userActivity = v);
            _savePreferences();
          }),
          const Divider(height: 1, color: AColors.divider),
          _NotifTile('System Alerts', _systemAlerts, (v) {
            setState(() => _systemAlerts = v);
            _savePreferences();
          }),
          const Divider(height: 1, color: AColors.divider),
          _NotifTile('Weekly Report Email', _weeklyReport, (v) {
            setState(() => _weeklyReport = v);
            _savePreferences();
          }),
        ],
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _NotifTile(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AColors.textPrimary)),
      trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AColors.secondary),
    );
  }
}
