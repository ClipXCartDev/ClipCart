# ClipCart — Mobile app (Flutter)

Sprint S5 (in progress): Sunset Coral theme · auth flow · discover gallery · clip player, wired to the backend API.

## Run
```bash
cd app
flutter pub get
# point at your backend (Android emulator default is 10.0.2.2):
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```
Backend must be running (`cd backend && uvicorn app.main:app --reload`).

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

## Next
- Editor (layer/timeline) + on-device export (ffmpeg_kit_flutter_new + pro_video_editor).
- Search/filters, Saved, Exports, Plans/checkout, Creator mode.
