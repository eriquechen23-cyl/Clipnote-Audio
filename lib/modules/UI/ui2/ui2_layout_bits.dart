import 'package:flutter/material.dart';

/// 中央頁面通用的可卷動容器（含 Scrollbar）。
/// 注意：不要用在含 ReorderableListView 的頁面（例如軌道頁）。
class ScrollablePane extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const ScrollablePane({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.only(bottom: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(padding: padding, child: child),
    );
  }
}
