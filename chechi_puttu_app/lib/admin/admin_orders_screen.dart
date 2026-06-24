import 'package:chechi_puttu_app/services/app_refresh.dart';
import 'package:chechi_puttu_app/widgets/app_pull_to_refresh.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:chechi_puttu_app/services/orders_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Admin Orders tab — matches kitchen / dispatch layout (tabs, filters, cards).
class AdminOrdersBody extends StatefulWidget {
  const AdminOrdersBody({super.key});

  @override
  State<AdminOrdersBody> createState() => _AdminOrdersBodyState();
}

class _AdminOrdersBodyState extends State<AdminOrdersBody> {
  static const _maroon = Color(0xFF5D1F1A);

  final OrdersService _orders = OrdersService();
  int _tab = 0;
  String _deliveryLabel = 'All delivery types';
  String _sortLabel = 'Newest';

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    return chechiFirestore
        .collection('orders')
        .orderBy('created_at', descending: true)
        .limit(200)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream() {
    return chechiFirestore
        .collection('users')
        .limit(700)
        .snapshots();
  }

  bool _docMatchesTab(Map<String, dynamic> m, int tab) {
    final s = (m['status'] as String? ?? '').toLowerCase().trim();
    switch (tab) {
      case 0:
        return s == 'placed' || s == 'new' || s.isEmpty;
      case 1:
        return s == 'preparing' || s == 'accepted';
      case 2:
        return s == 'ready';
      case 3:
        return s == 'delivered' || s == 'completed';
      case 4:
        return s == 'cancelled';
      default:
        return false;
    }
  }

  int _countForTab(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, int t) {
    return docs.where((e) => _docMatchesTab(e.data(), t)).length;
  }

