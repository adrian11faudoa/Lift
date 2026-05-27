import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'core/constants/app_constants.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/storage/database.dart';
import 'presentation/themes/app_theme.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait (can be unlocked in settings)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize AdMob
  await MobileAds.instance.initialize();

  // Setup dependency injection
  await configureDependencies();

  // Initialize local database
  await AppDatabase.instance.initialize();

  // Initialize notifications
  await NotificationService.instance.initialize();

  runApp(
    const ProviderScope(
      child: IronLogApp(),
    ),
  );
}

class IronLogApp extends ConsumerWidget {
  const IronLogApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router   = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme:      AppTheme.lightTheme,
      darkTheme:  AppTheme.darkTheme,
      themeMode:  themeMode,
      routerConfig: router,
      builder: (context, child) {
        return MediaQuery(
          // Prevent font scaling from breaking layouts
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaleFactor.clamp(0.85, 1.2),
            ),
          ),
          child: child!,
        );
      },
    );
  }
}
