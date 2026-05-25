import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Firestore documents are capped at 1 MiB. Base64 plus JSON metadata needs
/// headroom, so keep encoded image payloads well under that limit.
const kMenuImageMaxBase64Length = 360000;

/// Whether a base64 image payload is small enough to sync to Firestore.
bool menuImageBase64FitsCloud(String? base64) {
  if (base64 == null || base64.isEmpty) return true;
  return base64.length <= kMenuImageMaxBase64Length;
}

/// Resize and re-encode [input] as JPEG until it fits [kMenuImageMaxBase64Length].
Uint8List? compressMenuImageForCloud(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) return null;

  var working = decoded;
  const sideLimits = <int>[720, 640, 520, 420];
  const qualitySteps = <int>[72, 62, 52, 42, 32, 24];

  for (final side in sideLimits) {
    if (working.width > side || working.height > side) {
      working = img.copyResize(
        working,
        width: working.width >= working.height ? side : null,
        height: working.height > working.width ? side : null,
      );
    }

    for (final quality in qualitySteps) {
      final jpg = Uint8List.fromList(img.encodeJpg(working, quality: quality));
      if (menuImageBase64FitsCloud(base64Encode(jpg))) {
        return jpg;
      }
    }
  }

  return null;
}
