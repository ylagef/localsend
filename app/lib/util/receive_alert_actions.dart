import 'dart:collection';

/// Keeps native quick actions tied to trusted receive data, never callback paths.
class ReceiveAlertActions {
  final Map<String, Future<bool> Function(String)> _pending = {};
  final LinkedHashMap<String, ({String path, bool image})> _completed = LinkedHashMap();
  final Set<String> _busy = {};

  void pending(String sessionId, Future<bool> Function(String) action) {
    _pending
      ..clear()
      ..[sessionId] = action;
  }

  void clearPending(String sessionId) => _pending.remove(sessionId);

  void completed(String sessionId, {required String path, required bool image}) {
    _completed.remove(sessionId);
    _completed[sessionId] = (path: path, image: image);
    while (_completed.length > 8) {
      _completed.remove(_completed.keys.first);
    }
  }

  Future<bool> perform({
    required String sessionId,
    required String kind,
    required String action,
    required Future<void> Function(String) copy,
    required Future<bool> Function(String) open,
    required Future<void> Function() history,
  }) async {
    if (!_busy.add(sessionId)) return false;
    try {
      if (kind == 'pending' && (action == 'accept' || action == 'reject')) {
        return await _pending[sessionId]?.call(action) ?? false;
      }
      if (kind != 'done' && kind != 'error') return false;
      final file = _completed[sessionId];
      if (file == null) return false;
      switch (action) {
        case 'copy':
          if (kind != 'done' || !file.image || file.path.isEmpty) return false;
          await copy(file.path);
          return true;
        case 'open':
          if (kind != 'done' || file.path.isEmpty) return false;
          return await open(file.path);
        case 'history':
          await history();
          return true;
        default:
          return false;
      }
    } finally {
      _busy.remove(sessionId);
    }
  }
}

final receiveAlertActions = ReceiveAlertActions();
