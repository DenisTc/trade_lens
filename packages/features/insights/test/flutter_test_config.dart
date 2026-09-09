import 'dart:async';

import 'package:features_shared/testing.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    configureGoldenTests(testMain);
