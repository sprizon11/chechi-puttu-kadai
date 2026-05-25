import 'package:chechi_puttu_app/admin/admin_customers_screen.dart';
import 'package:chechi_puttu_app/admin/admin_chats_screen.dart';
import 'package:chechi_puttu_app/admin/admin_menu_management_screen.dart';
import 'package:chechi_puttu_app/admin/admin_orders_screen.dart';
import 'package:chechi_puttu_app/admin/admin_reports_screen.dart';
import 'package:chechi_puttu_app/admin/admin_settings_screen.dart';
import 'package:chechi_puttu_app/services/app_refresh.dart';
import 'package:chechi_puttu_app/theme/chechi_premium.dart';
import 'package:chechi_puttu_app/widgets/app_pull_to_refresh.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.onToggleTheme,
    required this.navIndexNotifier,
  });

  final VoidCallback onToggleTheme;
  final ValueNotifier<int> navIndexNotifier;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String _chartRange = 'This Week';

  void _openChats() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminChatsScreen()),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _ordersStream() {
    return FirebaseFirestore.instance
        .collection('orders')
        .orderBy('created_at', descending: true)
        .limit(250)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .limit(1200)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = theme.brightness == Brightness.dark
        ? cs.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A6A62);

    return ValueListenableBuilder<int>(
      valueListenable: widget.navIndexNotifier,
      builder: (context, navIndex, _) {
        Widget bodyContent() {
          switch (navIndex) {
            case 0:
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _usersStream(),
                builder: (context, usersSnap) {
                  final activeUids = usersSnap.data?.docs
                          .map((d) => d.id)
                          .where((id) => id.trim().isNotEmpty)
                          .toSet() ??
                      <String>{};
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _ordersStream(),
                    builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData &&
                      usersSnap.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: CircularProgressIndicator(
                          color: cs.primary,
                        ),
                      ),
                    );
                  }
                  if (usersSnap.hasError || snap.hasError) {
                    return AppPullToRefresh(
                      onRefresh: AppRefresh.refreshAdminMenuData,
                      child: SingleChildScrollView(
                        physics: AppPullToRefresh.scrollPhysics,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Could not load orders',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${usersSnap.error ?? snap.error}',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: muted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Check Firestore rules/indexes for `users` and `orders`.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: muted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    );
                  }
                  final docs = (snap.data?.docs ?? const []).where((d) {
                    final uid = (d.data()['uid'] as String?)?.trim() ?? '';
                    return uid.isNotEmpty && activeUids.contains(uid);
                  }).toList();
                  return AppPullToRefresh(
                    onRefresh: AppRefresh.refreshAdminMenuData,
                    child: SingleChildScrollView(
                      physics: AppPullToRefresh.scrollPhysics,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome, Admin',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 28,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Here's what's happening with your business today.",
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Metrics below use latest orders from active '
                          'customers (`users` + `orders`).',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: muted.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _FirestoreStatCardsRow(docs: docs, muted: muted),
                        const SizedBox(height: 18),
                        _FirestoreOrderOverviewCard(
                          docs: docs,
                          rangeLabel: _chartRange,
                          onRangeChanged: (v) =>
                              setState(() => _chartRange = v),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Quick Actions',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _QuickActionsRow(
                          onManageMenu: () =>
                              widget.navIndexNotifier.value = 1,
                          onOrders: () =>
                              widget.navIndexNotifier.value = 2,
                          onCustomers: () =>
                              widget.navIndexNotifier.value = 3,
                          textColor: cs.onSurface,
                          borderColor: cs.outlineVariant,
                        ),
                        const SizedBox(height: 22),
                        _RecentOrdersHeader(
                          onViewAll: () =>
                              widget.navIndexNotifier.value = 2,
                          titleColor: cs.onSurface,
                        ),
                        const SizedBox(height: 10),
                        _FirestoreRecentOrdersTable(docs: docs),
                        ],
                      ),
                    ),
                  );
                    },
                  );
                },
              );
            case 1:
              return const AdminMenuManagementBody();
            case 2:
              return const AdminOrdersBody();
            case 3:
              return const AdminCustomersBody();
            case 4:
              return const AdminReportsBody();
            case 5:
              return AdminSettingsBody(
                onToggleTheme: widget.onToggleTheme,
                onOpenTab: (i) => widget.navIndexNotifier.value = i,
              );
            default:
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Coming soon',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ),
              );
          }
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: theme.scaffoldBackgroundColor,
          extendBody: true,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: theme.brightness == Brightness.dark
                              ? [
                                  Colors.transparent,
                                  cs.primary.withValues(alpha: 0.06),
                                ]
                              : [
                                  Colors.transparent,
                                  const Color(0xFFFFEFE2).withValues(alpha: 0.55),
                                ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -40,
                  top: -20,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: theme.brightness == Brightness.dark
                          ? 0.04
                          : 0.06,
                      child: Icon(
                        Icons.restaurant_menu_rounded,
                        size: 220,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                _AdminTopBar(
                  onToggleTheme: widget.onToggleTheme,
                  onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                  onChats: _openChats,
                  iconColor: cs.onSurface,
                ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.015),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(navIndex),
                          child: bodyContent(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          drawer: Drawer(
            backgroundColor: cs.surface,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        Text(
                          'Admin',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.close_rounded, color: cs.onSurface),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: cs.outlineVariant),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: cs.primary.withValues(alpha: 0.14),
                            child: Icon(
                              Icons.admin_panel_settings_outlined,
                              size: 18,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Admin mode active',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: Text(
                      'Navigate',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.dashboard_outlined, color: cs.primary),
                    title: Text(
                      'Dashboard',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.navIndexNotifier.value = 0;
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.restaurant_menu_rounded, color: cs.primary),
                    title: Text(
                      'Menu Management',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.navIndexNotifier.value = 1;
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.receipt_long_outlined, color: cs.primary),
                    title: Text(
                      'Orders',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.navIndexNotifier.value = 2;
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.groups_outlined, color: cs.primary),
                    title: Text(
                      'Customers',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.navIndexNotifier.value = 3;
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.query_stats_rounded, color: cs.primary),
                    title: Text(
                      'Reports',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.navIndexNotifier.value = 4;
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.settings_outlined, color: cs.primary),
                    title: Text(
                      'Settings',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      widget.navIndexNotifier.value = 5;
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                    child: Text(
                      'Quick Tools',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.chat_bubble_outline_rounded, color: cs.primary),
                    title: Text(
                      'Support Chats',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openChats();
                    },
                  ),
                  Divider(height: 1, color: cs.outlineVariant),
                  ListTile(
                    leading: Icon(Icons.logout_rounded, color: cs.primary),
                    title: Text(
                      'Sign out',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await FirebaseAuth.instance.signOut();
                    },
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: _AdminBottomNav(
            index: navIndex,
            onTap: (i) => widget.navIndexNotifier.value = i,
            surface: cs.surface,
            outline: cs.outlineVariant,
          ),
        );
      },
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({
    required this.onToggleTheme,
    required this.onMenu,
    required this.onChats,
    required this.iconColor,
  });

  final VoidCallback onToggleTheme;
  final VoidCallback onMenu;
  final VoidCallback onChats;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget iconShell({
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.surfaceContainerHighest.withValues(alpha: dark ? 0.34 : 0.55),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.9)),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Icon(icon, key: ValueKey(icon), color: iconColor, size: 22),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Row(
        children: [
          iconShell(icon: Icons.menu_rounded, onTap: onMenu),
          const Spacer(),
          iconShell(icon: Icons.notifications_none_rounded, onTap: () {}),
          const SizedBox(width: 8),
          iconShell(icon: Icons.chat_bubble_outline_rounded, onTap: onChats),
        ],
      ),
    );
  }
}

