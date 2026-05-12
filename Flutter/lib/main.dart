import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/contract_provider.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/contract_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const EveryCheckApp());
}

class EveryCheckApp extends StatelessWidget {
  const EveryCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(AuthService(api))..checkAuth(),
        ),
        ChangeNotifierProvider(
          create: (_) => ContractProvider(ContractService(api)),
        ),
      ],
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.system,
        routes: {
          '/register': (_) => const RegisterScreen(),
        },
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return switch (auth.status) {
      AuthStatus.unknown => const Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      AuthStatus.authenticated => const HomeScreen(),
      AuthStatus.unauthenticated => const OnboardingScreen(),
    };
  }
}
