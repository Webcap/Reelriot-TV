import 'dart:async';
import 'package:flutter/material.dart';
import 'package:reelriot_tv/main.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('[FlutterError] ${details.exception}');
    };
    await bootstrap('.env.prod');
  }, (error, stack) {
    debugPrint('[ZonedError] $error\n$stack');
  });
}
