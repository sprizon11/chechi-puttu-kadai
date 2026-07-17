import 'package:chechi_puttu_app/theme/chechi_premium.dart';
import 'package:flutter/material.dart';

/// Motion primitives built on the [ChechiBrand] timing tokens so screens
/// animate with one voice instead of ad-hoc durations per widget.
///
/// Every primitive here collapses to a no-op when the platform asks for
/// reduced motion, so that setting is honoured without per-call checks.
bool chechiReduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Fade + rise used whenever content first appears. [delay] staggers siblings;
/// keep the step small (~40ms) so a list feels alive rather than slow.
class ChechiReveal extends StatefulWidget {
  const ChechiReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.from = const Offset(0, 0.06),
  });

  final Widget child;
  final Duration delay;

  /// Start offset as a fraction of the child's own size.
  final Offset from;

  /// Staggers by [index], capped so long lists do not crawl.
  factory ChechiReveal.staggered({
    Key? key,
    required int index,
    required Widget child,
    Offset from = const Offset(0, 0.06),
  }) {
    final steps = index.clamp(0, 8);
    return ChechiReveal(
      key: key,
      delay: Duration(milliseconds: 40 * steps),
      from: from,
      child: child,
    );
  }

  @override
  State<ChechiReveal> createState() => _ChechiRevealState();
}

class _ChechiRevealState extends State<ChechiReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: ChechiBrand.normal,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
      return;
    }
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (chechiReduceMotion(context)) return widget.child;
    final curved = CurvedAnimation(parent: _c, curve: ChechiBrand.ease);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.from,
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// Press feedback for cards and tiles that are tappable but are not buttons.
/// Use on surfaces that already read as tappable; it adds weight, not meaning.
class ChechiTapScale extends StatefulWidget {
  const ChechiTapScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<ChechiTapScale> createState() => _ChechiTapScaleState();
}

class _ChechiTapScaleState extends State<ChechiTapScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (chechiReduceMotion(context)) {
      return GestureDetector(onTap: widget.onTap, child: widget.child);
    }
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: ChechiBrand.fast,
        curve: ChechiBrand.ease,
        child: widget.child,
      ),
    );
  }
}

/// Shared push transition. Routes slide in from the trailing edge and the
/// outgoing page fades back slightly, which reads as depth without the
/// full-screen white flash of the default Material push.
/// Drop-in for `MaterialPageRoute` — same `builder` contract, so swapping the
/// class name is the whole change at a call site.
class ChechiPageRoute<T> extends PageRouteBuilder<T> {
  ChechiPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: ChechiBrand.normal,
        reverseTransitionDuration: ChechiBrand.fast,
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (chechiReduceMotion(context)) return child;

    final enter = CurvedAnimation(parent: animation, curve: ChechiBrand.ease);
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: ChechiBrand.ease,
    );

    return FadeTransition(
      opacity: enter,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(enter),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-0.03, 0),
          ).animate(exit),
          child: child,
        ),
      ),
    );
  }
}
