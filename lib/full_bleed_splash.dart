import 'dart:async';
import 'package:flutter/material.dart';

class FullBleedSplash extends StatefulWidget {
  const FullBleedSplash({super.key});

  @override
  State<FullBleedSplash> createState() => _FullBleedSplashState();
}

class _FullBleedSplashState extends State<FullBleedSplash> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 停留 800ms（你也可在這裡等實際初始化 Future 完成）
    _timer = Timer(const Duration(milliseconds: 800), _goNext);
  }

  void _goNext() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => const HomePage(), // TODO: 換成你的首頁
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1C),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('lib/assets/loading.jpg'),
            fit: BoxFit.cover, // 關鍵：鋪滿全螢幕
            alignment: Alignment.center, // 可改 topCenter 等
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// DEMO：你的首頁
class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Home')));
  }
}
