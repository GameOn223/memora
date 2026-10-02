import 'package:flutter/material.dart';

// Keeps the headless entrypoint in the build. A release build drops any
// library main.dart can't reach, and WorkManager could then not start
// backgroundMain. Do not remove this line.
export 'background_main.dart' show backgroundMain;

void main() {
  runApp(const MemoraApp());
}

class MemoraApp extends StatelessWidget {
  const MemoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('Memora'))),
    );
  }
}
