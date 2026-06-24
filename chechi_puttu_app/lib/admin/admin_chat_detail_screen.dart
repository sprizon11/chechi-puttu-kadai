import 'dart:async';

import 'package:chechi_puttu_app/services/birthday_chat_wish_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Arguments for [AdminChatDetailScreen] (opened from admin chat list).
class AdminChatDetailArgs {
  const AdminChatDetailArgs({
    required this.customerUid,
    required this.peerDisplayName,
    this.peerInitials,
    this.peerMobile,
    required this.avatarBg,
    required this.avatarFg,
    required this.peerOnline,
    required this.contextPreview,
  });

  final String customerUid;
  final String peerDisplayName;
  final String? peerInitials;
  final String? peerMobile;
  final Color avatarBg;
  final Color avatarFg;
  final bool peerOnline;
  final String contextPreview;
}

/// Premium 1:1 support-style chat for a customer (admin view).
class AdminChatDetailScreen extends StatefulWidget {
  const AdminChatDetailScreen({super.key, required this.args});

  final AdminChatDetailArgs args;

  @override
  State<AdminChatDetailScreen> createState() => _AdminChatDetailScreenState();
}

class _AdminChatDetailScreenState extends State<AdminChatDetailScreen> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  /// Bumps to force a fresh Firestore subscription (e.g. after rules deploy).
  int _streamEpoch = 0;
  bool _customerBirthdayToday = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCustomerBirthdayFlag());
  }

  Future<void> _loadCustomerBirthdayFlag() async {
    final isToday = await BirthdayChatWishService.instance
        .isBirthdayTodayForUid(widget.args.customerUid);
    if (mounted) setState(() => _customerBirthdayToday = isToday);
  }

  bool _showMessage(Map<String, dynamic> data) {
    if (!BirthdayChatWishService.isBirthdayWishMessage(data)) return true;
    return _customerBirthdayToday;
  }

  static const _maroon = Color(0xFF7C1D1B);
  static const _softPink = Color(0xFFFFE8EF);
  static const _pageTint = Color(0xFFFFF7FA);

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final threadRef = chechiFirestore
          .collection('support_inbox')
          .doc(widget.args.customerUid);
      await chechiFirestore
          .collection('support_inbox')
          .doc(widget.args.customerUid)
          .collection('messages')
          .add({
            'text': text,
            'sender': 'admin',
            'created_at': FieldValue.serverTimestamp(),
          });
      await threadRef.set({
        'customer_uid': widget.args.customerUid,
        'customer_name': widget.args.peerDisplayName,
        'customer_mobile': widget.args.peerMobile,
        'last_message': text,
        'last_sender': 'admin',
        'last_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'unread_customer_to_admin': 0,
      }, SetOptions(merge: true));
      if (!mounted) return;
      _input.clear();
      _focus.requestFocus();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not send. Deploy Firestore rules for support_inbox, or check your connection.',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _appendQuick(String line) {
    final t = _input.text;
    final spacer = t.isEmpty || t.endsWith(' ') ? '' : ' ';
    _input.text = '$t$spacer$line';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    setState(() {});
    _focus.requestFocus();
  }

  Future<void> _callPeer() async {
    final raw = widget.args.peerMobile?.replaceAll(RegExp(r'\s'), '') ?? '';
    if (raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No phone on file for this customer.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: raw);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Theme.of(context).scaffoldBackgroundColor : _pageTint;
    final muted = isDark
        ? cs.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A6A62);

    final messagesQuery = chechiFirestore
        .collection('support_inbox')
        .doc(widget.args.customerUid)
        .collection('messages')
        .orderBy('created_at', descending: false)
        .limit(200);

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              args: widget.args,
              muted: muted,
              onBack: () => Navigator.pop(context),
              onCall: _callPeer,
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                key: ValueKey(
                  'support_msgs_${widget.args.customerUid}_$_streamEpoch',
                ),
                stream: messagesQuery.snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    final err = snap.error.toString();
                    final isPerm = err.contains('permission-denied');
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 40,
                              color: cs.error.withValues(alpha: 0.85),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              isPerm
                                  ? 'Firestore blocked this chat (permission denied).\n\n'
                                        'Fix: deploy the latest `firestore.rules` from this '
                                        'project, then tap Retry. You must be signed in as '
                                        'the admin account (chechiputtukadai@gmail.com).'
                                  : 'Could not load messages.\n$err',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                color: cs.error,
                                fontSize: 12.5,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () =>
                                  setState(() => _streamEpoch++),
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              label: Text(
                                'Retry',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return Center(
                      child: CircularProgressIndicator(color: cs.primary),
                    );
                  }
                  final docs = snap.data!.docs
                      .where((d) => _showMessage(d.data()))
                      .toList();
                  final pendingWait = _pendingCustomerWait(docs);
                  _scrollToBottom();

                  return ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    children: [
                      if (_customerBirthdayToday)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFFF0E6),
                                  Color(0xFFFFE8EF),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFFD6E0),
                              ),
                            ),
                            child: Text(
                              "🎂 Today is ${widget.args.peerDisplayName}'s birthday — "
                              'a birthday wish was sent automatically.',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF5D1F1A),
                              ),
                            ),
                          ),
                        ),
                      _InfoBanner(muted: muted),
                      const SizedBox(height: 14),
                      _DatePill(label: _todayLabel()),
                      const SizedBox(height: 16),
                      if (docs.isEmpty) ...[
                        _BusinessBubble(
                          text:
                              'Hi! Thanks for choosing Chechi Puttu Kadai. '
                              'How can we help you today?',
                          timeLabel: _nowTimeLabel(),
                          muted: muted,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 10),
                        if (widget.args.contextPreview.trim().isNotEmpty)
                          _CustomerBubble(
                            text: widget.args.contextPreview,
                            timeLabel: _nowTimeLabel(),
                            bubbleBg: isDark
                                ? cs.primaryContainer.withValues(alpha: 0.35)
                                : _softPink,
                            muted: muted,
                          ),
                      ],
                      for (final d in docs) ...[
                        _MessageBubble(
                          data: d.data(),
                          muted: muted,
                          isDark: isDark,
                          cs: cs,
                          showBirthdayLabels: _customerBirthdayToday,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (pendingWait != null)
                        _SlaNudgeCard(wait: pendingWait, muted: muted),
                    ],
                  );
                },
              ),
            ),
            _QuickActions(onTap: _appendQuick),
            const SizedBox(height: 6),
            _ReplyBar(
              controller: _input,
              focusNode: _focus,
              sending: _sending,
              onSend: _send,
              onAttach: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Photo attachments will be available in a future update.',
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom > 0 ? 4 : 10),
          ],
        ),
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    return 'Today, ${now.day}/${now.month}/${now.year}';
  }

  String _nowTimeLabel() {
    final now = DateTime.now();
    final h24 = now.hour;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    final m = now.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Duration? _pendingCustomerWait(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    DateTime? customerAt;
    DateTime? adminAt;
    for (final d in docs) {
      final data = d.data();
      final sender = (data['sender'] as String?) ?? '';
      final ts = data['created_at'];
      if (ts is! Timestamp) continue;
      final at = ts.toDate();
      if (sender == 'customer') {
        customerAt = at;
      } else if (sender == 'admin') {
        adminAt = at;
      }
    }
    if (customerAt == null) return null;
    if (adminAt != null && !customerAt.isAfter(adminAt)) return null;
    final diff = DateTime.now().difference(customerAt);
    return diff.isNegative ? Duration.zero : diff;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.args,
    required this.muted,
    required this.onBack,
    required this.onCall,
  });

  final AdminChatDetailArgs args;
  final Color muted;
  final VoidCallback onBack;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          CircleAvatar(
            radius: 22,
            backgroundColor: args.avatarBg,
            child: args.peerInitials == null || args.peerInitials!.isEmpty
                ? Icon(Icons.person_rounded, color: args.avatarFg)
                : Text(
                    args.peerInitials!,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800,
                      color: args.avatarFg,
                      fontSize: 13,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  args.peerDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: args.peerOnline
                            ? const Color(0xFF2ED15E)
                            : muted.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      args.peerOnline ? 'Online' : 'Away',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _HeaderIconButton(
            icon: Icons.phone_outlined,
            onTap: onCall,
          ),
          const SizedBox(width: 6),
          _HeaderIconButton(
            icon: Icons.more_vert_rounded,
            onTap: () {
              showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (ctx) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Customer',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          'UID: ${args.customerUid}',
                          style: GoogleFonts.poppins(fontSize: 12, color: muted),
                        ),
                        if ((args.peerMobile ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          SelectableText(
                            'Phone: ${args.peerMobile}',
                            style: GoogleFonts.poppins(fontSize: 12, color: muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.surface.withValues(alpha: 0.95),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Icon(icon, size: 20, color: cs.onSurface),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.muted});

  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEF3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD6E0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, size: 18, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'We typically reply in a few minutes. Customer support: '
              '9:00 AM – 10:00 PM.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF5C4545),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _BusinessBubble extends StatelessWidget {
  const _BusinessBubble({
    required this.text,
    required this.timeLabel,
    required this.muted,
    required this.isDark,
  });

  final String text;
  final String timeLabel;
  final Color muted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? cs.surfaceContainerHighest : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
            ),
            border: Border.all(
              color: isDark ? cs.outlineVariant : const Color(0xFFE8E0E4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    height: 1.38,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  timeLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerBubble extends StatelessWidget {
  const _CustomerBubble({
    required this.text,
    required this.timeLabel,
    required this.bubbleBg,
    required this.muted,
  });

  final String text;
  final String timeLabel;
  final Color bubbleBg;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleBg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: _AdminChatDetailScreenState._maroon.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  text,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.poppins(
                    fontSize: 13.5,
                    height: 1.38,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeLabel,
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      Icons.done_all_rounded,
                      size: 15,
                      color: cs.primary.withValues(alpha: 0.85),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.data,
    required this.muted,
    required this.isDark,
    required this.cs,
    required this.showBirthdayLabels,
  });

  final Map<String, dynamic> data;
  final Color muted;
  final bool isDark;
  final ColorScheme cs;
  final bool showBirthdayLabels;

  @override
  Widget build(BuildContext context) {
    final sender = (data['sender'] as String?)?.toLowerCase() ?? 'admin';
    final text = (data['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final isBirthdayWish = BirthdayChatWishService.isBirthdayWishMessage(data);

    final ts = data['created_at'];
    DateTime? at;
    if (ts is Timestamp) at = ts.toDate();
    final timeLabel = at == null ? '' : _fmtTime(at);

    final isAdmin = sender == 'admin';
    if (isAdmin) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isBirthdayWish && showBirthdayLabels)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '🎂 Birthday wish',
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFE85D3F),
                ),
              ),
            ),
          _CustomerBubble(
            text: text,
            timeLabel: timeLabel,
            bubbleBg: isDark
                ? cs.primaryContainer.withValues(alpha: 0.42)
                : _AdminChatDetailScreenState._softPink,
            muted: muted,
          ),
        ],
      );
    }
    return _BusinessBubble(
      text: text,
      timeLabel: timeLabel,
      muted: muted,
      isDark: isDark,
    );
  }

  String _fmtTime(DateTime d) {
    final h24 = d.hour;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}

