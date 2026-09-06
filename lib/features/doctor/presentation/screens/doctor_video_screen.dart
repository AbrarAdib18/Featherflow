import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/doctor_api_service.dart';
import '../doctor_theme.dart';

/// Video consultations run in an external Jitsi Meet room — no native SDK, works
/// on web + mobile. The doctor starts a call (backend flips the consultation to
/// in_progress and notifies the farmer), both open the same room URL.
class DoctorVideoScreen extends StatefulWidget {
  const DoctorVideoScreen({super.key});

  @override
  State<DoctorVideoScreen> createState() => _DoctorVideoScreenState();
}

class _DoctorVideoScreenState extends State<DoctorVideoScreen> {
  List<Map<String, dynamic>> _online = const [];
  final Map<String, Map<String, dynamic>> _video = {};
  bool _loading = true;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await DoctorApiService.get('appointments');
      final rows = List<Map<String, dynamic>>.from(
          (data['appointments'] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map)));
      final online = rows
          .where((a) =>
              a['mode'] == 'online' &&
              (a['status'] == 'accepted' || a['status'] == 'in_progress'))
          .toList()
        ..sort((a, b) => '${a['scheduled_at']}'.compareTo('${b['scheduled_at']}'));
      for (final a in online) {
        try {
          _video['${a['id']}'] =
              await DoctorApiService.get('appointments/${a['id']}/video');
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _online = online;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _openRoom(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) _toast('Could not open the video room. URL: $url');
  }

  Future<void> _start(String id) async {
    setState(() => _busyId = id);
    try {
      final state = await DoctorApiService.post('appointments/$id/video', {'action': 'start'});
      _video[id] = state;
      await _openRoom('${state['room_url']}');
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
      _load();
    }
  }

  Future<void> _end(String id) async {
    setState(() => _busyId = id);
    try {
      _video[id] = await DoctorApiService.post('appointments/$id/video', {'action': 'end'});
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busyId = null);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VetColors.bg,
      appBar: AppBar(
        backgroundColor: VetColors.appBar,
        foregroundColor: Colors.white,
        title: const Text('Video Consultations',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: VetColors.inProgress))
          : _error != null
              ? _CenteredNote(
                  icon: Icons.wifi_off,
                  title: 'Could not load consultations',
                  subtitle: _error,
                  onRetry: _load)
              : _online.isEmpty
                  ? const _CenteredNote(
                      icon: Icons.videocam_off_outlined,
                      title: 'No online consultations to call',
                      subtitle:
                          'Accepted online consultations appear here. Start a call and the farmer is notified to join the same room.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _online.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _card(_online[i]),
                      ),
                    ),
    );
  }

  Widget _card(Map<String, dynamic> a) {
    final id = '${a['id']}';
    final v = _video[id] ?? const {};
    final active = v['active'] == true;
    final busy = _busyId == id;
    final when = DateTime.tryParse('${a['scheduled_at']}');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: vetCard(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: VetColors.inProgressLight,
            child: Icon(Icons.person, color: VetColors.inProgress, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a['farmer_name'] ?? 'Farmer'}',
                  style: const TextStyle(
                      color: VetColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              Text(
                when == null
                    ? '${a['scheduled_at']}'
                    : '${when.day}/${when.month} · ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: VetColors.textSecondary, fontSize: 12),
              ),
            ]),
          ),
          vetChip(
            active ? 'Live' : (a['status'] == 'in_progress' ? 'In progress' : 'Accepted'),
            active ? VetColors.emergency : VetColors.inProgress,
            active ? VetColors.emergencyLight : VetColors.inProgressLight,
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          if (!active)
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : () => _start(id),
                style: FilledButton.styleFrom(
                    backgroundColor: VetColors.inProgress, foregroundColor: Colors.white),
                icon: busy
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.videocam, size: 18),
                label: const Text('Start call'),
              ),
            )
          else ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openRoom('${v['room_url']}'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Rejoin'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : () => _end(id),
                style: FilledButton.styleFrom(
                    backgroundColor: VetColors.red, foregroundColor: Colors.white),
                icon: const Icon(Icons.call_end, size: 18),
                label: const Text('End call'),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _CenteredNote extends StatelessWidget {
  const _CenteredNote({required this.icon, required this.title, this.subtitle, this.onRetry});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: VetColors.grey),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: VetColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: VetColors.textSecondary, fontSize: 13, height: 1.5)),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ]),
      ),
    );
  }
}
