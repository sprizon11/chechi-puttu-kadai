import 'package:flutter/material.dart';

/// Shared brand tokens and motion for customer + admin UI.
abstract final class ChechiBrand {
  static const maroon = Color(0xFF7C1D1B);
  static const maroonDeep = Color(0xFF5D1F1A);
  static const cream = Color(0xFFFFF6ED);
  static const creamCard = Color(0xFFFFFCF8);
  static const border = Color(0xFFE4D7C7);
  static const accent = Color(0xFFE85D3F);
  static const gold = Color(0xFFC9A227);
  static const success = Color(0xFF2E7D32);

  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 420);
  static const Curve ease = Curves.easeOutCubic;
}

abstract final class ChechiPremium {
  static List<BoxShadow> cardShadow(BuildContext context, {double elevation = 1}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = dark ? 0.22 : 0.06;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: a * elevation),
        blurRadius: 8 + elevation * 6,
        offset: Offset(0, 2 + elevation * 2),
      ),
      if (!dark)
        BoxShadow(
          color: ChechiBrand.maroon.withValues(alpha: 0.04 * elevation),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
    ];
  }

  static BoxDecoration premiumCard({
    required BuildContext context,
    Color? color,
    double radius = 18,
    bool border = true,
  }) {
    return BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(radius),
      border: border
          ? Border.all(
              color: Theme.of(context).colorScheme.outlineVariant.withValues(
                    alpha: 0.85,
                  ),
            )
          : null,
      boxShadow: cardShadow(context),
    );
  }

  static LinearGradient brandGradient({bool vertical = false}) {
    return LinearGradient(
      begin: vertical ? Alignment.topCenter : Alignment.topLeft,
      end: vertical ? Alignment.bottomCenter : Alignment.bottomRight,
      colors: const [
        Color(0xFFFFF8F0),
        Color(0xFFFFEEE7),
        Color(0xFFFFE4DC),
      ],
    );
  }

  static LinearGradient adminHeaderGradient() {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF5D1F1A),
        Color(0xFF7C1D1B),
        Color(0xFF8B2E28),
      ],
    );
  }
}

/// Gentle scale feedback on tap (buttons, chips, cards without nested taps).
class ChechiPressable extends StatefulWidget {
  const ChechiPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = BorderRadius.zero,
    this.scaleDown = 0.97,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final double scaleDown;
  final bool enabled;

  @override
  State<ChechiPressable> createState() => _ChechiPressableState();
}

class _ChechiPressableState extends State<ChechiPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed && widget.enabled ? widget.scaleDown : 1.0;
    return GestureDetector(
      onTapDown: widget.enabled && widget.onTap != null
          ? (_) => setState(() => _pressed = true)
          : null,
      onTapUp: widget.enabled && widget.onTap != null
          ? (_) => setState(() => _pressed = false)
          : null,
      onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedScale(
        scale: scale,
        duration: ChechiBrand.fast,
        curve: ChechiBrand.ease,
        child: AnimatedOpacity(
          opacity: widget.enabled ? 1 : 0.55,
          duration: ChechiBrand.fast,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fade + slide up when widget first appears (lists, sections).
class ChechiFadeIn extends StatefulWidget {
  const ChechiFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offsetY = 14,
    this.duration = ChechiBrand.normal,
  });

  final Widget child;
  final Duration delay;
  final double offsetY;
  final Duration duration;

  @override
  State<ChechiFadeIn> createState() => _ChechiFadeInState();
}

class _ChechiFadeInState extends State<ChechiFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _ctrl, curve: ChechiBrand.ease);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offsetY / 80),
      end: Offset.zero,
    ).animate(_fade);
    Future<void>.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Stagger helper: delay = index * staggerMs
Duration chechiStagger(int index, {int staggerMs = 45}) {
  return Duration(milliseconds: index.clamp(0, 12) * staggerMs);
}
