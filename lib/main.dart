import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flyteasy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const WebViewScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController controller;

  /// Guard to prevent multiple back navigations firing simultaneously.
  bool _isHandlingBack = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse('https://flyteasy.com'));
  }

  /// Handles the system back button press.
  /// Navigates back in WebView history if possible, otherwise exits.
  Future<void> _handleBackNavigation() async {
    if (_isHandlingBack) return;
    _isHandlingBack = true;

    try {
      if (await controller.canGoBack()) {
        await controller.goBack();
      } else {
        // Root route — exit the app cleanly on Android
        if (Platform.isAndroid) {
          SystemNavigator.pop();
        }
      }
    } finally {
      _isHandlingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        body: SafeArea(child: WebViewWidget(controller: controller)),
      ),
    );
  }
}
