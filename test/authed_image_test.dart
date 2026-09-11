import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:featherflow/core/network/authed_image.dart';

void main() {
  group('AuthedNetworkImage', () {
    const url = 'http://127.0.0.1:8000/api/auth/registration-documents/abc/';

    test('is an ImageProvider', () {
      expect(const AuthedNetworkImage(url), isA<ImageProvider>());
    });

    test('equality + hashCode key on url and scale (so imageCache dedupes)', () {
      expect(const AuthedNetworkImage(url), const AuthedNetworkImage(url));
      expect(const AuthedNetworkImage(url).hashCode,
          const AuthedNetworkImage(url).hashCode);
      expect(const AuthedNetworkImage(url),
          isNot(const AuthedNetworkImage('$url?x')));
      expect(const AuthedNetworkImage(url, scale: 2.0),
          isNot(const AuthedNetworkImage(url)));
    });

    test('obtainKey resolves to itself synchronously', () async {
      const provider = AuthedNetworkImage(url);
      final key = await provider.obtainKey(ImageConfiguration.empty);
      expect(identical(key, provider), isTrue);
    });
  });
}
