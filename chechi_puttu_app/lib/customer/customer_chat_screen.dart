import 'dart:async';

import 'package:chechi_puttu_app/services/birthday_chat_wish_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomerChatScreen extends StatefulWidget {
  const CustomerChatScreen({super.key, this.asTab = false});

  /// True when embedded in the main IndexedStack (nav bar visible below).
  final bool asTab;

  @override
  State<CustomerChatScreen> createState() => _CustomerChatScreenState();
}

class _CustomerChatScreenState extends State<CustomerChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _birthdayToday = false;

  static const _primary = Color(0xFF7C1D1B);

  @override
  void initState() {
    super.initState();
    unawaited(_loadBirthdayFlag());
  }

  Future<void> _loadBirthdayFlag() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final isToday =
        await BirthdayChatWishService.instance.isBirthdayTodayForUid(uid);
    if (mounted) setState(() => _birthdayToday = isToday);
  }

  bool _showMessage(Map<String, dynamic> data) {
    if (!BirthdayChatWishService.isBirthdayWishMessage(data)) return true;
    return _birthdayToday;
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send(String uid) async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    setState(() => _sending = true);
    try {
      final threadRef = chechiFirestore.collection('support_inbox').doc(uid);
      await chechiFirestore
          .collection('support_inbox')
          .doc(uid)
          .collection('messages')
          .add({
        'text': text,
        'sender': 'customer',
        'created_at': FieldValue.serverTimestamp(),
      });
      await threadRef.set({
        'customer_uid': uid,
        'customer_name':
            (currentUser?.displayName?.trim().isNotEmpty ?? false)
                ? currentUser!.displayName!.trim()
                : null,
        'customer_mobile':
            (currentUser?.phoneNumber?.trim().isNotEmpty ?? false)
                ? currentUser!.phoneNumber!.trim()
                : null,
        'last_message': text,
        'last_sender': 'customer',
        'last_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'unread_customer_to_admin': FieldValue.increment(1),
      }, SetOptions(merge: true));
      // Push to admin (best-effort; the Firestore chat trigger can't deploy on
      // this named DB, so we notify via callable).
      unawaited(_notifyAdmin(uid, text));
      if (!mounted) return;
      _input.clear();
      _focus.requestFocus();
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to send message. Try again.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _notifyAdmin(String uid, String text) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('notifyChatMessage')
          .call({'customerUid': uid, 'text': text, 'sender': 'customer'});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final scaffoldBg =
        isDark ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFFFAF6F3);
    final bubbleMine =
        isDark ? cs.primaryContainer.withValues(alpha: 0.44) : const Color(0xFFF5E6E0);
    final bubbleOther = isDark ? cs.surfaceContainerHigh : Colors.white;
    final muted =
        isDark ? cs.onSurface.withValues(alpha: 0.55) : const Color(0xFF9B8880);

    // Extra bottom padding when embedded as a tab (floating nav bar is visible)
    final bottomPad = widget.asTab
        ? (82.0 + MediaQuery.of(context).viewPadding.bottom)
        : 0.0;

    if (user == null) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        appBar: _buildAppBar(isDark),
        body: Center(
          child: Text(
            'Please sign in to chat with support.',
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }

    final stream = chechiFirestore
        .collection('support_inbox')
        .doc(user.uid)
        .collection('messages')
        .orderBy('created_at')
        .limit(200)
        .snapshots();

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: _buildAppBar(isDark),
      body: Column(
        children: [
          // Support hours notice
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? cs.primaryContainer.withValues(alpha: 0.18)
                    : const Color(0xFFFFF3EC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? cs.primary.withValues(alpha: 0.3)
                      : const Color(0xFFE8C9B8),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 15, color: _primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'We typically reply in a few minutes · Support hours: 9 AM – 10 PM',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: isDark ? cs.onSurface : const Color(0xFF5C3A2A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Messages list
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Could not load messages.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(color: cs.error),
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return Center(
                      child: CircularProgressIndicator(color: cs.primary));
                }
                final docs = snap.data!.docs
                    .where((d) => _showMessage(d.data()))
                    .toList();
                _scrollToBottom();
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                  itemCount: docs.isEmpty ? 1 : docs.length,
                  itemBuilder: (context, i) {
                    if (docs.isEmpty) {
                      return _bubble(
                        text: _birthdayToday
                            ? 'Hi! Happy Birthday from Chechi Puttu — how can we help you today? 🎂'
                            : 'Hi! Welcome to Chechi Puttu Kadai. How can we help you today?',
                        mine: false,
                        bubbleMine: bubbleMine,
                        bubbleOther: bubbleOther,
                        muted: muted,
                        isDark: isDark,
                        timeLabel: _timeLabel(DateTime.now()),
                      );
                    }
                    final m = docs[i].data();
                    final mine = ((m['sender'] as String?) ?? '').toLowerCase() == 'customer';
                    final isBirthdayWish = BirthdayChatWishService.isBirthdayWishMessage(m);
                    final ts = m['created_at'];
                    final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
                    return Column(
                      crossAxisAlignment:
                          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (isBirthdayWish && !mine && _birthdayToday)
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 4),
                            child: Text(
                              '🎂 Birthday wish from Chechi',
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFE85D3F),
                              ),
                            ),
                          ),
                        _bubble(
                          text: (m['text'] as String?) ?? '',
                          mine: mine,
                          bubbleMine: bubbleMine,
                          bubbleOther: bubbleOther,
                          muted: muted,
                          isDark: isDark,
                          timeLabel: _timeLabel(dt),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Input bar
          Container(
            decoration: BoxDecoration(
              color: isDark ? cs.surfaceContainerHigh : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? cs.outlineVariant.withValues(alpha: 0.4)
                      : const Color(0xFFEDE4DF),
                ),
              ),
            ),
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomPad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: isDark
                          ? cs.surfaceContainerHighest
                          : const Color(0xFFF5F0ED),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(user.uid),
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        hintText: 'Type a message...',
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 13.5,
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sending ? null : () => _send(user.uid),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _sending ? _primary.withValues(alpha: 0.5) : _primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _primary.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      automaticallyImplyLeading: !widget.asTab,
      titleSpacing: widget.asTab ? 16 : 0,
      backgroundColor: isDark ? null : Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFEDE4DF),
        ),
      ),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC23E2B), Color(0xFF7C1D1B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'CP',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chechi Support',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2ED15E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Typically replies in minutes',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF9B8880),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _timeLabel(DateTime d) {
    final h24 = d.hour;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Widget _bubble({
    required String text,
    required bool mine,
    required Color bubbleMine,
    required Color bubbleOther,
    required Color muted,
    required bool isDark,
    required String timeLabel,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 8),
        decoration: BoxDecoration(
          color: mine ? bubbleMine : bubbleOther,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
          border: mine
              ? null
              : Border.all(
                  color: isDark
                      ? cs.outlineVariant.withValues(alpha: 0.4)
                      : const Color(0xFFE8E0DA),
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              text,
              textAlign: mine ? TextAlign.right : TextAlign.left,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                ),
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.done_all_rounded, size: 14, color: _primary),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
