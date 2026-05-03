import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
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
  static const String _appUrl = 'https://flyteasy.com';
  late final WebViewController controller;
  late final WebViewCookieManager cookieManager;

  bool _isHandlingBack = false;
  bool _isAppleSigningIn = false;
  bool _showNativeAuthButtons = false;
  String _currentUrl = _appUrl;
  Timer? _authStateTimer;

  @override
  void initState() {
    super.initState();
    cookieManager = WebViewCookieManager();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'FlyteasyNativeAppleSignIn',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('JS requested native Apple Sign-In: ${message.message}');
          _handleNativeAppleSignIn();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _currentUrl = url;
              });
            }
            controller.runJavaScript("""
              window.open = function(url) {
                window.location.href = url;
                return window;
              };
            """);
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _currentUrl = url;
              });
            }

            _injectAppleButtonBridge();
            _updateNativeAuthButtonVisibility();
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('Navigating to: ${request.url}');

            if (request.url.contains('appleid.apple.com/auth/authorize')) {
              _handleNativeAppleSignIn();
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_appUrl));

    _authStateTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) {
        if (mounted) {
          _updateNativeAuthButtonVisibility();
        }
      },
    );
  }

  @override
  void dispose() {
    _authStateTimer?.cancel();
    super.dispose();
  }

  Future<void> _updateNativeAuthButtonVisibility() async {
    try {
      final dynamic result = await controller.runJavaScriptReturningResult(r"""
        (() => {
          const url = window.location.href.toLowerCase();
          const pathname = window.location.pathname.toLowerCase();
          const bodyText = (document.body?.innerText || '').toLowerCase();
          const hasEmail = !!document.querySelector('input[type="email"], input[name*="email" i], input[autocomplete="email"]');
          const hasPassword = !!document.querySelector('input[type="password"]');
          const textSignals = [
            'sign in with google',
            'continue with google',
            'sign in with apple',
            'continue with apple',
            'welcome back',
            'forgot password',
            'create account',
            'already have an account',
            'sign up',
            'log in',
            'login'
          ];
          const hasTextSignal = textSignals.some((signal) => bodyText.includes(signal));
          const authPath = [
            '/login', '/signup', '/register', '/sign-up', '/sign_in', '/sign-in',
            '/auth/login', '/auth/signup', '/auth/register'
          ].some((prefix) => pathname === prefix || pathname.startsWith(prefix + '/'));
          return hasEmail || hasPassword || hasTextSignal || authPath ||
            url.includes('/login') || url.includes('/signup') || url.includes('/register') ||
            url.includes('/auth/login') || url.includes('/auth/signup') || url.includes('/auth/register');
        })();
      """);

      final bool shouldShow = result == true || result.toString().toLowerCase().contains('true');
      if (mounted && shouldShow != _showNativeAuthButtons) {
        setState(() {
          _showNativeAuthButtons = shouldShow;
        });
      }
    } catch (e) {
      debugPrint('Failed to update auth button visibility: $e');
    }
  }

  bool get _isAuthPage {
    final uri = Uri.tryParse(_currentUrl);
    final path = uri?.path ?? '';
    const authPrefixes = [
      '/login',
      '/signup',
      '/register',
      '/sign-up',
      '/sign_in',
      '/sign-in',
      '/auth/login',
      '/auth/signup',
      '/auth/register',
    ];

    for (final prefix in authPrefixes) {
      if (path == prefix || path.startsWith('$prefix/')) {
        return true;
      }
    }

    final lowered = _currentUrl.toLowerCase();
    if (lowered.contains('/login') ||
        lowered.contains('/signup') ||
        lowered.contains('/register') ||
        lowered.contains('/auth/login') ||
        lowered.contains('/auth/signup') ||
        lowered.contains('/auth/register')) {
      return true;
    }

    return false;
  }

  Future<void> _injectAppleButtonBridge() async {
    await controller.runJavaScript(r"""
      (() => {
        const channel = window.FlyteasyNativeAppleSignIn;
        if (!channel || typeof channel.postMessage !== 'function') return;
        const isIos = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
          (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
        const bodyText = (document.body?.innerText || '').toLowerCase();
        const hasEmail = !!document.querySelector('input[type="email"], input[name*="email" i], input[autocomplete="email"]');
        const hasPassword = !!document.querySelector('input[type="password"]');
        const authSignals = [
          'sign in / register',
          'sign in/register',
          'sign in with apple',
          'continue with apple',
          'welcome back',
          'forgot password',
          'create account',
          'already have an account',
          'sign up',
          'log in',
          'login'
        ];
        const hasAuthSignals = authSignals.some((signal) => bodyText.includes(signal));
        const authPrefixes = [
          '/login',
          '/signup',
          '/register',
          '/sign-up',
          '/sign_in',
          '/sign-in',
          '/auth/login',
          '/auth/signup',
          '/auth/register'
        ];
        const isAuthPage = authPrefixes.some((prefix) =>
          window.location.pathname === prefix ||
          window.location.pathname.startsWith(prefix + '/')
        ) || hasEmail || hasPassword || hasAuthSignals;

        const getLabel = (element) => {
          return (
            element.innerText ||
            element.textContent ||
            element.getAttribute('aria-label') ||
            element.getAttribute('title') ||
            element.value ||
            ''
          ).trim().toLowerCase();
        };

        const hideElement = (element) => {
          const target = element.closest('button,a,[role="button"],input[type="button"],input[type="submit"]') || element;
          if (target.dataset.flyteasyHiddenAuthButton === 'true') return;
          target.dataset.flyteasyHiddenAuthButton = 'true';
          target.style.display = 'none';
          target.style.visibility = 'hidden';
          target.style.pointerEvents = 'none';
          target.setAttribute('aria-hidden', 'true');
        };

        const selectors = [
          '[data-provider="apple"]',
          '[data-testid="apple-signin"]',
          '[data-test="apple-signin"]',
          '[data-social="apple"]',
          'button.apple-signin',
          'button[data-provider="apple"]'
        ];

        const matchesAppleLabel = (element) => {
          const text = (element.innerText || element.textContent || '').trim().toLowerCase();
          return text.includes('continue with apple') ||
            text.includes('sign in with apple') ||
            text.includes('apple');
        };

        const hookButtons = () => {
          if (!isIos || !isAuthPage) return;
          const found = new Set();

          for (const selector of selectors) {
            for (const element of document.querySelectorAll(selector)) {
              found.add(element);
            }
          }

          for (const button of document.querySelectorAll('button')) {
            if (matchesAppleLabel(button)) {
              found.add(button);
            }
          }

          for (const button of found) {
            hideElement(button);
            if (button.dataset.flyteasyAppleBridgeAttached === 'true') continue;

            button.dataset.flyteasyAppleBridgeAttached = 'true';
            button.addEventListener(
              'click',
              (event) => {
                event.preventDefault();
                event.stopPropagation();
              event.stopImmediatePropagation();
                event.stopPropagation();
                channel.postMessage('apple-button-click');
              },
              true
            );
          }
        };

        hookButtons();

        if (window.__flyteasyAppleBridgeObserver) {
          window.__flyteasyAppleBridgeObserver.disconnect();
        }

        const observer = new MutationObserver(() => hookButtons());
        observer.observe(document.body, { childList: true, subtree: true });
        window.__flyteasyAppleBridgeObserver = observer;
      })();
    """);
  }

  Future<void> _handleNativeAppleSignIn() async {
    if (_isAppleSigningIn) return;

    if (!Platform.isIOS) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Apple Sign-In is currently available on iOS only.'),
          ),
        );
      }
      return;
    }

    final bool isAvailable = await SignInWithApple.isAvailable();
    if (!isAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Apple Sign-In is not available on this device.'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isAppleSigningIn = true;
      });
    }

    try {
      debugPrint('=== Starting Native Apple Sign-In ===');
      final AuthorizationCredentialAppleID credential =
          await SignInWithApple.getAppleIDCredential(
            scopes: [
              AppleIDAuthorizationScopes.email,
              AppleIDAuthorizationScopes.fullName,
            ],
          );

      final String? identityToken = credential.identityToken;
      final String authorizationCode = credential.authorizationCode;
      final String? givenName = credential.givenName;
      final String? familyName = credential.familyName;
      final String? email = credential.email;
      final String userIdentifier = credential.userIdentifier ?? '';

      if (identityToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Apple sign-in did not return the required credentials.',
              ),
            ),
          );
        }
        return;
      }

      await controller.runJavaScript("""
        (async () => {
          const payload = {
            identityToken: ${_jsString(identityToken)},
            authorizationCode: ${_jsString(authorizationCode)},
            userIdentifier: ${_jsString(userIdentifier)},
            givenName: ${_jsString(givenName)},
            familyName: ${_jsString(familyName)},
            email: ${_jsString(email)}
          };

          localStorage.setItem('mobile_apple_identity_token', payload.identityToken);
          localStorage.setItem('mobile_apple_authorization_code', payload.authorizationCode);
          if (payload.userIdentifier) {
            localStorage.setItem('mobile_apple_user_identifier', payload.userIdentifier);
          }
          if (payload.email) {
            localStorage.setItem('mobile_apple_email', payload.email);
          }

          try {
            console.log('=== FLUTTER: Exchanging Apple token with backend ===');
            const response = await fetch('https://flyteasy.com/api/login/apple-login', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              credentials: 'include',
              body: JSON.stringify(payload)
            });
            const data = await response.json();
            console.log('=== FLUTTER: Apple backend response status=' + response.status + ' ===');
            console.log('=== FLUTTER: Apple backend response data ===', JSON.stringify(data));
            if (response.ok) {
              if (data.user) {
                localStorage.setItem('user', JSON.stringify(data.user));
              }
              if (data.token) {
                localStorage.setItem('token', data.token);
              }
              window.location.replace('/');
            } else {
              console.error('=== FLUTTER: Apple backend error ===', JSON.stringify(data));
              window.location.replace('/');
            }
          } catch (e) {
            console.error('=== FLUTTER: Apple token exchange failed ===', e.message || e);
            window.location.replace('/');
          }
        })();
      """);
    } catch (error, stackTrace) {
      debugPrint('Native Apple Sign-In Error: ${error.toString()}');
      debugPrint('Apple Sign-In stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Apple sign-in failed: ${error.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAppleSigningIn = false;
        });
      }
    }
  }

  String _jsString(String? value) {
    if (value == null) {
      return 'null';
    }

    return "'${value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')}'";
  }

  Future<void> _handleBackNavigation() async {
    if (_isHandlingBack) return;
    _isHandlingBack = true;

    try {
      if (await controller.canGoBack()) {
        await controller.goBack();
      } else {
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
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: controller),
              if (_isAuthPage || _showNativeAuthButtons)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: SafeArea(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 18,
                            color: Color(0x22000000),
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isAppleSigningIn
                                  ? null
                                  : _handleNativeAppleSignIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF111111),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: _isAppleSigningIn
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.apple),
                              label: Text(
                                _isAppleSigningIn
                                    ? 'Signing in with Apple...'
                                    : 'Continue with Apple',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
