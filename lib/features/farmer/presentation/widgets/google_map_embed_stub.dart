import 'package:flutter/material.dart';

class GoogleMapEmbed extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String label;

  const GoogleMapEmbed({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Center(
        child:
            Text('$label\n$latitude, $longitude', textAlign: TextAlign.center),
      );
}
