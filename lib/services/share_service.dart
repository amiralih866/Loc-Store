import 'package:share_plus/share_plus.dart';

/// Hands a generated file to the Android native share sheet
/// (WhatsApp / Telegram / Bluetooth / Files / ...).
Future<bool> shareFile(String path, {String? text}) async {
  try {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: text),
    );
    return true;
  } catch (_) {
    return false;
  }
}
