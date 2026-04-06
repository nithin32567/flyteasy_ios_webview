import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
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

  /// Native Google Sign-In instance
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '349556100233-b90kg0pptdoarmrh5le62h3lr59c5g34.apps.googleusercontent.com',
  );

  /// Guard to prevent multiple back navigations firing simultaneously.
  bool _isHandlingBack = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent(
          "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            // Overriding window.open to force same-window navigation if needed,
            // though we now intercept Google Auth separately.
            controller.runJavaScript("""
              window.open = function(url) {
                window.location.href = url;
                return window;
              };
            """);
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('Navigating to: ${request.url}');

            // Intercept Google Login attempts and trigger native sign-in
            if (request.url.contains('accounts.google.com/o/oauth2') ||
                request.url.contains('accounts.google.com/v3/signin') ||
                request.url.contains('gsiwebsdk=3')) {
              _handleNativeGoogleSignIn();
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse('https://flyteasy.com'));
  }

  /// Handles Native Google Sign-In and passes the token to the WebView
  Future<void> _handleNativeGoogleSignIn() async {
    try {
      debugPrint('=== Starting Native Google Sign-In ===');
      // Clear any cached state from previous sign-in attempts
      try {
        await _googleSignIn.signOut();
        await _googleSignIn.disconnect();
      } catch (_) {}
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      debugPrint('Sign-in result: account=${account?.email}');

      if (account == null) {
        debugPrint('Sign-in cancelled by user or returned null');
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await account.authentication;
      final String? idToken = googleAuth.idToken;

      debugPrint('idToken present: ${idToken != null}');

      if (idToken != null) {
        // Directly call the backend API to exchange the Google token
        // This bypasses the web app's mobile auth bridge entirely
        await controller.runJavaScript("""
          (async () => {
            try {
              console.log('=== FLUTTER: Exchanging Google token with backend ===');
              const response = await fetch('https://flyteasy.com/api/login/google-login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify({ token: '$idToken' })
              });
              const data = await response.json();
              console.log('=== FLUTTER: Backend response status=' + response.status + ' ===');
              console.log('=== FLUTTER: Backend response data ===', JSON.stringify(data));
              if (response.ok) {
                console.log('=== FLUTTER: Login SUCCESS ===');
                // Store user data in localStorage so the web app recognises the session
                if (data.user) {
                  localStorage.setItem('user', JSON.stringify(data.user));
                }
                if (data.token) {
                  localStorage.setItem('token', data.token);
                }
                // Force a full page reload (not SPA navigation) so the app
                // re-initialises with the authenticated session cookies
                console.log('=== FLUTTER: Forcing full reload to home ===');
                window.location.replace('/');
              } else {
                console.error('=== FLUTTER: Backend error ===', JSON.stringify(data));
                alert('Login failed: ' + (data.message || data.error || 'Unknown error'));
              }
            } catch (e) {
              console.error('=== FLUTTER: Token exchange failed ===', e.message || e);
              alert('Login error: ' + (e.message || e));
            }
          })();
        """);
        debugPrint('Native Login Success: Token sent to backend for exchange.');
      } else {
        debugPrint('ERROR: idToken is null');
      }
    } catch (error, stackTrace) {
      debugPrint('Native Google Sign-In Error: ${error.toString()}');
      debugPrint('Error type: ${error.runtimeType}');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: ${error.toString()}')),
        );
      }
    }
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
