import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';

/// An [ImageProvider] that fetches the bytes itself with the current JWT in the
/// `Authorization` header, then hands them to Flutter's normal image pipeline
/// (so results are cached by `PaintingBinding.instance.imageCache` like any
/// other provider — keyed on [url]).
///
/// Needed for images served from access-controlled endpoints such as
/// `/api/auth/registration-documents/<token>/` (profile photos, farm photos,
/// uploaded documents): a plain `NetworkImage` sends no auth header, so those
/// only load during the short unclaimed-grace window and then 401.
///
/// With no session it falls back to an unauthenticated request (the signup
/// preview, still inside the grace window). Works on every platform incl. web.
@immutable
class AuthedNetworkImage extends ImageProvider<AuthedNetworkImage> {
  const AuthedNetworkImage(this.url, {this.scale = 1.0});

  final String url;
  final double scale;

  @override
  Future<AuthedNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<AuthedNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
      AuthedNetworkImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _fetch(key, decode),
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('URL', key.url),
      ],
    );
  }

  Future<ui.Codec> _fetch(
      AuthedNetworkImage key, ImageDecoderCallback decode) async {
    final headers = <String, String>{};
    final auth = AuthService.instance;
    final session = auth.currentSession ?? await auth.getStoredSession();
    if (session != null && session.accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${session.accessToken}';
    }

    final uri = Uri.parse(key.url);
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      // Drop the cache entry so a later retry (e.g. after login) can succeed.
      scheduleMicrotask(
          () => PaintingBinding.instance.imageCache.evict(key));
      throw NetworkImageLoadException(
          statusCode: response.statusCode, uri: uri);
    }
    final buffer =
        await ui.ImmutableBuffer.fromUint8List(response.bodyBytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is AuthedNetworkImage && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'AuthedNetworkImage')}("$url", scale: $scale)';
}
