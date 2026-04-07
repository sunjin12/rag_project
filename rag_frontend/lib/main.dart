/// RAG Chat 앱 진입점
///
/// Provider 기반 의존성 주입(DI)으로 서비스와 상태 관리를 구성합니다.
/// AppConfig.init()으로 환경 설정을 초기화한 후 앱을 실행합니다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'config/app_config.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'providers/auth_provider.dart';
import 'providers/persona_provider.dart';
import 'providers/chat_provider.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/create_persona_screen.dart';
import 'screens/chat_screen.dart';
import 'models/persona_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env 파일 로드
  await dotenv.load(fileName: '.env');

  // 환경 설정 초기화 (개발 환경 기본값)
  AppConfig.init(environment: Environment.development);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Services
        Provider<Dio>(create: (_) => Dio()),
        ProxyProvider<Dio, ApiService>(
          update: (_, dio, __) => ApiService(dio),
        ),
        ProxyProvider<ApiService, AuthService>(
          update: (_, apiService, __) => AuthService(apiService),
        ),
        
        // Providers
        ChangeNotifierProvider<AuthProvider>(
          create: (context) => AuthProvider(context.read<AuthService>()),
        ),
        ChangeNotifierProxyProvider<AuthProvider, PersonaProvider>(
          create: (context) => PersonaProvider(context.read<ApiService>()),
          update: (context, authProvider, personaProvider) {
            return personaProvider ?? PersonaProvider(context.read<ApiService>());
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, ChatProvider>(
          create: (context) => ChatProvider(context.read<ApiService>()),
          update: (context, authProvider, chatProvider) {
            return chatProvider ?? ChatProvider(context.read<ApiService>());
          },
        ),
      ],
      child: MaterialApp(
        title: 'RAG Chat',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: const SplashScreen(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const HomeScreen(),
          '/create-persona': (context) => const CreatePersonaScreen(),
          '/chat': (context) {
            final persona = ModalRoute.of(context)?.settings.arguments as Persona?;
            return persona != null
                ? ChatScreen(persona: persona)
                : const HomeScreen();
          },
        },
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Initialize auth and check login status
    final authProvider = context.read<AuthProvider>();
    await authProvider.initialize();

    if (mounted) {
      if (authProvider.isLoggedIn) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.chat_rounded,
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              Text(
                'RAG Chat',
                style: Theme.of(context).textTheme.displayLarge!.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Intelligent Conversations',
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
