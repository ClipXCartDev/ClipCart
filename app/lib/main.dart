import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/remote_config.dart';
import 'core/token_store.dart';
import 'services/auth_service.dart';
import 'services/billing_service.dart';
import 'services/catalog_service.dart';
import 'services/creator_service.dart';
import 'services/font_service.dart';
import 'state/auth_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RemoteConfig.load(); // resolve API base + flags from the stable config URL
  final tokens = TokenStore();
  final api = ApiClient(tokens);
  final authService = AuthService(api);
  final catalog = CatalogService(api);
  final billing = BillingService(api);
  final creator = CreatorService(api);
  final authController = AuthController(authService, tokens)..bootstrap();

  runApp(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      Provider<CatalogService>.value(value: catalog),
      Provider<BillingService>.value(value: billing),
      Provider<CreatorService>.value(value: creator),
      ChangeNotifierProvider<FontService>(create: (_) => FontService()),
      ChangeNotifierProvider<AuthController>.value(value: authController),
    ],
    child: const ClipCartApp(),
  ));
}
