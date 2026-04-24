import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:idea_notes/app/app.dart';
import 'core/storage/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge display
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));

  // Initialize database
  await DatabaseHelper.instance.database;

  // Limit image cache to 50 MB
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20;

  runApp(const IdeaNotesApp());
}
