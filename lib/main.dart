import 'package:flutter/material.dart';
import 'package:idea_notes/app/app.dart';
import 'core/storage/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database
  await DatabaseHelper.instance.database;

  runApp(const IdeaNotesApp());
}
