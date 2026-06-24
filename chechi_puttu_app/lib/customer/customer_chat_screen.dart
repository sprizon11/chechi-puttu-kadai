import 'dart:async';

import 'package:chechi_puttu_app/services/birthday_chat_wish_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomerChatScreen extends StatefulWidget {
  const CustomerChatScreen({super.key});

  @override
  State<CustomerChatScreen> createState() => _CustomerChatScreenState();
}

class _CustomerChatScreenState extends State<CustomerChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _birthdayToday = false;

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
      final threadRef = chechiFirestore
          .collection('support_inbox')
          .doc(uid);
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleMine = isDark
        ? cs.primaryContainer.withValues(alpha: 0.44)
        : const Color(0xFFFFE8EF);
    final bubbleOther = isDark ? cs.surfaceContainerHigh : Colors.white;
    final muted = isDark ? cs.onSurface.withValues(alpha: 0.72) : const Color(0xFF7A6A62);

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Support Chat')),
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
      backgroundColor: isDark ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFFFFF7FA),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFFFF2DD),
              child: Text(
                'CP',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF7A4E2D),
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
                    fontSize: 16,
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
                      'Online',
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
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEF3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFD6E0)),
                ),
                child: Text(
                  'We typically reply in a few minutes. Support hours: 9:00 AM - 10:00 PM.',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF5C4545),
                  ),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Could not load messages.\n${snap.error}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(color: cs.error),
                        ),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return Center(child: CircularProgressIndicator(color: cs.primary));
                  }
                  final docs = snap.data!.docs
                      .where((d) => _showMessage(d.data()))
                      .toList();
                  _scrollToBottom();
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    itemCount: docs.length + (docs.isEmpty ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (docs.isEmpty) {
                        return _bubble(
                          context: context,
                          text: _birthdayToday
                              ? 'Hi! Happy Birthday from Chechi Puttu — how can we help you today?'
                              : 'Hi! Welcome to Chechi Puttu. How can we help you today?',
                          mine: false,
                          bubbleMine: bubbleMine,
                          bubbleOther: bubbleOther,
                          muted: muted,
                          timeLabel: _timeLabel(DateTime.now()),
                        );
                      }
                      final m = docs[i].data();
                      final mine = ((m['sender'] as String?) ?? '').toLowerCase() == 'customer';
                      final isBirthdayWish =
                          BirthdayChatWishService.isBirthdayWishMessage(m);
                      final ts = m['created_at'];
                      final dt = ts is Timestamp ? ts.toDate() : DateTime.now();
                      return Column(
                        crossAxisAlignment: mine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
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
                            context: context,
                            text: (m['text'] as String?) ?? '',
                            mine: mine,
                            bubbleMine: bubbleMine,
                            bubbleOther: bubbleOther,
                            muted: muted,
                            timeLabel: _timeLabel(dt),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? cs.surfaceContainerHigh : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: isDark ? cs.outlineVariant : const Color(0xFFE8E0E4)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: null,
                      icon: Icon(Icons.attach_file_rounded, color: muted),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(user.uid),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          hintText: 'Type a message...',
                          hintStyle: GoogleFonts.poppins(
                            fontSize: 14,
                            color: const Color(0xFFB0A4A8),
                          ),
                        ),
                      ),
                    ),
                    Material(
                      color: const Color(0xFF7C1D1B),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sending ? null : () => _send(user.uid),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: _sending
                              ? const Padding(
                                  padding: EdgeInsets.all(11),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
    required BuildContext context,
    required String text,
    required bool mine,
    required Color bubbleMine,
    required Color bubbleOther,
    required Color muted,
    required String timeLabel,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: mine ? bubbleMine : bubbleOther,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: const Color(0xFFE8E0E4)),
        ),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              text,
              textAlign: mine ? TextAlign.right : TextAlign.left,
              style: GoogleFonts.poppins(
                fontSize: 13.5,
                height: 1.35,
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
                if (mine) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.done_all_rounded, size: 15, color: cs.primary),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
