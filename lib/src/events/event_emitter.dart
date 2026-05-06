import 'dart:async';
import 'anam_event.dart';

class EventEmitter {
  final Map<AnamEvent, StreamController<dynamic>> _controllers = {};

  Stream<T> on<T>(AnamEvent event) {
    _controllers[event] ??= StreamController<dynamic>.broadcast();
    return _controllers[event]!.stream.cast<T>();
  }

  void emit(AnamEvent event, [dynamic data]) {
    if (_controllers.containsKey(event)) {
      _controllers[event]!.add(data);
    }
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }
}
