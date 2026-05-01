# Apple Sign-In Setup For Flyteasy

This project now includes the Flutter-side Apple Sign-In bridge in [lib/main.dart](/Users/kappale_muthalali/Downloads/flyteasy_mobile%20copy/lib/main.dart) and the iOS entitlement in [ios/Runner/Runner.entitlements](/Users/kappale_muthalali/Downloads/flyteasy_mobile%20copy/ios/Runner/Runner.entitlements).

You still need to finish the Apple Developer portal and backend work before Apple Sign-In can succeed end to end.

## 1. What is already implemented in this repo

- The app shows a native `Continue with Apple` button on the login page.
- The WebView intercepts Apple login button clicks and Apple auth URLs.
- Native iOS Sign in with Apple is launched with the Flutter `sign_in_with_apple` package.
- The app sends the Apple credentials to `POST https://flyteasy.com/api/login/apple-login`.
- On success, the app reloads the website so the web app can pick up the authenticated session.

## 2. Values used by this app

- Bundle ID: `io.velense.fteasy`
- Team ID in Xcode project: `9YKNK9956R`
- Website domain: `flyteasy.com`
- Backend Apple login endpoint expected by the app: `https://flyteasy.com/api/login/apple-login`
If you want different endpoint paths, update them in [lib/main.dart](/Users/kappale_muthalali/Downloads/flyteasy_mobile%20copy/lib/main.dart).

## 3. Apple Developer portal setup

### Step 3.1: Enable Sign in with Apple on the app ID

