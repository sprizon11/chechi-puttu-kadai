import 'package:chechi_puttu_app/services/app_refresh.dart';
import 'package:flutter/material.dart';

/// Pull down from the top to refresh scrollable content.
class AppPullToRefresh extends StatelessWidget {
  const AppPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final Color? color;

  /// Use on [ListView], [SingleChildScrollView], [CustomScrollView], etc.
  static const scrollPhysics = AlwaysScrollableScrollPhysics(
    parent: BouncingScrollPhysics(),
  );

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: color ?? const Color(0xFF5D1F1A),
      onRefresh: () => AppRefresh.run(onRefresh),
      child: child,
    );
  }
}