  String _relTime(DateTime? t) {
    if (t == null) return '—';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds} secs ago';
    if (d.inMinutes < 60) return '${d.inMinutes} mins ago';
    if (d.inHours < 24) return '${d.inHours} hours ago';
    return '${d.inDays} days ago';
  }

  Future<void> _setStatus(String id, String status) async {
    try {
      await _orders.updateOrderStatus(orderId: id, status: status);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update order status. Please check your connection and try again.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? cs.onSurface.withValues(alpha: 0.7)
        : const Color(0xFF6B5E58);
    final surface = cs.surface;
    final border = cs.outlineVariant;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Center(child: CircularProgressIndicator(color: cs.primary));
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Orders: ${snap.error}',
              style: GoogleFonts.poppins(color: cs.error, height: 1.4),
            ),
          );
        }
        final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        var filtered = docs.where((e) => _docMatchesTab(e.data(), _tab)).toList();
        if (_sortLabel == 'Oldest') {
          filtered = filtered.reversed.toList();
        }

        final tabLabels = <String>[
          'New Orders',
          'Preparing',
          'Ready',
          'Completed',
          'Cancelled',
        ];
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _usersStream(),
          builder: (context, usersSnap) {
            final usersDocs =
                usersSnap.data?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final usersByUid = _buildUserProfilesByUid(usersDocs);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Orders',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          'Manage and receive customer orders.',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        onPressed: () {},
                        icon: Icon(Icons.notifications_outlined, color: cs.onSurface),
                      ),
                      if (_countForTab(docs, 0) > 0)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_countForTab(docs, 0)}',
                              style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Material(
                    color: surface,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.calendar_today_outlined, size: 18, color: cs.onSurface),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: tabLabels.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final n = _countForTab(docs, i);
                  final sel = _tab == i;
                  return ChoiceChip(
                    label: Text(
                      n > 0 ? '${tabLabels[i]} ($n)' : tabLabels[i],
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                        color: sel ? Colors.white : cs.onSurface,
                      ),
                    ),
                    selected: sel,
                    onSelected: (_) => setState(() => _tab = i),
                    selectedColor: _maroon,
                    backgroundColor: surface,
                    side: BorderSide(color: border),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final v = await showModalBottomSheet<String>(
                          context: context,
                          builder: (ctx) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  title: const Text('All delivery types'),
                                  onTap: () => Navigator.pop(ctx, 'All delivery types'),
                                ),
                                ListTile(
                                  title: const Text('Delivery'),
                                  onTap: () => Navigator.pop(ctx, 'Delivery'),
                                ),
                                ListTile(
                                  title: const Text('Pickup'),
                                  onTap: () => Navigator.pop(ctx, 'Pickup'),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (v != null) setState(() => _deliveryLabel = v);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.onSurface,
                        side: BorderSide(color: border),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.restaurant_outlined, size: 18),
                      label: Text(
                        _deliveryLabel,
                        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final v = await showModalBottomSheet<String>(
                        context: context,
                        builder: (ctx) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                title: const Text('Newest'),
                                onTap: () => Navigator.pop(ctx, 'Newest'),
                              ),
                              ListTile(
                                title: const Text('Oldest'),
                                onTap: () => Navigator.pop(ctx, 'Oldest'),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (v != null) setState(() => _sortLabel = v);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(
                      'Sort: $_sortLabel',
                      style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => setState(() {}),
                    style: FilledButton.styleFrom(
                      backgroundColor: _maroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                    label: Text(
                      'Refresh',
                      style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AppPullToRefresh(
                onRefresh: AppRefresh.refreshAdminMenuData,
                child: filtered.isEmpty
                    ? ListView(
                        physics: AppPullToRefresh.scrollPhysics,
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.32,
                            child: Center(
                              child: Text(
                                'No orders in this tab.',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: muted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: AppPullToRefresh.scrollPhysics,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final doc = filtered[i];
                        final m = doc.data();
                        final uid = (m['uid'] as String?) ?? '';
                        final profile = usersByUid[uid];
                        return _AdminOrderCard(
                          docId: doc.id,
                          data: m,
                          customerName: _resolveCustomerName(uid, profile, m),
                          customerPhone: _resolveCustomerPhone(profile, m),
                          relTime: _relTime(_readCreatedTs(m)),
                          tabIndex: _tab,
                          surface: surface,
                          border: border,
                          muted: muted,
                          onAccept: _tab == 0
                              ? () => _setStatus(doc.id, 'preparing')
                              : null,
                          onReject: _tab == 0
                              ? () => _setStatus(doc.id, 'cancelled')
                              : null,
                          onMarkReady: _tab == 1
                              ? () => _setStatus(doc.id, 'ready')
                              : null,
                          onMarkCompleted: _tab == 2
                              ? () => _setStatus(doc.id, 'completed')
                              : null,
                        );
                      },
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  Text(
                    '${filtered.length} ${tabLabels[_tab].toLowerCase()} shown.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontSize: 11.5, color: muted),
                  ),
                  if (_tab == 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: muted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Accept moves order to Preparing. Then use Mark Ready and Mark Completed.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(fontSize: 11, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_tab == 1) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: muted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Tap Mark Ready when food is packed for pickup/delivery.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(fontSize: 11, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_tab == 2) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: muted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Tap Mark Completed after customer receives the order.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(fontSize: 11, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
              ],
            );
          },
        );
      },
    );
  }
}

Map<String, _AdminUserProfile> _buildUserProfilesByUid(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final out = <String, _AdminUserProfile>{};
  for (final d in docs) {
    final uid = d.id;
    if (uid.isEmpty) continue;
    final m = d.data();
    final name = _pickNameCandidate(m);
    final phone = _pickPhoneCandidate(m);
    out[uid] = _AdminUserProfile(name: name, phone: phone);
  }
  return out;
}

String? _pickNameCandidate(Map<String, dynamic> m) {
  String? read(dynamic v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  final candidates = [
    read(m['displayName']),
    read(m['name']),
    read(m['fullName']),
    read(m['username']),
  ];
  for (final c in candidates) {
    if (c == null) continue;
    final normalized = c.toLowerCase();
    if (normalized == 'customer') continue;
    return c;
  }
  return null;
}

String? _pickPhoneCandidate(Map<String, dynamic> m) {
  String? read(dynamic v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  return read(m['mobile']) ?? read(m['authPhone']) ?? read(m['phone']);
}

String _resolveCustomerName(
  String uid,
  _AdminUserProfile? profile,
  Map<String, dynamic> orderMap,
) {
  final orderName = _readTrimmed(orderMap['customer_name']);
  if (orderName != null && orderName.toLowerCase() != 'customer') return orderName;

  final explicitName = profile?.name?.trim();
  if (explicitName != null && explicitName.isNotEmpty) return explicitName;

  final phone = profile?.phone ?? _readTrimmed(orderMap['customer_mobile']) ?? '';
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length >= 4) {
    return 'Customer ${digits.substring(digits.length - 4)}';
  }

  if (uid.isEmpty) return 'Customer';
  final tail = uid.length > 6 ? uid.substring(uid.length - 6) : uid;
  return 'Customer · …$tail';
}

String _resolveCustomerPhone(_AdminUserProfile? profile, Map<String, dynamic> orderMap) {
  final p = profile?.phone?.trim() ?? _readTrimmed(orderMap['customer_mobile']);
  if (p == null || p.isEmpty) return '—';
  return p;
}

String? _readTrimmed(dynamic v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

class _AdminUserProfile {
  const _AdminUserProfile({this.name, this.phone});

  final String? name;
  final String? phone;
}

DateTime _readCreatedTs(Map<String, dynamic> m) {
  final c = m['created_at'];
  if (c is Timestamp) return c.toDate();
  return DateTime.fromMillisecondsSinceEpoch(0);
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    required this.docId,
    required this.data,
    required this.customerName,
    required this.customerPhone,
    required this.relTime,
    required this.tabIndex,
    required this.surface,
    required this.border,
    required this.muted,
    this.onAccept,
    this.onReject,
    this.onMarkReady,
    this.onMarkCompleted,
  });

  final String docId;
  final Map<String, dynamic> data;
  final String customerName;
  final String customerPhone;
  final String relTime;
  final int tabIndex;
  final Color surface;
  final Color border;
  final Color muted;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onMarkReady;
  final VoidCallback? onMarkCompleted;

  String _orderRef() {
    if (docId.length >= 6) {
      return '#ORD${docId.substring(docId.length - 4).toUpperCase()}';
    }
    return '#ORD${docId.toUpperCase()}';
  }

  int _lineTotal(Map<String, dynamic> it) {
    final q = (it['qty'] is int) ? it['qty'] as int : (it['qty'] as num?)?.toInt() ?? 1;
    final p = it['priceRupees'];
    final pr = p is int ? p : (p as num?)?.toInt() ?? 0;
    return pr * q;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final delivery = (data['delivery_line'] as String?) ?? '—';
    final schedule = (data['schedule_line'] as String?)?.trim() ?? '';
    final items = data['items'];
    final list = items is List ? items : const [];
    final total = (data['total_rupees'] is int)
        ? data['total_rupees'] as int
        : (data['total_rupees'] as num?)?.toInt() ?? 0;

    return Material(
      color: surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (tabIndex == 0)
                    _statusChip('NEW', const Color(0xFFFF9800))
                  else if (tabIndex == 1)
                    _statusChip('PREPARING', const Color(0xFF1565C0))
                  else if (tabIndex == 2)
                    _statusChip('READY', const Color(0xFF2E7D32))
                  else
                    const SizedBox.shrink(),
                  const Spacer(),
                  Icon(Icons.schedule_rounded, size: 16, color: const Color(0xFFEA7A2C)),
                  const SizedBox(width: 4),
                  Text(
                    relTime,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFEA7A2C),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _orderRef(),
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              _rowIcon(Icons.person_outline_rounded, customerName, cs.onSurface),
              const SizedBox(height: 4),
              _rowIcon(Icons.phone_outlined, customerPhone, cs.onSurface),
              if (schedule.isNotEmpty) ...[
                const SizedBox(height: 4),
                _rowIcon(
                  Icons.event_available_outlined,
                  schedule,
                  const Color(0xFFEA7A2C),
                ),
              ],
              const SizedBox(height: 4),
              _rowIcon(Icons.location_on_outlined, delivery, cs.onSurface),
              const SizedBox(height: 10),
              Text(
                'Items (${list.length})',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              ...list.map((raw) {
                if (raw is! Map<String, dynamic>) {
                  return const SizedBox.shrink();
                }
                final it = Map<String, dynamic>.from(raw);
                final name = (it['name'] as String?) ?? 'Item';
                final qty = (it['qty'] is int) ? it['qty'] as int : (it['qty'] as num?)?.toInt() ?? 1;
                final line = _lineTotal(it);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: GoogleFonts.poppins(fontSize: 12, color: muted)),
                      Expanded(
                        child: Text(
                          '$name × $qty',
                          style: GoogleFonts.poppins(fontSize: 12, color: cs.onSurface),
                        ),
                      ),
                      Text(
                        '₹$line',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 6),
              CustomPaint(
                painter: _DashPainter(color: border),
                child: const SizedBox(height: 1, width: double.infinity),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'Total Amount',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '₹$total',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFB71C1C),
                    ),
                  ),
                ],
              ),
              if (onAccept != null && onReject != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onAccept,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2E7D32),
                          side: const BorderSide(color: Color(0xFF2E7D32)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          'Accept',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFC62828),
                          side: const BorderSide(color: Color(0xFFC62828)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: Text(
                          'Reject',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (onMarkReady != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onMarkReady,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.restaurant_rounded, size: 18),
                    label: Text(
                      'Mark Ready',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
              if (onMarkCompleted != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onMarkCompleted,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: Text(
                      'Mark Completed',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  static Widget _rowIcon(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color.withValues(alpha: 0.75)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    double x = 0;
    while (x < size.width) {
      final end = (x + dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0), Offset(end, 0), p);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) => oldDelegate.color != color;
}
