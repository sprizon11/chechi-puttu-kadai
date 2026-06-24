import 'package:chechi_puttu_app/models/customer_order_type.dart';
import 'package:chechi_puttu_app/theme/chechi_premium.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shown once after sign-in: pick normal, hospital, or corporate ordering.
class OrderTypeSelectionScreen extends StatefulWidget {
  const OrderTypeSelectionScreen({
    super.key,
    required this.onTypeChosen,
  });

  final ValueChanged<CustomerOrderType> onTypeChosen;

  @override
  State<OrderTypeSelectionScreen> createState() =>
      _OrderTypeSelectionScreenState();
}

class _OrderTypeSelectionScreenState extends State<OrderTypeSelectionScreen>
    with SingleTickerProviderStateMixin {
  CustomerOrderType? _selected;
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: ChechiPremium.brandGradient()),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FadeTransition(
                  opacity: _anim,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome to\nChechi Puttu',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 32,
                          height: 1.08,
                          fontWeight: FontWeight.w700,
                          color: ChechiBrand.maroonDeep,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'How would you like to order today?',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          height: 1.45,
                          color: const Color(0xFF7A6A62),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    _typeCard(
                      context,
                      type: CustomerOrderType.normal,
                      icon: Icons.restaurant_menu_rounded,
                      accent: const Color(0xFFE85D3F),
                      delay: 0.05,
                    ),
                    const SizedBox(height: 14),
                    _typeCard(
                      context,
                      type: CustomerOrderType.hospital,
                      icon: Icons.local_hospital_rounded,
                      accent: const Color(0xFF2E7D8E),
                      delay: 0.12,
                    ),
                    const SizedBox(height: 14),
                    _typeCard(
                      context,
                      type: CustomerOrderType.corporate,
                      icon: Icons.business_center_rounded,
                      accent: const Color(0xFF6B4E9B),
                      delay: 0.19,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: FilledButton(
                  onPressed: _selected == null
                      ? null
                      : () => widget.onTypeChosen(_selected!),
                  style: FilledButton.styleFrom(
                    backgroundColor: ChechiBrand.maroonDeep,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Continue',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeCard(
    BuildContext context, {
    required CustomerOrderType type,
    required IconData icon,
    required Color accent,
    required double delay,
  }) {
    final selected = _selected == type;
    final anim = CurvedAnimation(
      parent: _anim,
      curve: Interval(delay, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(anim),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => setState(() => _selected = type),
            child: AnimatedContainer(
              duration: ChechiBrand.normal,
              curve: ChechiBrand.ease,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: 0.85)
                      : ChechiBrand.border,
                  width: selected ? 2 : 1,
                ),
                boxShadow: ChechiPremium.cardShadow(
                  context,
                  elevation: selected ? 1.6 : 0.8,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: accent, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.title,
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ChechiBrand.maroonDeep,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          type.subtitle,
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            height: 1.35,
                            color: const Color(0xFF7A6A62),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: ChechiBrand.fast,
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? accent : Colors.transparent,
                      border: Border.all(
                        color: selected ? accent : const Color(0xFFC9B8A8),
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
