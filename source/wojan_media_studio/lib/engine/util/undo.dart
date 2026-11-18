import 'dart:convert';

/// Snapshot based undo/redo stack for JSON serialisable documents.
class UndoStack {
  final int limit;
  final _undo = <String>[];
  final _redo = <String>[];
  final _labels = <String>[];
  UndoStack({this.limit = 200});

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get lastLabel => _labels.isEmpty ? null : _labels.last;

  /// Call BEFORE mutating, passing the current state.
  void push(Map<String, dynamic> state, [String label = '']) {
    _undo.add(jsonEncode(state));
    _labels.add(label);
    if (_undo.length > limit) {
      _undo.removeAt(0);
      _labels.removeAt(0);
    }
    _redo.clear();
  }

  Map<String, dynamic>? undo(Map<String, dynamic> current) {
    if (_undo.isEmpty) return null;
    _redo.add(jsonEncode(current));
    _labels.removeLast();
    return jsonDecode(_undo.removeLast()) as Map<String, dynamic>;
  }

  Map<String, dynamic>? redo(Map<String, dynamic> current) {
    if (_redo.isEmpty) return null;
    _undo.add(jsonEncode(current));
    _labels.add('redo');
    return jsonDecode(_redo.removeLast()) as Map<String, dynamic>;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
    _labels.clear();
  }
}
