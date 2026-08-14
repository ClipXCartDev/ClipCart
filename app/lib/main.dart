import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/token_store.dart';
import 'services/auth_service.dart';
import 'services/catalog_service.dart';
import 'services/font_service.dart';
import 'state/auth_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final tokens = TokenStore();
  final api = ApiClient(tokens);
  final authService = AuthService(api);
  final catalog = CatalogService(api);
  final authController = AuthController(authService, tokens)..bootstrap();

  runApp(MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      Provider<CatalogService>.value(value: catalog),
      ChangeNotifierProvider<FontService>(create: (_) => FontService()),
      ChangeNotifierProvider<AuthController>.value(value: authController),
    ],
    child: const ClipCartApp(),
  ));
}
