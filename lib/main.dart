import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'data/db.dart';
import 'data/file_store.dart';
import 'data/settings_repository.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'src/rust/frb_generated.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await FileStore().cleanupTempCache();
  final db = AppDatabase();
  final initialSettings = await SettingsRepository(db).load();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(initialSettings),
      ],
      child: const JScanApp(),
    ),
  );
}

class JScanApp extends ConsumerWidget {
  const JScanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      appSettingsProvider.select((s) => s.themeMode),
    );
    final onboardingDone = ref.watch(
      appSettingsProvider.select((s) => s.onboardingDone),
    );

    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      home: onboardingDone ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
