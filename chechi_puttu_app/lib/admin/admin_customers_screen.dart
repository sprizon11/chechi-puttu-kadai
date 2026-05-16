import 'dart:async';

import 'package:chechi_puttu_app/services/app_refresh.dart';
import 'package:chechi_puttu_app/services/birthday_chat_wish_service.dart';
import 'package:chechi_puttu_app/widgets/app_pull_to_refresh.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:chechi_puttu_app/admin/admin_customer_map_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// Admin Customers tab — merges Firestore `users` (saved profiles) with
/// `orders` (counts & last order). Deploy rules so admin can read `users`.
class AdminCustomersBody extends StatefulWidget {
  const AdminCustomersBody({super.key});

  @override
  State<AdminCustomersBody> createState() => _AdminCustomersBodyState();
}

class _AdminCustomersBodyState extends State<AdminCustomersBody> {
  final _search = TextEditingController();
  String _sortLabel = 'Newest';
  _CustomerSegment _segment = _CustomerSegment.all;

  static const _maroon = Color(0xFF7C1D1B);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;

  QuerySnapshot<Map<String, dynamic>>? _usersSnap;
  QuerySnapshot<Map<String, dynamic>>? _ordersSnap;
  Object? _usersErr;
  Object? _ordersErr;
  bool _gotUsers = false;
  bool _gotOrders = false;
  String? _deletingUid;

  @override
  void initState() {
    super.initState();
    _usersSub = FirebaseFirestore.instance
        .collection('users')
        .limit(500)
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
    _ordersSub = FirebaseFirestore.instance
        .collection('orders')
        .orderBy('created_at', descending: true)
        .limit(500)
        .snapshots()
        .listen(
          (s) => setState(() {
            _ordersSnap = s;
            _ordersErr = null;
            _gotOrders = true;
          }),
          onError: (e) => setState(() {
            _ordersErr = e;
            _ordersSnap = null;
            _gotOrders = true;
          }),
        );
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _ordersSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _openFilterSheet() async {
    final picked = await showModalBottomSheet<_CustomerSegment>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text(
                    'Filter customers',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(ctx).colorScheme.onSurface,
                    ),
                  ),
                ),
                for (final s in _CustomerSegment.values)
                  ListTile(
                    title: Text(
                      s.label,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    trailing: _segment == s
                        ? Icon(Icons.check_rounded, color: _maroon)
                        : null,
                    onTap: () => Navigator.pop(ctx, s),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) setState(() => _segment = picked);
  }

