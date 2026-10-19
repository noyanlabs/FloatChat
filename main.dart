import 'package:flutter/material.dart';
import 'floatchat_screen.dart';

void main() {
  runApp(const FloatChatApp());
}

class FloatChatApp extends StatelessWidget {
  const FloatChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FloatChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F6FB2)),
        fontFamily: 'Roboto',
      ),
      home: const FloatChatScreen(),
    );
  }
}