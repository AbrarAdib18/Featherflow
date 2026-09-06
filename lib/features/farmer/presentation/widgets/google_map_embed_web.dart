// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

class GoogleMapEmbed extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String label;
  final bool interactive;

  const GoogleMapEmbed({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.label,
    this.interactive = true,
  });

  @override
  State<GoogleMapEmbed> createState() => _GoogleMapEmbedState();
}

class _GoogleMapEmbedState extends State<GoogleMapEmbed> {
  late String _viewType;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(covariant GoogleMapEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude ||
        oldWidget.interactive != widget.interactive) {
      _register();
    }
  }

  void _register() {
    _viewType =
        'google-map-${widget.latitude}-${widget.longitude}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final query =
          Uri.encodeComponent('${widget.latitude},${widget.longitude}');
      return html.IFrameElement()
        ..src = 'https://maps.google.com/maps?q=$query&z=15&output=embed'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.pointerEvents = widget.interactive ? 'auto' : 'none'
        ..allowFullscreen = true
        ..setAttribute('loading', 'lazy')
        ..setAttribute('title', 'Google Map - ${widget.label}');
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(
        key: ValueKey(_viewType),
        viewType: _viewType,
      );
}
