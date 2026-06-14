import 'package:flutter/material.dart';
import '../../data/models/admin_role.dart';
import '../../data/services/admin_session.dart';
import '../admin_theme.dart';
import '../widgets/admin_scaffold.dart';

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
        text: 'Admin managing the Featherflow platform and all user operations.');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _deptCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _save() {
    AdminSession.instance.setRole(
      AdminSession.instance.role,
      name: _nameCtrl.text,
    );
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
                            color: AColors.secondary,
                            shape: BoxShape.circle),
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
            child: _StatCard('7', 'Open Tickets',
                Icons.support_agent_outlined, AColors.blue, AColors.blueLight)),
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
              style: const TextStyle(
                  fontSize: 10, color: AColors.textSecondary),
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
          _ReadField('Email', AdminSession.instance.email,
              Icons.email_outlined),
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
                borderSide: const BorderSide(
                    color: AColors.secondary, width: 1.5)),
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
              color: AColors.surface2,
              borderRadius: BorderRadius.circular(4)),
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

  const _InfoRow({required this.icon, required this.label, required this.value});

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

class _SecuritySection extends StatelessWidget {
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
            'Enabled via email OTP',
            () {},
            trailing: Switch(
              value: true,
              onChanged: (_) {},
              activeThumbColor: AColors.secondary,
            ),
          ),
          const Divider(height: 1, color: AColors.divider),
          _SecurityTile(
            Icons.history,
            'Login History',
            'Last login: Today, 09:00 AM',
            () {},
          ),
        ],
      ),
    );
  }

  void _showChangePasswordSheet(BuildContext context) {
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
            const _PwField('Current Password'),
            const SizedBox(height: 10),
            const _PwField('New Password'),
            const SizedBox(height: 10),
            const _PwField('Confirm New Password'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
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
  const _PwField(this.label);

  @override
  Widget build(BuildContext context) => TextField(
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
            color: AColors.surface2,
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: AColors.primary),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AColors.textPrimary)),
      subtitle: Text(sub,
          style: const TextStyle(
              fontSize: 11, color: AColors.textSecondary)),
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
          _NotifTile('User Activity Alerts', _userActivity,
              (v) => setState(() => _userActivity = v)),
          const Divider(height: 1, color: AColors.divider),
          _NotifTile('System Alerts', _systemAlerts,
              (v) => setState(() => _systemAlerts = v)),
          const Divider(height: 1, color: AColors.divider),
          _NotifTile('Weekly Report Email', _weeklyReport,
              (v) => setState(() => _weeklyReport = v)),
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
          value: value, onChanged: onChanged, activeThumbColor: AColors.secondary),
    );
  }
}