  Future<void> _contactSupport() async {
    final uri = Uri.parse(
      'mailto:support@chechiputtukadai.com?subject=Admin%20—%20Customers',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openCustomerMapScreen(_CustomerAgg c) async {
    if (c.latitude == null || c.longitude == null) {
      await _openLocationForCustomer(c);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => AdminCustomerMapScreen(
          customerName: c.displayName,
          latitude: c.latitude!,
          longitude: c.longitude!,
          addressLine: c.locationLine,
        ),
      ),
    );
  }

  Future<void> _openLocationForCustomer(_CustomerAgg c) async {
    final line = c.locationLine.trim();
    if (line.isEmpty || line == '—') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No location available for this customer.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
      return;
    }
    final uri = (c.latitude != null && c.longitude != null)
        ? Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${c.latitude},${c.longitude}&travelmode=driving',
          )
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(line)}',
          );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not open map for this location.',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  Future<void> _openCustomerDetails(_CustomerAgg c) async {
    final cs = Theme.of(context).colorScheme;
    final confirmDelete = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              20 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.displayName,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Customer details',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                _InfoRow(label: 'Mobile', value: c.phoneDisplay),
                _InfoRow(label: 'UID', value: c.uid),
                _InfoRow(label: 'Orders', value: '${c.orderCount}'),
                _InfoRow(
                  label: 'First order',
                  value: c.firstOrder == null ? '—' : _formatMediumDate(c.firstOrder!),
                ),
                _InfoRow(
                  label: 'Last order',
                  value: c.lastOrder == null ? '—' : _formatMediumDate(c.lastOrder!),
                ),
                if (c.latitude != null && c.longitude != null)
                  _InfoRow(
                    label: 'Coordinates',
                    value:
                        '${c.latitude!.toStringAsFixed(6)}, ${c.longitude!.toStringAsFixed(6)}',
                  ),
                if (c.latitude != null && c.longitude != null) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _openCustomerMapScreen(c),
                    borderRadius: BorderRadius.circular(14),
                    child: Ink(
                      height: 132,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                        color: cs.surfaceContainerLowest,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _CustomerLocationMapPreview(
                              latitude: c.latitude!,
                              longitude: c.longitude!,
                            ),
                            IgnorePointer(
                              child: Container(
                                alignment: Alignment.bottomRight,
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Color(0x66000000),
                                    ],
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Tap to enlarge & directions',
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openCustomerMapScreen(c),
                  icon: const Icon(Icons.location_on_outlined),
                  label: Text(
                    c.locationLine.trim().isEmpty ? 'No location' : c.locationLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(
                    'Delete Customer',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            ),
          ),
        );
      },
    );

    if (confirmDelete == true && mounted) {
      await _confirmDeleteCustomer(c);
    }
  }

  Future<void> _confirmDeleteCustomer(_CustomerAgg c) async {
    if (_deletingUid != null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(
            'Delete customer?',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'This will delete ${c.displayName} profile from Firestore. This action cannot be undone.',
            style: GoogleFonts.poppins(fontSize: 13.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Delete',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
    if (yes != true || !mounted) return;

    setState(() => _deletingUid = c.uid);
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('adminDeleteCustomer');
      await fn.call({'uid': c.uid});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted ${c.displayName} account and all customer data.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = (e.message?.trim().isNotEmpty ?? false)
          ? e.message!.trim()
          : 'Delete failed. Please check admin permissions.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.poppins()),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Delete failed. Try again.',
            style: GoogleFonts.poppins(),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingUid = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final muted = theme.brightness == Brightness.dark
        ? cs.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A6A62);

    if (!_gotUsers || !_gotOrders) {
      return Center(
        child: CircularProgressIndicator(color: cs.primary),
      );
    }

    final userDocs = _usersSnap?.docs ?? const [];
    final orderDocs = _ordersSnap?.docs ?? const [];
    final aggs = _mergeCustomers(userDocs, orderDocs);
    final metrics = _CustomerMetrics.from(aggs);
    final filtered = _applySegment(aggs, _segment);
    final q = _search.text.trim().toLowerCase();
    final searched = q.isEmpty
        ? filtered
        : filtered
            .where((c) {
              final name = c.displayName.toLowerCase();
              final loc = c.locationLine.toLowerCase();
              final uid = c.uid.toLowerCase();
              final mob = (c.mobile ?? '').toLowerCase();
              return name.contains(q) ||
                  loc.contains(q) ||
                  uid.contains(q) ||
                  mob.contains(q);
            })
            .toList();
    _sortCustomers(searched, _sortLabel);

    return AppPullToRefresh(
      onRefresh: AppRefresh.refreshAdminMenuData,
      child: SingleChildScrollView(
        physics: AppPullToRefresh.scrollPhysics,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: cs.outlineVariant),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          cs.surface.withValues(alpha: 0.96),
                          cs.surfaceContainerHighest.withValues(alpha: 0.42),
                        ]
                      : [
                        const Color(0xFFFFFCF8),
                        const Color(0xFFF9F1E7),
                      ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Customer Studio',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 31,
                          fontWeight: FontWeight.w700,
                          color: _maroon,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        '${searched.length} visible',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Search, segment, and act on customer behavior with one premium dashboard view.',
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                ),
                if (_usersErr != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Could not load user profiles. Deploy updated Firestore rules '
                    'so admins can read `users`.\n$_usersErr',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: cs.error,
                      height: 1.35,
                    ),
                  ),
                ],
                if (_ordersErr != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Could not load orders (order counts may be incomplete).\n'
                    '$_ordersErr',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: cs.error,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search by name, mobile, location, or uid...',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 12.5,
                      color: muted.withValues(alpha: 0.85),
                    ),
                    prefixIcon: Icon(Icons.search_rounded, color: muted, size: 22),
                    filled: true,
                    fillColor: cs.surfaceContainerLowest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cs.primary, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openFilterSheet,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.onSurface,
                          side: BorderSide(color: cs.outlineVariant),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: Icon(Icons.filter_list_rounded, color: muted, size: 18),
                        label: Text(
                          'Segment Filter',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PopupMenuButton<String>(
                        onSelected: (v) => setState(() => _sortLabel = v),
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 'Newest', child: Text('Newest')),
                          PopupMenuItem(value: 'Oldest', child: Text('Oldest')),
                          PopupMenuItem(value: 'Most orders', child: Text('Most orders')),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.swap_vert_rounded, size: 18, color: muted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Sort: $_sortLabel',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.2,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: muted,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _CustomerMetricTile(
                      icon: Icons.groups_2_outlined,
                      iconBg: const Color(0xFFFFF0E6),
                      iconColor: const Color(0xFFEA7A2C),
                      label: 'Total Customers',
                      value: '${metrics.total}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CustomerMetricTile(
                      icon: Icons.person_add_alt_1_outlined,
                      iconBg: const Color(0xFFE8F5E9),
                      iconColor: const Color(0xFF2E7D32),
                      label: 'New This Month',
                      value: '${metrics.newThisMonth}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _CustomerMetricTile(
                      icon: Icons.bolt_outlined,
                      iconBg: const Color(0xFFE3F2FD),
                      iconColor: const Color(0xFF1565C0),
                      label: 'Active Customers',
                      value: '${metrics.active}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(
                          () => _segment = _CustomerSegment.birthdayToday,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        child: _CustomerMetricTile(
                          icon: Icons.cake_outlined,
                          iconBg: const Color(0xFFFFE8EF),
                          iconColor: const Color(0xFFE85D3F),
                          label: 'Birthday Today',
                          value: '${metrics.birthdaysToday}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SegmentPill(
                  label: _CustomerSegment.all.label,
                  selected: _segment == _CustomerSegment.all,
                  onTap: () => setState(() => _segment = _CustomerSegment.all),
                ),
                const SizedBox(width: 8),
                _SegmentPill(
                  label: _CustomerSegment.birthdayToday
                      .labelWithCount(metrics.birthdaysToday),
                  selected: _segment == _CustomerSegment.birthdayToday,
                  onTap: () =>
                      setState(() => _segment = _CustomerSegment.birthdayToday),
                ),
                const SizedBox(width: 8),
                _SegmentPill(
                  label: _CustomerSegment.newThisMonth.label,
                  selected: _segment == _CustomerSegment.newThisMonth,
                  onTap: () => setState(() => _segment = _CustomerSegment.newThisMonth),
                ),
                const SizedBox(width: 8),
                _SegmentPill(
                  label: _CustomerSegment.active.label,
                  selected: _segment == _CustomerSegment.active,
                  onTap: () => setState(() => _segment = _CustomerSegment.active),
                ),
                const SizedBox(width: 8),
                _SegmentPill(
                  label: _CustomerSegment.repeat.label,
                  selected: _segment == _CustomerSegment.repeat,
                  onTap: () => setState(() => _segment = _CustomerSegment.repeat),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Customer Directory',
            style: GoogleFonts.playfairDisplay(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _segment == _CustomerSegment.birthdayToday
                ? '${searched.length} member${searched.length == 1 ? '' : 's'} '
                    'celebrating birthday today '
                    '(${metrics.birthdaysToday} total with DOB on file).'
                : 'Tap any customer to view full profile and delete options.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: muted,
            ),
          ),
          const SizedBox(height: 10),
          if (searched.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Text(
                'No customers match your current filters.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < searched.length; i++) ...[
                  TweenAnimationBuilder<double>(
                    key: ValueKey('${searched[i].uid}-$i'),
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 180 + (i * 28)),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, child) => Opacity(
                      opacity: v,
                      child: Transform.translate(
                        offset: Offset(0, (1 - v) * 10),
                        child: child,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CustomerListTile(
                        customer: searched[i],
                        muted: muted,
                        onSurface: cs.onSurface,
                        deleting: _deletingUid == searched[i].uid,
                        onTap: () => _openCustomerDetails(searched[i]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.support_agent_rounded, color: muted, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Need help handling customer requests?',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _contactSupport,
                  child: Text(
                    'Contact Support',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: _maroon,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}

enum _CustomerSegment {
  all,
  birthdayToday,
  newThisMonth,
  active,
  repeat;

  String labelWithCount(int count) => switch (this) {
        all => 'All customers',
        birthdayToday => count > 0 ? "Birthday today ($count)" : 'Birthday today',
        newThisMonth => 'New this month',
        active => 'Active (30 days)',
        repeat => 'Repeat buyers',
      };

  String get label => labelWithCount(0);
}

class _CustomerMetrics {
  const _CustomerMetrics({
    required this.total,
    required this.birthdaysToday,
    required this.newThisMonth,
    required this.active,
    required this.repeat,
  });

  final int total;
  final int birthdaysToday;
  final int newThisMonth;
  final int active;
  final int repeat;

  factory _CustomerMetrics.from(List<_CustomerAgg> list) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final windowStart = now.subtract(const Duration(days: 30));

    var nBirthdays = 0;
    var nNew = 0;
    var nActive = 0;
    var nRepeat = 0;
    for (final c in list) {
      if (c.isBirthdayToday) nBirthdays++;
      final newByOrder = c.firstOrder != null &&
          !c.firstOrder!.isBefore(monthStart);
      final newByProfile = c.profileCreatedAt != null &&
          !c.profileCreatedAt!.isBefore(monthStart);
      if (newByOrder || newByProfile) nNew++;

      final activeByOrder = c.lastOrder != null &&
          !c.lastOrder!.isBefore(windowStart);
      final activeByProfile = (c.profileUpdatedAt != null &&
              !c.profileUpdatedAt!.isBefore(windowStart)) ||
          (c.profileCreatedAt != null &&
              !c.profileCreatedAt!.isBefore(windowStart));
      if (activeByOrder || activeByProfile) nActive++;

      if (c.orderCount >= 2) nRepeat++;
    }
    return _CustomerMetrics(
      total: list.length,
      birthdaysToday: nBirthdays,
      newThisMonth: nNew,
      active: nActive,
      repeat: nRepeat,
    );
  }
}

class _CustomerAgg {
  _CustomerAgg({
    required this.uid,
    required this.displayName,
    this.mobile,
    required this.locationLine,
    this.latitude,
    this.longitude,
    this.orderCount = 0,
    this.lastOrder,
    this.firstOrder,
    this.profileCreatedAt,
    this.profileUpdatedAt,
    this.dateOfBirth,
  });

  final String uid;
  final String displayName;
  final String? mobile;
  String locationLine;
  double? latitude;
  double? longitude;
  int orderCount;
  DateTime? lastOrder;
  DateTime? firstOrder;
  final DateTime? profileCreatedAt;
  final DateTime? profileUpdatedAt;
  final String? dateOfBirth;

  bool get isBirthdayToday =>
      BirthdayChatWishService.isBirthdayToday(dateOfBirth);

  DateTime get _newestActivity {
    var best = DateTime.fromMillisecondsSinceEpoch(0);
    for (final t in [lastOrder, profileUpdatedAt, profileCreatedAt]) {
      if (t != null && t.isAfter(best)) best = t;
    }
    return best;
  }

  String get phoneDisplay {
    final m = mobile?.trim();
    if (m != null && m.isNotEmpty) return m;
    if (uid.length < 6) return '—';
    final tail = uid.substring(uid.length - 4);
    return '+91 ···· ···· $tail';
  }

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      final a = parts[0].isNotEmpty ? parts[0][0] : '';
      final b = parts[1].isNotEmpty ? parts[1][0] : '';
      if (a.isNotEmpty && b.isNotEmpty) {
        return '${a.toUpperCase()}${b.toUpperCase()}';
      }
    }
    if (parts.isNotEmpty && parts[0].length >= 2) {
      return parts[0].substring(0, 2).toUpperCase();
    }
    if (uid.isEmpty) return '?';
    final alnum = uid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (alnum.length >= 2) {
      return alnum.substring(0, 2).toUpperCase();
    }
    return uid.substring(0, 1).toUpperCase();
  }
}

List<_CustomerAgg> _mergeCustomers(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> userDocs,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> orderDocs,
) {
  final map = <String, _CustomerAgg>{};

  for (final d in userDocs) {
    final uid = d.id;
    if (uid.isEmpty) continue;
    final m = d.data();
    final rawName = (m['displayName'] as String?)?.trim();
    final name = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : 'Customer';
    final mobile = (m['mobile'] as String?)?.trim();
    final loc = _locationFromUserMap(m);
    final coords = _coordsFromUserMap(m);
    final created = _readFirestoreTs(m['createdAt']);
    final updated = _readFirestoreTs(m['updatedAt']);
    final dob = (m['dateOfBirth'] as String?)?.trim();
    map[uid] = _CustomerAgg(
      uid: uid,
      displayName: name,
      mobile: mobile,
      locationLine: loc,
      latitude: coords.$1,
      longitude: coords.$2,
      orderCount: 0,
      lastOrder: null,
      firstOrder: null,
      profileCreatedAt: created,
      profileUpdatedAt: updated,
      dateOfBirth: dob != null && dob.isNotEmpty ? dob : null,
    );
  }

  for (final d in orderDocs) {
    final m = d.data();
    final uid = _readUid(m);
    if (uid.isEmpty) continue;
    final existing = map[uid];
    if (existing == null) continue;
    final t = _readCreatedAt(m);
    final line = (m['delivery_line'] as String?)?.trim();
    final loc = (line == null || line.isEmpty) ? '—' : line;

    existing.orderCount++;
    if (t != null) {
      if (existing.lastOrder == null || t.isAfter(existing.lastOrder!)) {
        existing.lastOrder = t;
        if (loc != '—') existing.locationLine = loc;
      }
      if (existing.firstOrder == null || t.isBefore(existing.firstOrder!)) {
        existing.firstOrder = t;
      }
    }
  }

  final list = map.values.toList();
  list.sort((a, b) => b._newestActivity.compareTo(a._newestActivity));
  return list;
}

DateTime? _readFirestoreTs(dynamic v) {
  if (v is Timestamp) return v.toDate();
  return null;
}

String _locationFromUserMap(Map<String, dynamic> m) {
  final loc = (m['location'] as String?)?.trim();
  if (loc != null && loc.isNotEmpty) return loc;
  final addr = m['addresses'];
  if (addr is Map) {
    for (final k in ['home', 'office', 'other']) {
      final s = addr[k] as String?;
      if (s != null && s.trim().isNotEmpty) return s.trim();
    }
  }
  return '—';
}

(double?, double?) _coordsFromUserMap(Map<String, dynamic> m) {
  final geo = m['location_geo'];
  if (geo is GeoPoint) {
    return (geo.latitude, geo.longitude);
  }
  double? readNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
  final lat = readNum(m['location_lat']) ?? readNum(m['latitude']) ?? readNum(m['lat']);
  final lng =
      readNum(m['location_lng']) ?? readNum(m['longitude']) ?? readNum(m['lng']);
  return (lat, lng);
}

List<_CustomerAgg> _applySegment(
  List<_CustomerAgg> all,
  _CustomerSegment seg,
) {
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month);
  final windowStart = now.subtract(const Duration(days: 30));
  switch (seg) {
    case _CustomerSegment.all:
      return List.of(all);
    case _CustomerSegment.birthdayToday:
      return all.where((c) => c.isBirthdayToday).toList();
    case _CustomerSegment.newThisMonth:
      return all
          .where((c) {
            final byOrder = c.firstOrder != null &&
                !c.firstOrder!.isBefore(monthStart);
            final byProfile = c.profileCreatedAt != null &&
                !c.profileCreatedAt!.isBefore(monthStart);
            return byOrder || byProfile;
          })
          .toList();
    case _CustomerSegment.active:
      return all.where((c) {
        final byOrder = c.lastOrder != null &&
            !c.lastOrder!.isBefore(windowStart);
        final byProfile = (c.profileUpdatedAt != null &&
                !c.profileUpdatedAt!.isBefore(windowStart)) ||
            (c.profileCreatedAt != null &&
                !c.profileCreatedAt!.isBefore(windowStart));
        return byOrder || byProfile;
      }).toList();
    case _CustomerSegment.repeat:
      return all.where((c) => c.orderCount >= 2).toList();
  }
}

void _sortCustomers(List<_CustomerAgg> list, String sortLabel) {
  switch (sortLabel) {
    case 'Oldest':
      list.sort((a, b) {
        final la = a._newestActivity;
        final lb = b._newestActivity;
        return la.compareTo(lb);
      });
      break;
    case 'Most orders':
      list.sort((a, b) => b.orderCount.compareTo(a.orderCount));
      break;
    case 'Newest':
    default:
      list.sort((a, b) {
        final la = a._newestActivity;
        final lb = b._newestActivity;
        return lb.compareTo(la);
      });
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerMetricTile extends StatelessWidget {
  const _CustomerMetricTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? cs.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A6A62);

    return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    cs.surface.withValues(alpha: 0.98),
                    cs.surfaceContainerHighest.withValues(alpha: 0.32),
                  ]
                : [
                    const Color(0xFFFFFFFF),
                    const Color(0xFFFFF5EB),
                  ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              height: 34,
              width: 34,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
                border: Border.all(color: iconColor.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 10.2,
                fontWeight: FontWeight.w600,
                color: muted,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
                height: 1.05,
              ),
            ),
          ],
        ),
    );
  }
}

