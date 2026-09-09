import 'package:data_local/src/database.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// The on-device database, one file in the app's support directory.
/// Tests use `AppDatabase(NativeDatabase.memory())` instead.
AppDatabase openAppDatabase({String name = 'tradelens'}) =>
    AppDatabase(driftDatabase(name: name));
