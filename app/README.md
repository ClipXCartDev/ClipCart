# ClipCart — Mobile app (Flutter)

Sprint S5 (in progress): Sunset Coral theme · auth flow · discover gallery · clip player, wired to the backend API.

## Run
```bash
cd app
flutter create .          # generate android/ios/web platform folders (first time)
flutter pub get
# put a Roboto.ttf in assets/fonts/ (see that folder's README)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1   # emulator
# real device: use your PC's LAN IP, e.g. http://192.168.1.7:8000/api/v1
```
Backend must be running (`cd backend && uvicorn app.main:app --host 0.0.0.0 --port 8000`).

### Android build config (apply after `flutter create .`)
Verified building an APK needs these (already set in the committed `android/` config):
- `android/app/build.gradle.kts` → `minSdk = 24`, `compileSdk = 36`
- `android/gradle.properties` → add `kotlin.incremental=false` (avoids a Windows cache-lock error)
- `android/build.gradle.kts` → in the first `subprojects {}` block, force plugins to SDK 36:
  ```kotlin
  afterEvaluate {
      val androidExt = project.extensions.findByName("android")
      if (androidExt != null) { androidExt.withGroovyBuilder { "compileSdkVersion"(36) } }
  }
  ```
Uses `ffmpeg_kit_flutter_new` 4.6.2 (downloads FFmpeg libs at build time — keep internet on for the first build).

## Structure
```
lib/
  core/      theme (coral), api client (Dio + JWT refresh), token store, config
  models/    user, clip
  services/  auth_service, catalog_service
  state/     auth_controller (Provider/ChangeNotifier)
  features/  auth (splash/onboarding/login/register), home (discover+shell), player
  widgets/   primary_button, clip_card
  app.dart   MaterialApp + GoRouter (auth-aware redirect)
```

## Done
- Coral theme (light + dark), Google + email auth, device binding sent on login.
- Auth-gated routing (splash → onboarding/login → home).
- Discover gallery (GET /clips) → tap → full-screen clip player (GET /clips/{slug}).

## Editor (S5)
Full layer editor wired into the clip player ("Use template" → `/editor`):
- **Multi-timed subtitles** — different lines at different timestamps (RangeSlider start–end), each with its own font/color/size, shown on a timeline track.
- **Custom font upload** — pick `.ttf/.otf` at runtime; registered for live preview (FontLoader) and used by FFmpeg export (`drawtext fontfile=`).
- **Logo overlay** + live time-synced preview (`video_player`).
- **On-device MP4 export** via `ffmpeg_kit_flutter_new` (`drawtext enable='between(t,start,end)'` per line + `overlay`), saved to app docs.

> ⚠️ Add a default font: place `Roboto.ttf` in `assets/fonts/` (see that folder's README).
> `pro_video_editor` is included for richer visual editing (trim/transitions/filters) and can replace the custom timeline later.

## Next
- Search/filters, Saved, Exports, Plans/checkout screens · Creator mode (upload/author) · S6 Web · S7 Admin.