1. Sign in to [Apple Developer](https://developer.apple.com/account/).
2. Open `Certificates, Identifiers & Profiles`.
3. Open `Identifiers`.
4. Find the App ID for bundle ID `io.velense.fteasy`.
5. Edit the App ID.
6. Enable `Sign in with Apple`.
7. Save the change.

Why this matters:
Apple will not return valid credentials to your iOS app unless the app identifier itself is enabled for the capability.

### Step 3.2: Regenerate or refresh provisioning profiles

1. Open the provisioning profile used by the Runner target.
2. Regenerate it after enabling `Sign in with Apple`.
3. Download and install the updated profile if you manage signing manually.
4. In Xcode, confirm the Runner target is signed with a profile that includes the new capability.

Why this matters:
Your release build in this repo uses manual signing for Release and Profile. Old profiles often cause entitlement mismatch errors during archive or App Store upload.

### Step 3.3: Enable the Xcode capability

1. Open [ios/Runner.xcworkspace](/Users/kappale_muthalali/Downloads/flyteasy_mobile%20copy/ios/Runner.xcworkspace).
2. Select the `Runner` target.
3. Open `Signing & Capabilities`.
4. Click `+ Capability`.
5. Add `Sign in with Apple`.

Why this matters:
The repo now includes `com.apple.developer.applesignin` in [ios/Runner/Runner.entitlements](/Users/kappale_muthalali/Downloads/flyteasy_mobile%20copy/ios/Runner/Runner.entitlements), but Xcode should also show the capability on the target so your local signing configuration stays aligned.

### Step 3.4: Decide whether you need a Services ID

For the native iOS flow implemented in this repo, a `Services ID` is not always required.

You do need a `Services ID` if:

- your backend exchanges Apple authorization codes with Apple
- your backend uses Apple web auth configuration
- you want the same Apple sign-in identity shared with a website flow

You may not need a `Services ID` if:

- your iOS app only sends the Apple `identityToken` to your backend
- your backend only verifies that JWT with Apple’s public keys and then creates its own session

If you need a `Services ID`, create it like this:

1. In Apple Developer, open `Identifiers`.
2. Click `+`.
3. Create a `Services ID`.
4. Use a stable identifier such as `com.flyteasy.signin` or `io.velense.fteasy.service`.
5. Open that Services ID after creation.
6. Enable `Sign in with Apple`.
7. Click `Configure`.
8. Add domain `flyteasy.com`.
9. Add return URL `https://flyteasy.com/api/login/apple/callback`.
10. Save.

Why this matters:
Apple’s official setup for websites and backend-integrated flows uses a Services ID, associated domains, and a return URL. Apple documents this in its Sign in with Apple web configuration guidance.

### Step 3.5: Create a Sign in with Apple private key

1. In Apple Developer, open `Keys`.
2. Click `+`.
3. Create a new key with `Sign in with Apple` enabled.
4. Associate it with the primary app ID for `io.velense.fteasy`.
5. Download the `.p8` file once.
6. Record the `Key ID`.

Keep these values safe:

- `Team ID`
- `Key ID`
- private key `.p8`
- App ID / Bundle ID
- Services ID, if you created one

Why this matters:
Your backend uses these values when it needs to generate Apple client secrets or exchange authorization codes with Apple.

## 4. Backend work required to make login succeed

This repo does not contain the `flyteasy.com` backend, so the most important remaining work is server-side.

### Step 4.1: Create `POST /api/login/apple-login`

Your backend should accept JSON like:

```json
{
  "identityToken": "APPLE_ID_TOKEN",
  "authorizationCode": "APPLE_AUTH_CODE",
  "userIdentifier": "APPLE_USER_ID",
  "givenName": "FIRST_NAME",
  "familyName": "LAST_NAME",
  "email": "EMAIL_IF_FIRST_LOGIN"
}
```

### Step 4.2: Verify the Apple identity token

At minimum, verify:

- the JWT signature matches Apple’s public keys
- `iss` is Apple
- `aud` matches your expected app identifier or service identifier
- the token is not expired
- `sub` is present and stable

Why this matters:
The `sub` value is the durable Apple user identifier you should use to link the Apple account to your internal user record.

### Step 4.3: Handle first login vs repeat login

Apple only shares `email`, `givenName`, and `familyName` the first time the user authorizes your app.

Your backend must:

- store the Apple `sub` / user identifier permanently
- store the first returned email if present
- not assume name or email will be present on later logins
- support users who choose Apple relay email addresses

### Step 4.4: Create the normal Flyteasy session

After Apple token verification:

1. Find an existing user by Apple `sub`, or by confirmed email if you support linking.
2. Create the user if needed.
3. Issue the same auth cookie or session your web app already uses after password or Google login.
4. Return JSON similar to the Google endpoint:

```json
{
  "user": {},
  "token": "OPTIONAL_APP_TOKEN"
}
```

Why this matters:
The Flutter app reloads the WebView after calling `/api/login/apple-login`. The web app must already recognize the returned cookie or stored token at that point.

### Step 4.5: Add the callback route only if your backend needs it

If your backend architecture uses the Services ID redirect flow, implement:

- `GET` or `POST https://flyteasy.com/api/login/apple/callback`

Use the same URL that you registered in Apple Developer.

If your backend only validates the native `identityToken` directly and does not use the code exchange flow, this callback may not need much logic. Keep the route in place anyway if your Apple configuration references it.

## 5. Flutter and iOS commands to run locally

From the project root:

```bash
flutter pub get
cd ios
pod install
cd ..
flutter clean
flutter run
```

If CocoaPods is already in sync, `pod install` may just confirm the new plugin integration.

## 6. Testing checklist

### Device testing

Test on a real iPhone signed into an Apple account.

Checklist:

1. Open the app.
2. Go to the login page.
3. Tap `Continue with Apple`.
4. Complete Face ID or Touch ID.
5. Confirm the app calls `/api/login/apple-login`.
6. Confirm the backend returns success and sets cookies.
7. Confirm the WebView lands on the logged-in homepage.

### Repeat-login testing

1. Sign in once and create the account.
2. Log out.
3. Sign in again with Apple.
4. Confirm login still works even if Apple does not resend email or name.

### Negative-path testing

Check these cases too:

1. User cancels Apple sign-in.
2. Device does not support Apple sign-in.
3. Backend rejects token.
4. Provisioning profile is missing entitlement.
5. Apple returns relay email.

## 7. Common issues

### `invalid_client`

Usually means the backend is using the wrong client identifier, wrong key, wrong Team ID, or wrong Services ID configuration.

### `aud` mismatch

Usually means the backend expected a different audience than the one Apple signed into the token. Make sure the backend expects the same identifier used by your native flow and Apple configuration.

### Works in Debug but not Release

Usually means the Release provisioning profile was not regenerated with the Sign in with Apple capability.

### Email is missing

This is normal after the user’s first authorization. Your backend must not depend on Apple resending email every time.

## 8. Official references

- [About Sign in with Apple](https://developer.apple.com/help/account/capabilities/about-sign-in-with-apple)
- [Configure Sign in with Apple for the web](https://developer.apple.com/help/account/configure-app-capabilities/configure-sign-in-with-apple-for-the-web)
- [Configuring your environment for Sign in with Apple](https://developer.apple.com/documentation/signinwithapple/configuring-your-environment-for-sign-in-with-apple)
- [sign_in_with_apple package on pub.dev](https://pub.dev/packages/sign_in_with_apple)