class _FirestoreStatCardsRow extends StatelessWidget {
  const _FirestoreStatCardsRow({
    required this.docs,
    required this.muted,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final totalOrders = docs.length;
    var revenue = 0;
    final uids = <String>{};
    var pending = 0;
    for (final d in docs) {
      final m = d.data();
      revenue += _readTotalRupees(m);
      final u = _readUid(m);
      if (u.isNotEmpty) uids.add(u);
      final st = (_readStatusRaw(m) ?? '').toLowerCase();
      if (st != 'delivered' && st != 'cancelled') pending++;
    }

    return SizedBox(
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          ChechiFadeIn(
            delay: chechiStagger(0),
            child: _StatCard(
              icon: Icons.shopping_bag_outlined,
              iconBg: const Color(0xFFFFF0E6),
              iconColor: const Color(0xFFEA7A2C),
              label: 'Orders',
              value: '$totalOrders',
              trend: 'Recent orders',
              trendUp: true,
              muted: muted,
              titleColor: cs.onSurface,
              cardBg: cs.surface,
              borderColor: cs.outlineVariant,
            ),
          ),
          const SizedBox(width: 10),
          ChechiFadeIn(
            delay: chechiStagger(1),
            child: _StatCard(
              icon: Icons.currency_rupee_rounded,
              iconBg: const Color(0xFFE8F5E9),
              iconColor: const Color(0xFF2E7D32),
              label: 'Revenue',
              value: _fmtInr(revenue),
              trend: 'From recent orders',
              trendUp: true,
              muted: muted,
              titleColor: cs.onSurface,
              cardBg: cs.surface,
              borderColor: cs.outlineVariant,
            ),
          ),
          const SizedBox(width: 10),
          ChechiFadeIn(
            delay: chechiStagger(2),
            child: _StatCard(
              icon: Icons.people_outline_rounded,
              iconBg: const Color(0xFFFFF8E1),
              iconColor: const Color(0xFFF9A825),
              label: 'Customers',
              value: '${uids.length}',
              trend: 'Unique customers',
              trendUp: true,
              muted: muted,
              titleColor: cs.onSurface,
              cardBg: cs.surface,
              borderColor: cs.outlineVariant,
            ),
          ),
          const SizedBox(width: 10),
          ChechiFadeIn(
            delay: chechiStagger(3),
            child: _StatCard(
              icon: Icons.inventory_2_outlined,
              iconBg: const Color(0xFFF3E5F5),
              iconColor: const Color(0xFF7B1FA2),
              label: 'Active pipeline',
              value: '$pending',
              trend: 'Not delivered/cancelled',
              trendUp: pending == 0,
              muted: muted,
              titleColor: cs.onSurface,
              cardBg: cs.surface,
              borderColor: cs.outlineVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.trend,
    required this.trendUp,
    required this.muted,
    required this.titleColor,
    required this.cardBg,
    required this.borderColor,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final String trend;
  final bool trendUp;
  final Color muted;
  final Color titleColor;
  final Color cardBg;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: ChechiPremium.cardShadow(context, elevation: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: iconColor.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: muted,
              height: 1.12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: titleColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                trend,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                  color: trendUp
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFC62828),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirestoreOrderOverviewCard extends StatelessWidget {
  const _FirestoreOrderOverviewCard({
    required this.docs,
    required this.rangeLabel,
    required this.onRangeChanged,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String rangeLabel;
  final ValueChanged<String> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? cs.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A6A62);
    final spots = _spotsForChart(docs, rangeLabel);
    var maxY = spots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    if (maxY < 1) maxY = 1;
    final interval = (maxY / 4).ceilToDouble();
    maxY = interval * 4;
    final labels = _chartBottomLabels(rangeLabel);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Order Overview',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: onRangeChanged,
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'This Week', child: Text('This Week')),
                  PopupMenuItem(value: 'This Month', child: Text('This Month')),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rangeLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: cs.onSurface,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: cs.outlineVariant.withValues(alpha: 0.6),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: interval,
                      getTitlesWidget: (v, m) => Text(
                        v.toInt().toString(),
                        style: GoogleFonts.poppins(fontSize: 9, color: muted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (v, m) {
                        final i = v.toInt().clamp(0, 6);
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[i],
                            style: GoogleFonts.poppins(
                              fontSize: 9.5,
                              color: muted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFF5D1F1A),
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                        radius: 4,
                        color: const Color(0xFF5D1F1A),
                        strokeWidth: 2,
                        strokeColor: cs.surface,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          cs.primary.withValues(alpha: 0.35),
                          cs.primary.withValues(alpha: 0.04),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.onManageMenu,
    required this.onOrders,
    required this.onCustomers,
    required this.textColor,
    required this.borderColor,
  });

  final VoidCallback onManageMenu;
  final VoidCallback onOrders;
  final VoidCallback onCustomers;
  final Color textColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _QuickAction(
          icon: Icons.room_service_outlined,
          label: 'Manage\nMenu',
          color: const Color(0xFFFFF0E6),
          iconColor: const Color(0xFFEA7A2C),
          onTap: onManageMenu,
          textColor: textColor,
          borderColor: borderColor,
        ),
        _QuickAction(
          icon: Icons.assignment_outlined,
          label: 'Orders',
          color: const Color(0xFFE8F5E9),
          iconColor: const Color(0xFF2E7D32),
          onTap: onOrders,
          textColor: textColor,
          borderColor: borderColor,
        ),
        _QuickAction(
          icon: Icons.people_outline_rounded,
          label: 'Customers',
          color: const Color(0xFFFFEBEE),
          iconColor: const Color(0xFFE65100),
          onTap: onCustomers,
          textColor: textColor,
          borderColor: borderColor,
        ),
        _QuickAction(
          icon: Icons.local_offer_outlined,
          label: 'Offers',
          color: const Color(0xFFFFF8E1),
          iconColor: const Color(0xFFF9A825),
          textColor: textColor,
          borderColor: borderColor,
        ),
        _QuickAction(
          icon: Icons.bar_chart_rounded,
          label: 'Reports',
          color: const Color(0xFFF3E5F5),
          iconColor: const Color(0xFF7B1FA2),
          textColor: textColor,
          borderColor: borderColor,
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.textColor,
    required this.borderColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final Color textColor;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      children: [
        Container(
          height: 52,
          width: 52,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: GoogleFonts.poppins(
            fontSize: 9.5,
            height: 1.15,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ],
    );

    final child = onTap != null
        ? InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: column,
          )
        : column;

    return Expanded(child: child);
  }
}

class _RecentOrdersHeader extends StatelessWidget {
  const _RecentOrdersHeader({
    required this.onViewAll,
    required this.titleColor,
  });

  final VoidCallback onViewAll;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Recent Orders',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: titleColor,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: onViewAll,
          child: Text(
            'View All Orders >',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFEA7A2C),
            ),
          ),
        ),
      ],
    );
  }
}

class _FirestoreRecentOrdersTable extends StatelessWidget {
  const _FirestoreRecentOrdersTable({required this.docs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = docs.take(8).toList();

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                _h('Order ID', 1, cs),
                _h('Customer', 2, cs),
                _h('Items', 1, cs),
                _h('Amount', 1, cs),
                _h('Status', 1.2, cs),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No orders yet.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.7),
                ),
              _OrderRow(doc: rows[i], cs: cs),
            ],
        ],
      ),
    );
  }

  static Widget _h(String t, double flex, ColorScheme cs) {
    return Expanded(
      flex: (flex * 10).round(),
      child: Text(
        t,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.doc,
    required this.cs,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final idShort = doc.id.length > 6 ? doc.id.substring(0, 6) : doc.id;
    final uid = _readUid(m);
    final customer = uid.isEmpty
        ? '—'
        : (uid.length <= 6 ? uid : '…${uid.substring(uid.length - 6)}');
    final items = '${_readItemCount(m)}';
    final amt = _fmtInr(_readTotalRupees(m));
    final status = _formatStatus(_readStatusRaw(m));
    final chipBg = _statusChipFill(_readStatusRaw(m), cs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 10,
            child: Text(
              '#$idShort',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          Expanded(
            flex: 20,
            child: Text(
              customer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ),
          Expanded(
            flex: 10,
            child: Text(
              items,
              style: GoogleFonts.poppins(fontSize: 11, color: cs.onSurface),
            ),
          ),
          Expanded(
            flex: 10,
            child: Text(
              amt,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ),
          Expanded(
            flex: 12,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.poppins(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminBottomNav extends StatelessWidget {
  const _AdminBottomNav({
    required this.index,
    required this.onTap,
    required this.surface,
    required this.outline,
  });

  final int index;
  final ValueChanged<int> onTap;
  final Color surface;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = cs.primary;
    final inactive = Theme.of(context).brightness == Brightness.dark
        ? Colors.white54
        : const Color(0xFF8B8B8B);
    Widget item(int i, IconData icon, String label) {
      final sel = index == i;
      return Expanded(
        child: InkWell(
          onTap: () => onTap(i),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: sel
                    ? active.withValues(alpha: 0.14)
                    : Colors.transparent,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 21, color: sel ? active : inactive),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 9.5,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                      color: sel ? active : inactive,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface.withValues(alpha: 0.98),
            border: Border.all(color: outline),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(
              children: [
                item(0, Icons.home_outlined, 'Dashboard'),
                item(1, Icons.grid_view_outlined, 'Menu'),
                item(2, Icons.assignment_outlined, 'Orders'),
                item(3, Icons.people_outline_rounded, 'Customers'),
                item(4, Icons.bar_chart_rounded, 'Reports'),
                item(5, Icons.settings_outlined, 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Order helpers (aligned with [OrdersService] fields) ---

DateTime? _readCreatedAt(Map<String, dynamic> data) {
  final c = data['created_at'];
  if (c is Timestamp) return c.toDate();
  return null;
}

int _readTotalRupees(Map<String, dynamic> data) {
  final t = data['total_rupees'];
  if (t is int) return t;
  if (t is num) return t.round();
  return 0;
}

int _readItemCount(Map<String, dynamic> data) {
  final items = data['items'];
  if (items is List) return items.length;
  return 0;
}

String? _readStatusRaw(Map<String, dynamic> data) {
  final s = data['status'];
  return s is String ? s : null;
}

String _formatStatus(String? raw) {
  if (raw == null || raw.isEmpty) return 'Unknown';
  final s = raw.trim();
  if (s.length == 1) return s.toUpperCase();
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

String _readUid(Map<String, dynamic> data) {
  final u = data['uid'];
  return u is String ? u : '';
}

String _fmtInr(int rupees) {
  final s = rupees.abs().toString();
  final buf = StringBuffer('₹');
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    if (i > 0 && fromEnd % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

Color _statusChipFill(String? status, ColorScheme cs) {
  final st = (status ?? '').toLowerCase();
  switch (st) {
    case 'delivered':
      return cs.primaryContainer.withValues(alpha: 0.65);
    case 'cancelled':
      return cs.surfaceContainerHighest;
    case 'placed':
    case 'pending':
      return cs.errorContainer.withValues(alpha: 0.55);
    default:
      return cs.secondaryContainer.withValues(alpha: 0.65);
  }
}

List<FlSpot> _spotsForChart(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  String range,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final sums = List<double>.filled(7, 0);

  if (range == 'This Week') {
    final startDay = today.subtract(const Duration(days: 6));
    for (final d in docs) {
      final t = _readCreatedAt(d.data());
      if (t == null) continue;
      final day = DateTime(t.year, t.month, t.day);
      if (day.isBefore(startDay) || day.isAfter(today)) continue;
      final idx = day.difference(startDay).inDays.clamp(0, 6);
      sums[idx] += _readTotalRupees(d.data()).toDouble();
    }
  } else {
    for (final d in docs) {
      final t = _readCreatedAt(d.data());
      if (t == null) continue;
      final day = DateTime(t.year, t.month, t.day);
      final diff = today.difference(day).inDays;
      if (diff < 0 || diff > 29) continue;
      final raw = (diff * 7 / 30).floor().clamp(0, 6);
      final chartIdx = 6 - raw;
      sums[chartIdx] += _readTotalRupees(d.data()).toDouble();
    }
  }

  return List.generate(7, (i) => FlSpot(i.toDouble(), sums[i]));
}

List<String> _chartBottomLabels(String range) {
  if (range == 'This Week') {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      return names[d.weekday - 1];
    });
  }
  return const ['30d', '26d', '22d', '18d', '14d', '10d', '6d'];
}
