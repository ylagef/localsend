import 'package:flutter/services.dart';
import 'package:localsend_isolates/model/file_type.dart';

const _channel = MethodChannel('main-delegate-channel');

bool canCopyReceivedImage({required FileType fileType, required String? path, required bool isMacOS}) {
  return isMacOS && fileType == FileType.image && path != null && path.isNotEmpty;
}

/// The native implementation validates and writes image content, not a file URL.
Future<void> copyReceivedImageToClipboard(String path) async {
  await _channel.invokeMethod<void>('copyImageToClipboard', path);
}
