import 'dart:async';
import 'package:clipnote_audio/modules/UI/mainEditorUI2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

void main() async {
  // 原生 Splash 交接
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // TODO: 放你的初始化流程（FFI/播放器/設定等）
  // await initStuff();

  FlutterNativeSplash.remove(); // 移除原生 Splash，改由 Flutter 假 Splash 接手
  runApp(const ClipNoteAudioApp());
}

/// App 根元件：先進全螢幕假 Splash，再進編輯器
class ClipNoteAudioApp extends StatelessWidget {
  const ClipNoteAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 可選：狀態列透明，照片更沉浸
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, primarySwatch: Colors.blueGrey),
      home: const _FullBleedSplash(), // 先顯示全螢幕照片
    );
  }
}

/// 全螢幕照片式假 Splash（鋪滿 lib/assets/loading.jpg）
class _FullBleedSplash extends StatefulWidget {
  const _FullBleedSplash({super.key});

  @override
  State<_FullBleedSplash> createState() => _FullBleedSplashState();
}

class _FullBleedSplashState extends State<_FullBleedSplash> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 停留 800ms（或在這裡等待實際初始化 Future 完成後再 _goNext）
    _timer = Timer(const Duration(milliseconds: 800), _goNext);
  }

  void _goNext() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => const MainEditorUI2(),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A0F1C), // 與品牌色一致
      body: DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('lib/assets/loading.jpg'),
            fit: BoxFit.cover, // 關鍵：鋪滿全螢幕
            alignment: Alignment.center, // 可依需求改 topCenter 等
          ),
        ),
        child: SizedBox.expand(),
      ),
    );
  }
}
