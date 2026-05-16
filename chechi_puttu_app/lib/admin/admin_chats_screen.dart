import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chechi_puttu_app/admin/admin_chat_detail_screen.dart';

class AdminChatsScreen extends StatefulWidget {
  const AdminChatsScreen({super.key});

  @override
  State<AdminChatsScreen> createState() => _AdminChatsScreenState();
}

class _AdminChatsScreenState extends State<AdminChatsScreen> {
  final _searchCtrl = TextEditingController();
  _ChatFilter _filter = _ChatFilter.all;
  bool _broadcasting = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _msgsSub;
  QuerySnapshot<Map<String, dynamic>>? _usersSnap;
  QuerySnapshot<Map<String, dynamic>>? _msgsSnap;
  Object? _usersErr;
  Object? _msgsErr;
  bool _gotUsers = false;
  bool _gotMsgs = false;

  @override
  void initState() {
    super.initState();
    _usersSub = FirebaseFirestore.instance
        .collection('users')
        .limit(700)
        .snapshots()
        .listen(
          (s) => setState(() {
            _usersSnap = s;
            _usersErr = null;
            _gotUsers = true;
          }),
          onError: (e) => setState(() {
            _usersErr = e;
            _usersSnap = null;
            _gotUsers = true;
          }),
        );
    _msgsSub = FirebaseFirestore.instance
        .collection('support_inbox')
        .orderBy('last_at', descending: true)
        .limit(1200)
        .snapshots()
        .listen(
          (s) => setState(() {
            _msgsSnap = s;
            _msgsErr = null;
            _gotMsgs = true;
          }),
          onError: (e) => setState(() {
            _msgsErr = e;
            _msgsSnap = null;
            _gotMsgs = true;
          }),
        );
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _msgsSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openThread(_ChatThread t) async {
    await FirebaseFirestore.instance.collection('support_inbox').doc(t.uid).set({
      'customer_uid': t.uid,
      'unread_customer_to_admin': 0,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminChatDetailScreen(
          args: AdminChatDetailArgs(
            customerUid: t.uid,
            peerDisplayName: t.name,
            peerInitials: t.initials,
            peerMobile: t.mobile,
            avatarBg: t.avatarBg,
            avatarFg: t.avatarFg,
            peerOnline: t.online,
            contextPreview: t.preview,
          ),
        ),
      ),
    );
  }

  Future<void> _openBroadcastDialog(List<_UserLite> users) async {
    if (_broadcasting || users.isEmpty) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Broadcast message',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Type offer/update to send all customers...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || text.isEmpty) return;

    setState(() => _broadcasting = true);
    try {
      final db = FirebaseFirestore.instance;
      const chunkSize = 180; // 2 writes/user -> <= 360 ops per batch
      for (var i = 0; i < users.length; i += chunkSize) {
        final end = (i + chunkSize < users.length) ? i + chunkSize : users.length;
        final chunk = users.sublist(i, end);
        final batch = db.batch();
        for (final u in chunk) {
          final thread = db.collection('support_inbox').doc(u.uid);
          final msgRef = thread.collection('messages').doc();
          batch.set(msgRef, {
            'text': text,
            'sender': 'admin',
            'broadcast': true,
            'created_at': FieldValue.serverTimestamp(),
          });
          batch.set(thread, {
            'customer_uid': u.uid,
            'customer_name': u.displayName,
            'customer_mobile': u.mobile,
            'last_message': text,
            'last_sender': 'admin',
            'last_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
            'unread_customer_to_admin': 0,
          }, SetOptions(merge: true));
        }
        await batch.commit();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Broadcast sent to ${users.length} customers.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Broadcast failed. Try again.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _broadcasting = false);
    }
  }

  Future<void> _openStartChatPicker(List<_UserLite> users) async {
    if (users.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No customers found yet.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    }

    var q = '';
    final picked = await showModalBottomSheet<_UserLite>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final list = users.where((u) {
              if (q.trim().isEmpty) return true;
              final z = q.trim().toLowerCase();
              return ('${u.displayName ?? ''} ${u.mobile ?? ''} ${u.uid}'.toLowerCase())
                  .contains(z);
            }).toList()
              ..sort((a, b) => _nameOfUser(a).compareTo(_nameOfUser(b)));

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Start new chat',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (v) => setLocal(() => q = v),
                      decoration: InputDecoration(
                        hintText: 'Search customer name or mobile...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final u = list[i];
                          final title = _nameOfUser(u);
                          final subtitle = (u.mobile?.trim().isNotEmpty ?? false)
                              ? u.mobile!.trim()
                              : 'UID: ${u.uid}';
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFEAF4FF),
                              child: Text(
                                _initialsFrom(title, u.uid),
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1F5AA0),
                                ),
                              ),
                            ),
                            title: Text(
                              title,
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              subtitle,
                              style: GoogleFonts.poppins(fontSize: 12),
                            ),
                            onTap: () => Navigator.pop(ctx, u),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || picked == null) return;
    final title = _nameOfUser(picked);
    final pal = _avatarPalette(picked.uid);
    _openThread(
      _ChatThread(
        id: picked.uid,
        uid: picked.uid,
        name: title,
        initials: _initialsFrom(title, picked.uid),
        mobile: picked.mobile,
        preview: '',
        tag: 'General Inquiry',
        timeLabel: 'Now',
        unreadCount: 0,
        filter: _ChatFilter.active,
        avatarBg: pal.$1,
        avatarFg: pal.$2,
        lastActivity: DateTime.now(),
        online: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? cs.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A6A62);
    final userDocs = _usersSnap?.docs ?? const [];
    final msgDocs = _msgsSnap?.docs ?? const [];
    final userMap = _usersByUid(userDocs);
    final userList = userMap.values.toList();
    final threads = _buildThreads(userMap, msgDocs);
    final unreadThreads = threads.where((t) => t.unreadCount > 0).toList();
    final unreadTotal = unreadThreads.fold<int>(0, (s, t) => s + t.unreadCount);
    final waitingMins = unreadThreads.isEmpty
        ? 0
        : unreadThreads
                .map((t) => DateTime.now().difference(t.lastActivity).inMinutes)
                .fold<int>(0, (a, b) => a + b) ~/
            unreadThreads.length;

    final filtered = threads.where((t) {
      if (_filter != _ChatFilter.all && t.filter != _filter) return false;
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q.isEmpty) return true;
      return ('${t.name} ${t.preview} ${t.tag} ${t.mobile ?? ''}'.toLowerCase())
          .contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Chats',
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w700,
            fontSize: 26,
            color: cs.onSurface,
          ),
        ),
        actions: [
          _CircleAction(
            icon: _broadcasting ? Icons.hourglass_top_rounded : Icons.campaign_outlined,
            onTap: _broadcasting ? () {} : () => _openBroadcastDialog(userList),
          ),
          const SizedBox(width: 8),
          _CircleAction(icon: Icons.tune_rounded, onTap: () {}),
          const SizedBox(width: 8),
          _CircleAction(
            icon: Icons.add_comment_outlined,
            onTap: () => _openStartChatPicker(userList),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Admin Panel',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search conversations...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: cs.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: cs.primary, width: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    _SlaChip(
                      label: 'Unread',
                      value: '$unreadTotal',
                      color: const Color(0xFFC62828),
                    ),
                    const SizedBox(width: 8),
                    _SlaChip(
                      label: 'Open threads',
                      value: '${unreadThreads.length}',
                      color: const Color(0xFF1565C0),
                    ),
                    const SizedBox(width: 8),
                    _SlaChip(
                      label: 'Avg wait',
                      value: '${waitingMins}m',
                      color: const Color(0xFF2E7D32),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _ChatFilter.values.map((f) {
                  final sel = _filter == f;
                  final c = _countFor(f, threads);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _filter = f),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: sel
                              ? cs.primary.withValues(alpha: 0.92)
                              : cs.surface,
                          border: Border.all(
                            color: sel ? cs.primary : cs.outlineVariant,
                          ),
                          boxShadow: sel
                              ? [
                                  BoxShadow(
                                    color: cs.primary.withValues(alpha: 0.24),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          children: [
                            Text(
                              f.label,
                              style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: sel ? Colors.white : cs.onSurface,
                              ),
                            ),
                            const SizedBox(width: 7),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 170),
                              child: Container(
                                key: ValueKey('${f.name}-$c'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : cs.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '$c',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: sel ? Colors.white : cs.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            if (_usersErr != null || _msgsErr != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: isDark ? 0.35 : 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.error.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    _usersErr != null && _msgsErr != null
                        ? 'Could not read users and chat messages from Firestore. '
                              'Please verify admin access in rules.'
                        : _usersErr != null
                        ? 'Could not read users from Firestore.'
                        : 'Could not read chat messages from Firestore.',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: !_gotUsers || !_gotMsgs
                  ? Center(
                      child: CircularProgressIndicator(color: cs.primary),
                    )
                  : filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _searchCtrl.text.trim().isEmpty
                              ? 'No chats yet. Chats appear when customers send messages.'
                              : 'No conversations match your search.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: muted,
                            height: 1.35,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => Divider(
                        color: cs.outlineVariant.withValues(alpha: 0.7),
                        height: 1,
                      ),
                      itemBuilder: (context, i) {
                        final t = filtered[i];
                        return TweenAnimationBuilder<double>(
                          key: ValueKey('${t.id}-$i'),
                          tween: Tween(begin: 0, end: 1),
                          duration: Duration(milliseconds: 280 + (i * 34)),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, child) => Opacity(
                            opacity: v,
                            child: Transform.translate(
                              offset: Offset(0, (1 - v) * 16),
                              child: child,
                            ),
                          ),
                          child: _ChatTile(thread: t, onTap: () => _openThread(t)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  int _countFor(_ChatFilter f, List<_ChatThread> threads) {
    if (f == _ChatFilter.all) return threads.length;
    return threads.where((t) => t.filter == f).length;
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.thread, required this.onTap});

  final _ChatThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? cs.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A6A62);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: thread.avatarBg,
                child: thread.initials == null
                    ? const Icon(Icons.person_rounded)
                    : Text(
                        thread.initials!,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w800,
                          color: thread.avatarFg,
                        ),
                      ),
              ),
              if (thread.online)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2ED15E),
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        thread.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    _StatusChip(filter: thread.filter),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  thread.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    height: 1.28,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 5),
                _TagChip(label: thread.tag),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                thread.timeLabel,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              const SizedBox(height: 16),
              if (thread.unreadCount > 0)
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B1D1D),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B1D1D).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    '${thread.unreadCount}',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Icon(icon, size: 20, color: cs.onSurface),
      ),
    );
  }
}

