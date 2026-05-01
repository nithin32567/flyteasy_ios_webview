import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  static const String _googleIosClientId =
      '349556100233-5qlvfbfrhgq0qac61u0qg6gslbcfo54o.apps.googleusercontent.com';
  static const String _googleServerClientId =
      '349556100233-b90kg0pptdoarmrh5le62h3lr59c5g34.apps.googleusercontent.com';
  late final WebViewController controller;
  late final WebViewCookieManager cookieManager;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: _googleIosClientId,
    scopes: ['email', 'profile'],
    serverClientId: _googleServerClientId,
  );

  bool _isHandlingBack = false;
  bool _isGoogleSigningIn = false;
  bool _isAppleSigningIn = false;
  String _currentUrl = _appUrl;

  @override
  void initState() {
    super.initState();
    cookieManager = WebViewCookieManager();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'FlyteasyNativeGoogleSignIn',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('JS requested native Google Sign-In: ${message.message}');
          _handleNativeGoogleSignIn();
        },
      )
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

            _injectGoogleButtonBridge();
            _injectAppleButtonBridge();
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('Navigating to: ${request.url}');

            if (request.url.contains('accounts.google.com/o/oauth2') ||
                request.url.contains('accounts.google.com/v3/signin') ||
                request.url.contains('gsiwebsdk=3')) {
              _handleNativeGoogleSignIn();
              return NavigationDecision.prevent;
            }

            if (request.url.contains('appleid.apple.com/auth/authorize')) {
              _handleNativeAppleSignIn();
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_appUrl));
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

    return false;
  }

  Future<void> _injectGoogleButtonBridge() async {
    await controller.runJavaScript(r"""
      (() => {
        const channel = window.FlyteasyNativeGoogleSignIn;
        if (!channel || typeof channel.postMessage !== 'function') return;
        const isIos = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
          (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
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
        );

        const hideGoogleButton = (button) => {
          if (!isIos || !isAuthPage) return;
          button.style.display = 'none';
          button.style.visibility = 'hidden';
          button.style.pointerEvents = 'none';
        };

        const hookButtons = () => {
          const buttons = Array.from(document.querySelectorAll('button'));
          for (const button of buttons) {
            const label = (button.innerText || button.textContent || '').trim().toLowerCase();
            if (!label.includes('continue with google')) continue;

             hideGoogleButton(button);
            if (button.dataset.flyteasyNativeBridgeAttached === 'true') continue;

            button.dataset.flyteasyNativeBridgeAttached = 'true';
            button.addEventListener(
              'click',
              (event) => {
                event.preventDefault();
                event.stopPropagation();
                event.stopImmediatePropagation();
                channel.postMessage('google-button-click');
              },
              true
            );
          }
        };

        hookButtons();

        if (window.__flyteasyGoogleBridgeObserver) {
          window.__flyteasyGoogleBridgeObserver.disconnect();
        }

        const observer = new MutationObserver(() => hookButtons());
        observer.observe(document.body, { childList: true, subtree: true });
        window.__flyteasyGoogleBridgeObserver = observer;
      })();
    """);
  }

  Future<void> _injectAppleButtonBridge() async {
    await controller.runJavaScript(r"""
      (() => {
        const channel = window.FlyteasyNativeAppleSignIn;
        if (!channel || typeof channel.postMessage !== 'function') return;

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
            if (button.dataset.flyteasyAppleBridgeAttached === 'true') continue;

            button.dataset.flyteasyAppleBridgeAttached = 'true';
            button.addEventListener(
              'click',
              (event) => {
                event.preventDefault();
                event.stopPropagation();
                event.stopImmediatePropagation();
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

  Future<void> _handleNativeGoogleSignIn() async {
    if (_isGoogleSigningIn) return;

    if (mounted) {
      setState(() {
        _isGoogleSigningIn = true;
      });
    }

    try {
      debugPrint('=== Starting Native Google Sign-In ===');
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
      final String? accessToken = googleAuth.accessToken;

      debugPrint('idToken present: ${idToken != null}');
      debugPrint('accessToken present: ${accessToken != null}');

      if (idToken != null || accessToken != null) {
        await controller.runJavaScript("""
          (async () => {
            const accessToken = ${_jsString(accessToken)};
            const idToken = ${_jsString(idToken)};

            if (accessToken) {
              localStorage.setItem('mobile_auth_token', accessToken);
            }
            if (idToken) {
              localStorage.setItem('mobile_id_token', idToken);
            }

            try {
              console.log('=== FLUTTER: Exchanging Google token with backend ===');
              const response = await fetch('https://flyteasy.com/api/login/google-login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                credentials: 'include',
                body: JSON.stringify({
                  accessToken,
                  token: idToken
                })
              });
              const data = await response.json();
              console.log('=== FLUTTER: Backend response status=' + response.status + ' ===');
              console.log('=== FLUTTER: Backend response data ===', JSON.stringify(data));
              if (response.ok) {
                console.log('=== FLUTTER: Login SUCCESS ===');
                if (data.user) {
                  localStorage.setItem('user', JSON.stringify(data.user));
                }
                if (data.token) {
                  localStorage.setItem('token', data.token);
                }
                console.log('=== FLUTTER: Forcing full reload to home ===');
                window.location.replace('/');
              } else {
                console.error('=== FLUTTER: Backend error ===', JSON.stringify(data));
                console.log('=== FLUTTER: Falling back to mobile auth bridge reload ===');
                window.location.replace('/');
              }
            } catch (e) {
              console.error('=== FLUTTER: Token exchange failed ===', e.message || e);
              console.log('=== FLUTTER: Falling back to mobile auth bridge reload after exception ===');
              window.location.replace('/');
            }
          })();
        """);
        debugPrint('Native Login Success: Token sent to backend for exchange.');
      } else {
        debugPrint('ERROR: both idToken and accessToken are null');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Google sign-in did not return a token.'),
            ),
          );
        }
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
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleSigningIn = false;
        });
      }
    }
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
              if (_isAuthPage)
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
                              onPressed:
                                  (_isGoogleSigningIn || _isAppleSigningIn)
                                      ? null
                                      : _handleNativeGoogleSignIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF1F1F1F),
                                elevation: 0,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(
                                    color: Color(0xFFDADCE0),
                                  ),
                                ),
                              ),
                              icon: _isGoogleSigningIn
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.login),
                              label: Text(
                                _isGoogleSigningIn
                                    ? 'Signing in with Google...'
                                    : 'Continue with Google',
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed:
                                  (_isGoogleSigningIn || _isAppleSigningIn)
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
