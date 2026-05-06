import 'package:uuid/uuid.dart';

class CorrelationIdManager {
  static const _uuid = Uuid();

  static String generate() {
    return _uuid.v4();
  }
}
