import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// FSSAI licence number for Sai Logabala OPC Pvt. Ltd. (Chechi Puttu Kadai).
///
/// Food business operators must display this on the platform their food is
/// sold through, so it is shown at the foot of every customer-facing page and
/// on the order receipt.
const String kFssaiLicenseNumber = '12426003001180';

/// Legal-entity line shown alongside the licence on the page footers.
const String kFssaiLicenseHolder = 'Sai Logabala OPC Pvt. Ltd.';

/// Footer strip: a divider, the FSSAI licence number, and the licence holder.
///
/// Drop this in as the last child of a page's scroll body. It is deliberately
/// low-contrast so it reads as a legal footnote rather than content.
class FssaiLicenseFooter extends StatelessWidget {
  const FssaiLicenseFooter({
    super.key,
    this.showHolder = true,
    this.padding = const EdgeInsets.fromLTRB(16, 22, 16, 18),
  });

  /// Whether to print the company name under the licence number.
  final bool showHolder;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? const Color(0xFF9E9E9E) : const Color(0xFF8A8A8A);
    final strong = dark ? const Color(0xFFCFCFCF) : const Color(0xFF5A5A5A);
    final line = dark ? const Color(0xFF3A3A3A) : const Color(0xFFE4E0DC);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, thickness: 1, color: line),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _FssaiMark(color: strong),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'License No. $kFssaiLicenseNumber',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: strong,
                  ),
                ),
              ),
            ],
          ),
          if (showHolder) ...[
            const SizedBox(height: 6),
            Text(
              kFssaiLicenseHolder,
              style: GoogleFonts.poppins(fontSize: 11, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// One-line version for tight spaces — receipts, invoices, bill summaries.
class FssaiLicenseLine extends StatelessWidget {
  const FssaiLicenseLine({super.key, this.color, this.fontSize = 10.5});

  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = color ?? (dark ? const Color(0xFF9E9E9E) : const Color(0xFF8A8A8A));
    return Text(
      'FSSAI License No. $kFssaiLicenseNumber',
      style: GoogleFonts.poppins(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: c,
      ),
    );
  }
}

/// The "fssai" wordmark, drawn as text so it stays crisp at any size and
/// needs no extra asset.
class _FssaiMark extends StatelessWidget {
  const _FssaiMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        'fssai',
        style: GoogleFonts.poppins(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}
