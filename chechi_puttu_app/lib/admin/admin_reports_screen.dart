import 'dart:io';

import 'package:chechi_puttu_app/services/app_refresh.dart';
import 'package:chechi_puttu_app/widgets/app_pull_to_refresh.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

class AdminReportsBody extends StatefulWidget {
  const AdminReportsBody({super.key});

  @override
  State<AdminReportsBody> createState() => _AdminReportsBodyState();
}

class _AdminReportsBodyState extends State<AdminReportsBody> {
  int _rangeDays = 7;
  DateTimeRange? _selectedRange;

  String _csvCell(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<Directory> _bestDownloadDirectory() async {
    try {
      final d = await getDownloadsDirectory();
      if (d != null) return d;
    } catch (_) {}
    try {
      final d = await getExternalStorageDirectory();
      if (d != null) return d;
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  String _safeRangeLabel(DateTime start, DateTime end) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${start.year}${two(start.month)}${two(start.day)}'
        '_${end.year}${two(end.month)}${two(end.day)}';
  }

  Future<void> _downloadCsv(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime start,
    DateTime end,
  ) async {
    final rows = <String>[
      'order_id,uid,status,total_rupees,payment_mode,delivery_line,created_at',
    ];
    for (final d in docs) {
      final m = d.data();
      final created = _createdAt(m);
      rows.add([
        _csvCell(d.id),
        _csvCell(_uid(m)),
        _csvCell((m['status'] as String?) ?? ''),
        _csvCell('${_totalRupees(m)}'),
        _csvCell((m['payment_mode'] as String?) ?? ''),
        _csvCell((m['delivery_line'] as String?) ?? ''),
        _csvCell(created?.toIso8601String() ?? ''),
      ].join(','));
    }
    final csv = rows.join('\n');
    final dir = await _bestDownloadDirectory();
    final file = File(
      '${dir.path}/chechi_report_${_safeRangeLabel(start, end)}.csv',
    );
    await file.writeAsString(csv, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'CSV downloaded: ${file.path}',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  Future<void> _downloadPdf(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime start,
    DateTime end,
  ) async {
    final pdf = pw.Document();
    final rows = <List<String>>[
      ['Order ID', 'Status', 'Total', 'Payment', 'Created At'],
    ];
    for (final d in docs.take(180)) {
      final m = d.data();
      final created = _createdAt(m)?.toIso8601String() ?? '-';
      rows.add([
        d.id,
        (m['status'] as String?) ?? '-',
        '₹${_totalRupees(m)}',
        (m['payment_mode'] as String?) ?? '-',
        created,
      ]);
    }
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            'Chechi Puttu Reports',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Range: ${_dateRangeLabel(start, end)}'),
          pw.Text('Orders: ${docs.length}'),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: rows.first,
            data: rows.skip(1).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );
    final bytes = await pdf.save();
    final dir = await _bestDownloadDirectory();
    final file = File(
      '${dir.path}/chechi_report_${_safeRangeLabel(start, end)}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'PDF downloaded: ${file.path}',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial =
        _selectedRange ??
        DateTimeRange(
          start: today.subtract(Duration(days: _rangeDays - 1)),
          end: today,
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: today.add(const Duration(days: 1)),
      initialDateRange: initial,
      saveText: 'Apply',
    );
    if (picked != null) {
      setState(() => _selectedRange = DateTimeRange(
            start: DateTime(picked.start.year, picked.start.month, picked.start.day),
            end: DateTime(picked.end.year, picked.end.month, picked.end.day),
          ));
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _ordersStream() {
    return chechiFirestore
        .collection('orders')
        .orderBy('created_at', descending: true)
        .limit(1200)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream() {
    return chechiFirestore.collection('users').limit(1200).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? cs.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A6A62);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _usersStream(),
      builder: (context, usersSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _ordersStream(),
          builder: (context, snap) {
        if (usersSnap.connectionState == ConnectionState.waiting &&
            !usersSnap.hasData &&
            snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return Center(
            child: CircularProgressIndicator(color: cs.primary),
          );
        }
        if (usersSnap.hasError || snap.hasError) {
          return AppPullToRefresh(
            onRefresh: AppRefresh.refreshAdminMenuData,
            child: SingleChildScrollView(
              physics: AppPullToRefresh.scrollPhysics,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
              child: Text(
              'Could not load reports.\n${usersSnap.error ?? snap.error}',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: muted,
                height: 1.45,
              ),
            ),
          ),
          );
        }

        final userDocs = usersSnap.data?.docs ?? const [];
        final activeUids = userDocs.map((d) => d.id).toSet();
        final docs = (snap.data?.docs ?? const []).where((d) {
          final uid = _uid(d.data()).trim();
          return uid.isNotEmpty && activeUids.contains(uid);
        }).toList();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final activeRange =
            _selectedRange ??
            DateTimeRange(
              start: today.subtract(Duration(days: _rangeDays - 1)),
              end: today,
            );
        final start = activeRange.start;
        final end = activeRange.end;
        final spanDays = end.difference(start).inDays + 1;
        final prevEnd = start.subtract(const Duration(days: 1));
        final prevStart = prevEnd.subtract(Duration(days: spanDays - 1));

        bool inRange(DateTime? t, DateTime s, DateTime e) {
          if (t == null) return false;
          final day = DateTime(t.year, t.month, t.day);
          return !(day.isBefore(s) || day.isAfter(e));
        }

        final current =
            docs.where((d) => inRange(_createdAt(d.data()), start, end)).toList();
        final previous = docs
            .where((d) => inRange(_createdAt(d.data()), prevStart, prevEnd))
            .toList();

        final currentSummary = _Summary.fromDocs(current, start, end);
        final previousSummary = _Summary.fromDocs(previous, prevStart, prevEnd);
        final topItems = _topItems(current);
        final statusBreakdown = _statusBreakdown(current);
        final paymentBreakdown = _paymentBreakdown(current);
        final spotsAndLabels = _lineSeries(current, start, spanDays);
        final uniqueCustomers = current
            .map((d) => _uid(d.data()))
            .where((u) => u.trim().isNotEmpty)
            .toSet()
            .length;
        final repeatRate = uniqueCustomers == 0
            ? 0.0
            : (currentSummary.repeatCustomers * 100.0 / uniqueCustomers);
        final cancelledCount = current.where((d) {
          final s = ((d.data()['status'] as String?) ?? '').toLowerCase();
          return s == 'cancelled' || s == 'rejected';
        }).length;
        final cancelRate = currentSummary.totalOrders == 0
            ? 0.0
            : (cancelledCount * 100.0 / currentSummary.totalOrders);
        final avgOrderValue = currentSummary.totalOrders == 0
            ? 0.0
            : (currentSummary.revenue / currentSummary.totalOrders);
        final peakHour = _peakHourLabel(current);

        return AppPullToRefresh(
          onRefresh: AppRefresh.refreshAdminMenuData,
          child: SingleChildScrollView(
            physics: AppPullToRefresh.scrollPhysics,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: cs.outlineVariant),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.surface,
                      cs.surfaceContainerHighest.withValues(alpha: 0.45),
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
                            'Analytics Studio',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: cs.surface,
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Text(
                            '${currentSummary.totalOrders} orders',
                            style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Track growth, quality, and operational signals in one premium dashboard.',
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _pickDateRange,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.date_range_rounded, size: 18, color: muted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _dateRangeLabel(start, end),
                                style: GoogleFonts.poppins(
                                  fontSize: 12.8,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _downloadCsv(current, start, end),
                          icon: const Icon(Icons.file_download_outlined, size: 18),
                          label: Text(
                            'CSV',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _downloadPdf(current, start, end),
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                          label: Text(
                            'PDF',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        PopupMenuButton<int>(
                          onSelected: (v) => setState(() {
                            _rangeDays = v;
                            _selectedRange = null;
                          }),
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(value: 7, child: Text('Last 7 days')),
                            PopupMenuItem(value: 30, child: Text('Last 30 days')),
                            PopupMenuItem(value: 90, child: Text('Last 90 days')),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.filter_list_rounded, size: 18, color: muted),
                                const SizedBox(width: 6),
                                Text(
                                  'Range',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: itemWidth,
                        child: _ReportMetricCard(
                          label: 'Total Orders',
                          value: '${currentSummary.totalOrders}',
                          delta: _pct(
                            currentSummary.totalOrders,
                            previousSummary.totalOrders,
                          ),
                          icon: Icons.shopping_bag_outlined,
                          iconBg: const Color(0xFFFFF0E6),
                          iconColor: const Color(0xFFEA7A2C),
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _ReportMetricCard(
                          label: 'Total Revenue',
                          value: _fmtInr(currentSummary.revenue),
                          delta: _pct(currentSummary.revenue, previousSummary.revenue),
                          icon: Icons.currency_rupee_rounded,
                          iconBg: const Color(0xFFE8F5E9),
                          iconColor: const Color(0xFF2E7D32),
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _ReportMetricCard(
                          label: 'New Customers',
                          value: '${currentSummary.newCustomers}',
                          delta: _pct(
                            currentSummary.newCustomers,
                            previousSummary.newCustomers,
                          ),
                          icon: Icons.person_add_alt_1_rounded,
                          iconBg: const Color(0xFFE3F2FD),
                          iconColor: const Color(0xFF1565C0),
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _ReportMetricCard(
                          label: 'Repeat Customers',
                          value: '${currentSummary.repeatCustomers}',
                          delta: _pct(
                            currentSummary.repeatCustomers,
                            previousSummary.repeatCustomers,
                          ),
                          icon: Icons.autorenew_rounded,
                          iconBg: const Color(0xFFF3E5F5),
                          iconColor: const Color(0xFF7B1FA2),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InsightChip(
                      label: 'Repeat Rate',
                      value: '${repeatRate.toStringAsFixed(1)}%',
                      color: const Color(0xFF2E7D32),
                    ),
                    _InsightChip(
                      label: 'Cancel Rate',
                      value: '${cancelRate.toStringAsFixed(1)}%',
                      color: const Color(0xFFC62828),
                    ),
                    _InsightChip(
                      label: 'Avg Order',
                      value: '₹${avgOrderValue.toStringAsFixed(0)}',
                      color: const Color(0xFF1565C0),
                    ),
                    _InsightChip(
                      label: 'Peak Hour',
                      value: peakHour,
                      color: const Color(0xFF7B1FA2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SalesOverviewCard(
                spots: spotsAndLabels.$1,
                labels: spotsAndLabels.$2,
                maxY: spotsAndLabels.$3,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 760;
                  if (narrow) {
                    return Column(
                      children: [
                        _TopItemsCard(items: topItems),
                        const SizedBox(height: 10),
                        _StatusCard(
                          totalOrders: currentSummary.totalOrders,
                          statusBreakdown: statusBreakdown,
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _TopItemsCard(items: topItems)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatusCard(
                          totalOrders: currentSummary.totalOrders,
                          statusBreakdown: statusBreakdown,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _PaymentCard(paymentBreakdown: paymentBreakdown),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(Icons.query_stats_rounded, color: cs.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reports update in real-time from active customers and their orders.',
                        style: GoogleFonts.poppins(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: muted,
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
          },
        );
      },
    );
  }
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({
    required this.label,
    required this.value,
    required this.delta,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
  });

  final String label;
  final String value;
  final double delta;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final up = delta >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surface,
            cs.surfaceContainerHighest.withValues(alpha: 0.38),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconBg,
                  border: Border.all(color: iconColor.withValues(alpha: 0.25)),
                ),
                child: Icon(icon, color: iconColor, size: 17),
              ),
              const Spacer(),
              Text(
                '${up ? '↑' : '↓'} ${delta.abs().toStringAsFixed(1)}%',
                style: GoogleFonts.poppins(
                  fontSize: 10.8,
                  fontWeight: FontWeight.w700,
                  color: up ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'vs previous period',
            style: GoogleFonts.poppins(
              fontSize: 10.2,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightChip extends StatelessWidget {
  const _InsightChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.poppins(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 10.8,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesOverviewCard extends StatelessWidget {
  const _SalesOverviewCard({
    required this.spots,
    required this.labels,
    required this.maxY,
  });

  final List<FlSpot> spots;
  final List<String> labels;
  final double maxY;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? cs.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A6A62);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Sales Overview',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Text(
                  'Daily',
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 210,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 5,
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
                      reservedSize: 40,
                      interval: maxY / 5,
                      getTitlesWidget: (v, _) => Text(
                        _fmtK(v),
                        style: GoogleFonts.poppins(fontSize: 9, color: muted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt().clamp(0, 6);
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
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
                lineTouchData: LineTouchData(enabled: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFF7C1D1B),
                    barWidth: 2.2,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 3.5,
                        color: const Color(0xFF7C1D1B),
                        strokeColor: cs.surface,
                        strokeWidth: 1.8,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF7C1D1B).withValues(alpha: 0.20),
                          const Color(0xFF7C1D1B).withValues(alpha: 0.02),
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

class _TopItemsCard extends StatelessWidget {
  const _TopItemsCard({required this.items});

  final List<_ItemSales> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Top Selling Items',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'View All',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              'No item data yet.',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: cs.onSurfaceVariant,
              ),
            )
          else
            for (final item in items.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _fmtInr(item.revenue),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.totalOrders,
    required this.statusBreakdown,
  });

  final int totalOrders;
  final List<MapEntry<String, int>> statusBreakdown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = <Color>[
      const Color(0xFF4CAF50),
      const Color(0xFFE53935),
      const Color(0xFFFFA726),
      const Color(0xFF5C6BC0),
      const Color(0xFF8D6E63),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Orders by Status',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 138,
            child: PieChart(
              PieChartData(
                sectionsSpace: 1.5,
                centerSpaceRadius: 32,
                sections: [
                  for (var i = 0; i < statusBreakdown.length; i++)
                    PieChartSectionData(
                      value: statusBreakdown[i].value.toDouble(),
                      color: colors[i % colors.length],
                      radius: 44,
                      title: '',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$totalOrders total',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < statusBreakdown.length && i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      statusBreakdown[i].key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    '${statusBreakdown[i].value}',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.paymentBreakdown});

  final List<MapEntry<String, int>> paymentBreakdown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = paymentBreakdown.fold<int>(0, (s, e) => s + e.value);
    final colors = <Color>[
      const Color(0xFF4CAF50),
      const Color(0xFF5C6BC0),
      const Color(0xFFFFA726),
      const Color(0xFF8E24AA),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Revenue by Payment Method',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 140,
                height: 130,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: 32,
                    sectionsSpace: 1.5,
                    sections: [
                      for (var i = 0; i < paymentBreakdown.length; i++)
                        PieChartSectionData(
                          value: paymentBreakdown[i].value.toDouble(),
                          color: colors[i % colors.length],
                          radius: 42,
                          title: '',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < paymentBreakdown.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: colors[i % colors.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                paymentBreakdown[i].key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Text(
                              _fmtInr(paymentBreakdown[i].value),
                              style: GoogleFonts.poppins(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (total > 0)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Total ${_fmtInr(total)}',
                          style: GoogleFonts.poppins(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Summary {
  const _Summary({
    required this.totalOrders,
    required this.revenue,
    required this.newCustomers,
    required this.repeatCustomers,
  });

  final int totalOrders;
  final int revenue;
  final int newCustomers;
  final int repeatCustomers;

  factory _Summary.fromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime start,
    DateTime end,
  ) {
    var revenue = 0;
    final byUser = <String, int>{};
    final firstSeen = <String, DateTime>{};
    for (final d in docs) {
      final m = d.data();
      revenue += _totalRupees(m);
      final uid = _uid(m);
      if (uid.isNotEmpty) {
        byUser.update(uid, (v) => v + 1, ifAbsent: () => 1);
        final t = _createdAt(m);
        if (t != null) {
          final prev = firstSeen[uid];
          if (prev == null || t.isBefore(prev)) firstSeen[uid] = t;
        }
      }
    }

    var newCustomers = 0;
    var repeatCustomers = 0;
    for (final e in byUser.entries) {
      if (e.value >= 2) repeatCustomers++;
      final first = firstSeen[e.key];
      if (first != null) {
        final day = DateTime(first.year, first.month, first.day);
        if (!(day.isBefore(start) || day.isAfter(end))) newCustomers++;
      }
    }

    return _Summary(
      totalOrders: docs.length,
      revenue: revenue,
      newCustomers: newCustomers,
      repeatCustomers: repeatCustomers,
    );
  }
}

class _ItemSales {
  const _ItemSales({
    required this.name,
    required this.qty,
    required this.revenue,
  });

  final String name;
  final int qty;
  final int revenue;
}

List<_ItemSales> _topItems(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final qtyMap = <String, int>{};
  final revMap = <String, int>{};
  for (final d in docs) {
    final m = d.data();
    final items = m['items'];
    if (items is! List) continue;
    for (final raw in items) {
      if (raw is! Map) continue;
      final name = ((raw['title'] ?? raw['name'] ?? '') as String).trim();
      if (name.isEmpty) continue;
      final q = _asInt(raw['qty']) ?? _asInt(raw['quantity']) ?? 1;
      final line = _asInt(raw['line_total_rupees']) ??
          _asInt(raw['total_rupees']) ??
          _asInt(raw['price_rupees']) ??
          0;
      qtyMap.update(name, (v) => v + q, ifAbsent: () => q);
      revMap.update(name, (v) => v + line, ifAbsent: () => line);
    }
  }
  final out = <_ItemSales>[];
  for (final e in qtyMap.entries) {
    out.add(
      _ItemSales(name: e.key, qty: e.value, revenue: revMap[e.key] ?? 0),
    );
  }
  out.sort((a, b) => b.revenue.compareTo(a.revenue));
  return out;
}

List<MapEntry<String, int>> _statusBreakdown(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final map = <String, int>{};
  for (final d in docs) {
    final raw = (d.data()['status'] as String?) ?? 'unknown';
    final key = _title(raw);
    map.update(key, (v) => v + 1, ifAbsent: () => 1);
  }
  final out = map.entries.toList();
  out.sort((a, b) => b.value.compareTo(a.value));
  return out;
}

List<MapEntry<String, int>> _paymentBreakdown(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final map = <String, int>{};
  for (final d in docs) {
    final m = d.data();
    final key = _paymentLabel((m['payment_mode'] as String?) ?? 'other');
    final rupees = _totalRupees(m);
    map.update(key, (v) => v + rupees, ifAbsent: () => rupees);
  }
  final out = map.entries.toList();
  out.sort((a, b) => b.value.compareTo(a.value));
  return out;
}

(List<FlSpot>, List<String>, double) _lineSeries(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  DateTime start,
  int rangeDays,
) {
  final sums = List<double>.filled(7, 0);
  final labels = List<String>.filled(7, '');

  for (var i = 0; i < 7; i++) {
    final chunkStart = start.add(Duration(days: (rangeDays * i / 7).floor()));
    labels[i] = _shortDate(chunkStart);
  }

  for (final d in docs) {
    final t = _createdAt(d.data());
    if (t == null) continue;
    final diff = DateTime(t.year, t.month, t.day).difference(start).inDays;
    if (diff < 0 || diff >= rangeDays) continue;
    final idx = ((diff * 7) / rangeDays).floor().clamp(0, 6);
    sums[idx] += _totalRupees(d.data()).toDouble();
  }

  var maxY = sums.fold<double>(0, (m, v) => v > m ? v : m);
  if (maxY < 1000) maxY = 1000;
  maxY = (maxY * 1.2 / 1000).ceilToDouble() * 1000;

  final spots = List.generate(7, (i) => FlSpot(i.toDouble(), sums[i]));
  return (spots, labels, maxY);
}

double _pct(num current, num previous) {
  if (previous == 0) return current == 0 ? 0 : 100;
  return ((current - previous) / previous) * 100;
}

DateTime? _createdAt(Map<String, dynamic> data) {
  final t = data['created_at'];
  if (t is Timestamp) return t.toDate();
  return null;
}

int _totalRupees(Map<String, dynamic> data) {
  final t = data['total_rupees'];
  if (t is int) return t;
  if (t is num) return t.round();
  return 0;
}

String _uid(Map<String, dynamic> data) {
  final u = data['uid'];
  return u is String ? u : '';
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return null;
}

String _dateRangeLabel(DateTime start, DateTime end) {
  return '${_shortDate(start)} - ${_shortDate(end)}';
}

String _shortDate(DateTime d) {
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
  return '${months[d.month - 1]} ${d.day}';
}

String _paymentLabel(String raw) {
  final r = raw.toLowerCase().trim();
  switch (r) {
    case 'cash_on_delivery':
    case 'cod':
      return 'Cash on Delivery';
    case 'cashfree':
      return 'Cashfree (Online)';
    case 'razorpay':
      return 'Razorpay (Online)';
    case 'upi':
      return 'UPI';
    case 'card':
      return 'Card';
    default:
      return _title(r.isEmpty ? 'other' : r);
  }
}

String _title(String s) {
  final t = s.replaceAll('_', ' ').trim();
  if (t.isEmpty) return 'Unknown';
  return t
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String _peakHourLabel(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final counts = List<int>.filled(24, 0);
  for (final d in docs) {
    final t = _createdAt(d.data());
    if (t == null) continue;
    counts[t.hour]++;
  }
  var bestHour = 0;
  var bestCount = 0;
  for (var h = 0; h < counts.length; h++) {
    if (counts[h] > bestCount) {
      bestCount = counts[h];
      bestHour = h;
    }
  }
  final start = bestHour % 12 == 0 ? 12 : bestHour % 12;
  final endHour = (bestHour + 1) % 24;
  final end = endHour % 12 == 0 ? 12 : endHour % 12;
  final ampm = bestHour >= 12 ? 'PM' : 'AM';
  return '$start-$end $ampm';
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

String _fmtK(double v) {
  if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(0)}k';
  return '₹${v.toStringAsFixed(0)}';
}
