import 'package:flutter/material.dart';
import '../doctor_theme.dart';

class DoctorVideoScreen extends StatelessWidget {
  const DoctorVideoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VetColors.bg,
      appBar: AppBar(
        backgroundColor: VetColors.appBar,
        foregroundColor: Colors.white,
        title: const Text(
          'Video Consultations',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: VetColors.inProgressLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: VetColors.inProgress.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.videocam_outlined,
                  color: VetColors.inProgress,
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Video Calling',
                style: TextStyle(
                  color: VetColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Live video consultations are ready to integrate.\nNo video package is currently in pubspec.yaml.',
                style: TextStyle(
                  color: VetColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: vetCard(),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'To enable video calls, add one of these to pubspec.yaml:',
                      style: TextStyle(
                        color: VetColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 12),
                    _PackageOption(
                      name: 'agora_rtc_engine',
                      description: 'Agora — production-grade, low latency',
                      recommended: true,
                    ),
                    SizedBox(height: 8),
                    _PackageOption(
                      name: 'flutter_webrtc',
                      description: 'WebRTC — open source, peer-to-peer',
                      recommended: false,
                    ),
                    SizedBox(height: 8),
                    _PackageOption(
                      name: 'jitsi_meet_flutter_sdk',
                      description: 'Jitsi — easy integration, open source',
                      recommended: false,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Once added, the video call screen will be wired\ninto appointments and chat automatically.',
                style: TextStyle(color: VetColors.grey, fontSize: 12, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackageOption extends StatelessWidget {
  final String name;
  final String description;
  final bool recommended;

  const _PackageOption({
    required this.name,
    required this.description,
    required this.recommended,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: recommended ? VetColors.availableLight : VetColors.surface2,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            Icons.code,
            size: 14,
            color: recommended ? VetColors.available : VetColors.grey,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: VetColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (recommended) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: VetColors.availableLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'recommended',
                        style: TextStyle(
                          color: VetColors.available,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                description,
                style: const TextStyle(color: VetColors.grey, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