class _SlaNudgeCard extends StatelessWidget {
  const _SlaNudgeCard({required this.wait, required this.muted});

  final Duration wait;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mins = wait.inMinutes;
    final isLate = mins >= 8;
    final text = mins <= 0
        ? 'New customer message waiting for reply.'
        : 'Customer waiting for $mins min.';
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isLate
              ? cs.errorContainer.withValues(alpha: 0.5)
              : cs.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLate
                ? cs.error.withValues(alpha: 0.3)
                : cs.primary.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isLate ? Icons.warning_amber_rounded : Icons.timer_outlined,
              size: 18,
              color: isLate ? cs.error : cs.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onTap});

  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(String label, IconData icon, String insert) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(insert),
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8EF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFFFD0DF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: cs.primary),
                const SizedBox(width: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6B2F3A),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final canned = <({String label, IconData icon, String insert})>[
      (
        label: 'Track order',
        icon: Icons.location_on_outlined,
        insert: 'Could you share your latest order ID so we can track it?',
      ),
      (
        label: 'Delay apology',
        icon: Icons.access_time_rounded,
        insert: 'Sorry for the delay. We are checking this with the kitchen now.',
      ),
      (
        label: 'Menu share',
        icon: Icons.restaurant_menu_rounded,
        insert: 'Here is today\'s menu — tell us what you would like to order.',
      ),
      (
        label: 'Refund help',
        icon: Icons.currency_rupee_rounded,
        insert: 'We have raised your refund request and will update shortly.',
      ),
      (
        label: 'Address confirm',
        icon: Icons.home_work_outlined,
        insert: 'Please confirm your exact delivery address and landmark.',
      ),
      (
        label: 'Close ticket',
        icon: Icons.check_circle_outline_rounded,
        insert: 'Glad to help. We are marking this issue resolved.',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in canned) chip(c.label, c.icon, c.insert),
        ],
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerHighest : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark ? cs.outlineVariant : const Color(0xFFE8E0E4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onAttach,
              icon: Icon(
                Icons.attach_file_rounded,
                color: cs.onSurfaceVariant,
                size: 22,
              ),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Type a message...',
                  hintStyle: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFFB0A4A8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Material(
              color: _AdminChatDetailScreenState._maroon,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
