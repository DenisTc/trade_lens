#!/usr/bin/env sh
# Writes placeholder Firebase configuration when the real, git-ignored
# files are absent (forks, CI). The app detects the stub project id and
# runs on the bundled defaults instead of Remote Config.
set -eu
cd "$(dirname "$0")/../../apps/mobile"
PKG=com.denistc.tradelens
if [ ! -f lib/firebase_options.dart ]; then
  cat > lib/firebase_options.dart <<'DART'
// Stub written by tooling/scripts/firebase_stub.sh. Run `flutterfire configure`
// for the real file (git-ignored).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => const FirebaseOptions(
    apiKey: 'stub',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '0',
    projectId: 'tradelens-stub',
  );
}
DART
  echo "wrote stub lib/firebase_options.dart"
fi
if [ ! -f android/app/google-services.json ]; then
  cat > android/app/google-services.json <<JSON
{
  "project_info": {"project_number": "0", "project_id": "tradelens-stub", "storage_bucket": "tradelens-stub.appspot.com"},
  "client": [{
    "client_info": {"mobilesdk_app_id": "1:000000000000:android:0000000000000000000000", "android_client_info": {"package_name": "$PKG"}},
    "oauth_client": [],
    "api_key": [{"current_key": "stub"}],
    "services": {"appinvite_service": {"other_platform_oauth_client": []}}
  }],
  "configuration_version": "1"
}
JSON
  echo "wrote stub android/app/google-services.json"
fi
if [ ! -f ios/Runner/GoogleService-Info.plist ]; then
  cat > ios/Runner/GoogleService-Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>API_KEY</key><string>stub</string>
  <key>GCM_SENDER_ID</key><string>0</string>
  <key>BUNDLE_ID</key><string>$PKG</string>
  <key>PROJECT_ID</key><string>tradelens-stub</string>
  <key>GOOGLE_APP_ID</key><string>1:000000000000:ios:0000000000000000000000</string>
  <key>IS_ADS_ENABLED</key><false/><key>IS_ANALYTICS_ENABLED</key><false/><key>IS_APPINVITE_ENABLED</key><false/><key>IS_GCM_ENABLED</key><false/><key>IS_SIGNIN_ENABLED</key><false/>
  <key>PLIST_VERSION</key><string>1</string>
</dict></plist>
PLIST
  echo "wrote stub ios/Runner/GoogleService-Info.plist"
fi
