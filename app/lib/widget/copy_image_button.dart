import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/util/native/image_clipboard.dart';
import 'package:localsend_app/util/ui/snackbar.dart';

class CopyImageButton extends StatefulWidget {
  final String path;

  const CopyImageButton({required this.path, super.key});

  @override
  State<CopyImageButton> createState() => _CopyImageButtonState();
}

class _CopyImageButtonState extends State<CopyImageButton> {
  bool _copying = false;

  Future<void> _copy() async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      await copyReceivedImageToClipboard(widget.path);
      if (mounted) context.showSnackBar(t.general.copiedToClipboard);
    } catch (_) {
      if (mounted) context.showSnackBar(t.general.error);
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: t.receiveHistoryPage.entryActions.copyImage,
      icon: const Icon(Icons.copy),
      onPressed: _copying ? null : _copy,
    );
  }
}
