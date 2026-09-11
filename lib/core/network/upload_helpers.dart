import 'package:http_parser/http_parser.dart' show MediaType;

/// Map a filename to a `Content-Type` for multipart uploads.
///
/// Flutter's `http.MultipartFile.fromBytes` defaults the part to
/// `application/octet-stream` when no `contentType` is given, which several
/// backend endpoints (signup docs, community media) used to reject outright.
/// Set this on every upload so the type travels with the bytes.
MediaType? mediaTypeForFilename(String filename) {
  final ext = filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : '';
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return MediaType('image', 'jpeg');
    case 'png':
      return MediaType('image', 'png');
    case 'webp':
      return MediaType('image', 'webp');
    case 'gif':
      return MediaType('image', 'gif');
    case 'pdf':
      return MediaType('application', 'pdf');
    case 'mp4':
      return MediaType('video', 'mp4');
    case 'mov':
      return MediaType('video', 'quicktime');
    default:
      return null;
  }
}
