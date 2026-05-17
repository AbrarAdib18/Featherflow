import 'package:flutter/material.dart';
import '../models/article.dart';

class AuthorAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const AuthorAvatar({super.key, required this.name, this.radius = 14});

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: PPColors.primary,
      child: Text(
        _initials,
        style: ppLabel(
          size: radius * 0.75,
          weight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
