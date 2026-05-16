import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Top-of-home birthday greeting — only shown when today is the user's birthday.
class BirthdayHomeBanner extends StatelessWidget {
  const BirthdayHomeBanner({
    super.key,
    required this.firstName,
    this.onOpenChat,
  });

  final String firstName;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = firstName.trim().isEmpty ? 'there' : firstName.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenChat,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF4A2C35),
                      const Color(0xFF5D1F1A),
                    ]
                  : const [
                      Color(0xFFFFF0E6),
                      Color(0xFFFFE8EF),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? const Color(0xFFE85D3F).withValues(alpha: 0.35)
                  : const Color(0xFFFFD6E0),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE85D3F).withValues(alpha: isDark ? 0.12 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🎂', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Happy Birthday, $name!',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 20,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF5D1F1A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Chechi Puttu Kadai wishes you a wonderful day filled with '
                      'joy and homestyle flavours.',
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.88)
                            : const Color(0xFF7A6A62),
                      ),
                    ),
                    if (onOpenChat != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Tap to open Support Chat →',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE85D3F),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