class _CustomerListTile extends StatelessWidget {
  const _CustomerListTile({
    required this.customer,
    required this.muted,
    required this.onSurface,
    required this.onTap,
    required this.deleting,
  });

  final _CustomerAgg customer;
  final Color muted;
  final Color onSurface;
  final VoidCallback onTap;
  final bool deleting;

  static const _avatarPalettes = [
    (Color(0xFFFFF8E1), Color(0xFFF9A825)),
    (Color(0xFFE8F5E9), Color(0xFF2E7D32)),
    (Color(0xFFE3F2FD), Color(0xFF1565C0)),
    (Color(0xFFF3E5F5), Color(0xFF7B1FA2)),
  ];

  @override
  Widget build(BuildContext context) {
    final h = customer.uid.hashCode.abs();
    final pal = _avatarPalettes[h % _avatarPalettes.length];
    final last = customer.lastOrder;

    return InkWell(
      onTap: deleting ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [pal.$1, pal.$1.withValues(alpha: 0.78)],
                ),
                border: Border.all(color: pal.$2.withValues(alpha: 0.25)),
              ),
              child: Center(
                child: Text(
                  customer.initials,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: pal.$2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    customer.phoneDisplay,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on_outlined, size: 15, color: muted),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          customer.locationLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: muted,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1E8),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFFFFD5BF),
                      ),
                    ),
                    child: Text(
                      '${customer.orderCount} orders',
                      style: GoogleFonts.poppins(
                        fontSize: 10.3,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF9A4632),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Icon(
                    deleting ? Icons.hourglass_top_rounded : Icons.chevron_right_rounded,
                    color: deleting ? const Color(0xFFD32F2F) : muted,
                    size: deleting ? 18 : 22,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    last == null
                        ? 'Last order: —'
                        : 'Last order: ${_formatMediumDate(last)}',
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: muted,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
            color: selected
                ? cs.primary.withValues(alpha: 0.14)
                : cs.surface,
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

String _formatMediumDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

DateTime? _readCreatedAt(Map<String, dynamic> data) {
  final c = data['created_at'];
  if (c is Timestamp) return c.toDate();
  return null;
}

String _readUid(Map<String, dynamic> data) {
  final u = data['uid'];
  return u is String ? u : '';
}

/// Live OpenStreetMap preview centered on the customer's saved coordinates.
class _CustomerLocationMapPreview extends StatelessWidget {
  const _CustomerLocationMapPreview({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  static const _maroon = Color(0xFF7C1D1B);

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    return FlutterMap(
      options: MapOptions(
        initialCenter: point,
        initialZoom: 16,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.chechiputtuapp',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: point,
              width: 42,
              height: 42,
              alignment: Alignment.topCenter,
              child: const Icon(
                Icons.location_on_rounded,
                color: _maroon,
                size: 42,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