class _SlaChip extends StatelessWidget {
  const _SlaChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.filter});

  final _ChatFilter filter;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = switch (filter) {
      _ChatFilter.newChats => (
        bg: const Color(0xFFFFF0F0),
        fg: const Color(0xFFB83B3B),
      ),
      _ChatFilter.active => (
        bg: const Color(0xFFF0FBEF),
        fg: const Color(0xFF2C8A3B),
      ),
      _ChatFilter.orders => (
        bg: const Color(0xFFF2EEFF),
        fg: const Color(0xFF5B42A6),
      ),
      _ChatFilter.resolved => (
        bg: const Color(0xFFEDF8FF),
        fg: const Color(0xFF2F6E93),
      ),
      _ChatFilter.all => (
        bg: cs.primary.withValues(alpha: 0.09),
        fg: cs.primary,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        filter.label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          color: tone.fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

enum _ChatFilter {
  all('All'),
  newChats('New'),
  active('Active'),
  orders('Orders'),
  resolved('Resolved');

  const _ChatFilter(this.label);
  final String label;
}

class _ChatThread {
  const _ChatThread({
    required this.id,
    required this.uid,
    required this.name,
    this.initials,
    this.mobile,
    required this.preview,
    required this.tag,
    required this.timeLabel,
    required this.unreadCount,
    required this.filter,
    required this.avatarBg,
    required this.avatarFg,
    required this.lastActivity,
    this.online = false,
  });

  final String id;
  final String uid;
  final String name;
  final String? initials;
  final String? mobile;
  final String preview;
  final String tag;
  final String timeLabel;
  final int unreadCount;
  final _ChatFilter filter;
  final Color avatarBg;
  final Color avatarFg;
  final DateTime lastActivity;
  final bool online;
}

Map<String, _UserLite> _usersByUid(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> userDocs,
) {
  final users = <String, _UserLite>{};
  for (final d in userDocs) {
    final uid = d.id;
    if (uid.isEmpty) continue;
    final m = d.data();
    users[uid] = _UserLite(
      uid: uid,
      displayName: _readDisplayName(m),
      mobile: (m['mobile'] as String?)?.trim(),
      createdAt: _readTs(m['createdAt']),
      updatedAt: _readTs(m['updatedAt']),
    );
  }
  return users;
}

List<_ChatThread> _buildThreads(
  Map<String, _UserLite> users,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> msgDocs,
) {
  final byUid = <String, _MsgAgg>{};
  for (final d in msgDocs) {
    final m = d.data();
    final uid = d.id;
    if (uid.isEmpty) continue;
    final agg = byUid.putIfAbsent(uid, () => _MsgAgg(uid: uid));
    final sender = (m['last_sender'] as String?)?.trim().toLowerCase() ?? 'customer';
    final text = (m['last_message'] as String?)?.trim() ?? '';
    final at =
        _readTs(m['last_at']) ??
        _readTs(m['updated_at']) ??
        _readTs(m['created_at']) ??
        DateTime(2000);
    final unreadRaw = m['unread_customer_to_admin'];
    final unread = unreadRaw is int ? unreadRaw : (unreadRaw as num?)?.toInt() ?? 0;

    agg.totalMessages = unread > 0 ? unread : 1;
    agg.customerMessages = unread;
    agg.latestAt = at;
    agg.latestSender = sender;
    agg.latestText = text;
    agg.threadName = _readThreadName(m);
    agg.threadMobile = _readThreadMobile(m);
  }

  final now = DateTime.now();
  final threads = <_ChatThread>[];
  for (final e in byUid.entries) {
    final uid = e.key;
    final agg = e.value;
    final user = users[uid];
    final activity = agg.latestAt;
    final displayName = user?.displayName?.trim() ?? agg.threadName?.trim();
    final tail = uid.length > 6 ? uid.substring(uid.length - 6) : uid;
    final mobile = (user?.mobile?.trim().isNotEmpty ?? false)
        ? user?.mobile?.trim()
        : agg.threadMobile?.trim();
    final digits = (mobile ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final name = (displayName == null || displayName.isEmpty)
        ? (digits.length >= 4 ? 'Customer ${digits.substring(digits.length - 4)}' : 'Customer · $tail')
        : displayName;
    final filter = _deriveFilter(agg, now);
    int unreadCount = agg.customerMessages;
    if (unreadCount > 99) unreadCount = 99;
    final preview = _buildPreview(agg);
    final tag = _buildTag(agg);
    final pal = _avatarPalette(uid);
    threads.add(
      _ChatThread(
        id: uid,
        uid: uid,
        name: name,
        initials: _initialsFrom(name, uid),
        mobile: mobile,
        preview: preview,
        tag: tag,
        timeLabel: _formatChatTime(activity, now),
        unreadCount: unreadCount,
        filter: filter,
        avatarBg: pal.$1,
        avatarFg: pal.$2,
        lastActivity: activity,
        online: now.difference(activity) <= const Duration(hours: 18),
      ),
    );
  }
  threads.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  return threads;
}

String _nameOfUser(_UserLite u) {
  final n = u.displayName?.trim();
  if (n != null && n.isNotEmpty) return n;
  final digits = (u.mobile ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length >= 4) {
    return 'Customer ${digits.substring(digits.length - 4)}';
  }
  final tail = u.uid.length > 6 ? u.uid.substring(u.uid.length - 6) : u.uid;
  return 'Customer · $tail';
}

String _buildPreview(_MsgAgg agg) {
  if (agg.latestText.trim().isEmpty) return 'Start a new conversation.';
  return agg.latestText.trim();
}

String _buildTag(_MsgAgg agg) {
  final s = agg.latestText.toLowerCase();
  if (s.contains('order') || s.contains('delivery') || s.contains('track')) {
    return 'Order Support';
  }
  if (s.contains('thank') || s.contains('resolved') || s.contains('done')) {
    return 'Feedback';
  }
  return 'General Inquiry';
}

_ChatFilter _deriveFilter(_MsgAgg agg, DateTime now) {
  final recency = now.difference(agg.latestAt);
  final s = agg.latestText.toLowerCase();
  if (agg.latestSender == 'customer' && recency <= const Duration(days: 2)) {
    return _ChatFilter.newChats;
  }
  if (s.contains('thank') || s.contains('resolved') || s.contains('done')) {
    return _ChatFilter.resolved;
  }
  if (s.contains('order') || s.contains('delivery') || s.contains('track')) {
    return _ChatFilter.orders;
  }
  return _ChatFilter.active;
}

String _initialsFrom(String name, String uid) {
  final parts = name
      .split(RegExp(r'\s+'))
      .where((e) => e.trim().isNotEmpty)
      .toList();
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  if (parts.isNotEmpty && parts[0].length >= 2) {
    return parts[0].substring(0, 2).toUpperCase();
  }
  final alnum = uid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  if (alnum.length >= 2) return alnum.substring(0, 2).toUpperCase();
  return uid.isNotEmpty ? uid[0].toUpperCase() : '?';
}

(Color, Color) _avatarPalette(String uid) {
  const palettes = [
    (Color(0xFFFFF4EC), Color(0xFF995B2D)),
    (Color(0xFFEFF8EE), Color(0xFF2E7D32)),
    (Color(0xFFEAF4FF), Color(0xFF1F5AA0)),
    (Color(0xFFF6EDFF), Color(0xFF6B3EA8)),
    (Color(0xFFFFEFF2), Color(0xFF9C3E58)),
  ];
  final h = uid.hashCode.abs();
  return palettes[h % palettes.length];
}

String? _readDisplayName(Map<String, dynamic> m) {
  String? read(dynamic v) {
    if (v is! String) return null;
    final t = v.trim();
    if (t.isEmpty) return null;
    if (t.toLowerCase() == 'customer') return null;
    return t;
  }

  return read(m['displayName']) ??
      read(m['name']) ??
      read(m['fullName']) ??
      read(m['username']);
}

DateTime? _readTs(dynamic v) {
  if (v is Timestamp) return v.toDate();
  return null;
}

String? _readThreadName(Map<String, dynamic> m) {
  for (final key in const [
    'customer_name',
    'customerName',
    'name',
    'displayName',
  ]) {
    final v = m[key];
    if (v is String) {
      final t = v.trim();
      if (t.isNotEmpty && t.toLowerCase() != 'customer') return t;
    }
  }
  return null;
}

String? _readThreadMobile(Map<String, dynamic> m) {
  for (final key in const [
    'customer_mobile',
    'customerMobile',
    'mobile',
    'phone',
    'phoneNumber',
  ]) {
    final v = m[key];
    if (v is String) {
      final t = v.trim();
      if (t.isNotEmpty) return t;
    }
  }
  return null;
}

String _formatChatTime(DateTime d, DateTime now) {
  if (d.year <= 2001) return '—';
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'Now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) {
    final h24 = d.hour;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
  if (diff.inHours < 48) return 'Yesterday';
  if (diff.inDays < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[d.weekday - 1];
  }
  return '${d.day}/${d.month}/${d.year.toString().substring(2)}';
}

class _UserLite {
  const _UserLite({
    required this.uid,
    required this.displayName,
    required this.mobile,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uid;
  final String? displayName;
  final String? mobile;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class _MsgAgg {
  _MsgAgg({required this.uid});

  final String uid;
  int totalMessages = 0;
  int customerMessages = 0;
  DateTime latestAt = DateTime(2000);
  String latestSender = 'customer';
  String latestText = '';
  String? threadName;
  String? threadMobile;
}
