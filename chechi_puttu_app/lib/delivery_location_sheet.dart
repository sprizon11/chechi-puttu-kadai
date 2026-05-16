import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chechi_puttu_app/customer_location_picker_screen.dart';
import 'package:http/http.dart' as http;

/// Label + street/area line (shown as `Label - street` on home & cart),
/// with optional exact coordinates when available.
typedef DeliveryAddressResult =
    ({String label, String street, double? latitude, double? longitude});

/// Reverse-geocodes the device position to one line. Returns null on web,
/// denied permission, or errors.
Future<({String street, double latitude, double longitude})?>
fetchAddressLineFromDeviceGps() async {
  if (kIsWeb) return null;
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));
    } catch (_) {
      pos = await Geolocator.getLastKnownPosition();
    }
    if (pos == null) return null;
    final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
    if (marks.isEmpty) return null;
    final p = marks.first;
    final parts = <String>[];
    void add(String? s) {
      if (s == null) return;
      final t = s.trim();
      if (t.isEmpty) return;
      parts.add(t);
    }

    add(p.street);
    add(p.subLocality);
    add(p.locality);
    add(p.postalCode);
    add(p.administrativeArea);
    final street = parts.isEmpty ? 'Current map location' : parts.join(', ');
    return (
      street: street,
      latitude: pos.latitude,
      longitude: pos.longitude,
    );
  } catch (_) {
    return null;
  }
}

Future<DeliveryAddressResult?> showDeliveryLocationSheet(
  BuildContext context, {
  required String currentLabel,
  required String currentStreet,
  String? savedHomeStreet,
  String? savedWorkStreet,
  String? savedOtherStreet,
  bool secondarySlotIsOffice = false,
  bool isDismissible = true,
  bool enableDrag = true,
  /// When set, chips start on this tag (e.g. opening the Office row).
  String? preferredTag,
}) {
  return showModalBottomSheet<DeliveryAddressResult>(
    context: context,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black54,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _DeliveryLocationSheet(
      currentLabel: currentLabel,
      currentStreet: currentStreet,
      savedHomeStreet: savedHomeStreet,
      savedWorkStreet: savedWorkStreet,
      savedOtherStreet: savedOtherStreet,
      secondarySlotIsOffice: secondarySlotIsOffice,
      preferredTag: preferredTag,
    ),
  );
}

class _NominatimHit {
  const _NominatimHit({
    required this.displayName,
    required this.lat,
    required this.lon,
  });

  final String displayName;
  final double lat;
  final double lon;
}

class _DeliveryLocationSheet extends StatefulWidget {
  const _DeliveryLocationSheet({
    required this.currentLabel,
    required this.currentStreet,
    this.savedHomeStreet,
    this.savedWorkStreet,
    this.savedOtherStreet,
    this.secondarySlotIsOffice = false,
    this.preferredTag,
  });

  final String currentLabel;
  final String currentStreet;
  final String? savedHomeStreet;
  final String? savedWorkStreet;
  final String? savedOtherStreet;
  final bool secondarySlotIsOffice;
  final String? preferredTag;

  @override
  State<_DeliveryLocationSheet> createState() => _DeliveryLocationSheetState();
}

class _DeliveryLocationSheetState extends State<_DeliveryLocationSheet> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<_NominatimHit> _hits = [];
  bool _searching = false;
  bool _gpsBusy = false;
  String? _pickedStreet;
  double? _pickedLat;
  double? _pickedLng;
  late String _tag;

  static const _ua = 'ChechiPuttuKadai/1.0 (delivery search; +https://github.com)';

  String get _secondaryTag => widget.secondarySlotIsOffice ? 'Office' : 'Work';

  @override
  void initState() {
    super.initState();
    final cur = widget.currentLabel.trim();
    if (cur == 'Home' ||
        cur == 'Work' ||
        cur == 'Office' ||
        cur == 'Other' ||
        cur == 'Current location') {
      _tag = cur == 'Office' && !widget.secondarySlotIsOffice ? 'Work' : cur;
    } else {
      _tag = 'Other';
    }
    final hint = widget.preferredTag?.trim();
    if (hint != null &&
        hint.isNotEmpty &&
        (hint == 'Home' ||
            hint == 'Work' ||
            hint == 'Office' ||
            hint == 'Other' ||
            hint == 'Current location')) {
      if (hint == 'Office' && !widget.secondarySlotIsOffice) {
        _tag = 'Work';
      } else if (hint == 'Work' && widget.secondarySlotIsOffice) {
        _tag = _secondaryTag;
      } else {
        _tag = hint;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _runSearch(String q) async {
    final query = q.trim();
    if (query.length < 3) {
      setState(() => _hits = []);
      return;
    }
    setState(() {
      _searching = true;
    });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '10',
        'countrycodes': 'in',
        'addressdetails': '0',
      });
      final res = await http.get(uri, headers: {'User-Agent': _ua});
      if (res.statusCode != 200) {
        if (mounted) _toast('Search failed. Try again.');
        setState(() => _hits = []);
        return;
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      final out = <_NominatimHit>[];
      for (final e in list) {
        if (e is! Map<String, dynamic>) continue;
        final name = e['display_name'] as String?;
        final latS = e['lat'] as String?;
        final lonS = e['lon'] as String?;
        if (name == null || latS == null || lonS == null) continue;
        final lat = double.tryParse(latS);
        final lon = double.tryParse(lonS);
        if (lat == null || lon == null) continue;
        out.add(_NominatimHit(displayName: name, lat: lat, lon: lon));
      }
      if (mounted) setState(() => _hits = out);
    } catch (_) {
      if (mounted) {
        _toast('Could not search. Check internet.');
        setState(() => _hits = []);
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _useGps() async {
    if (kIsWeb) {
      _toast('Use search on web — GPS is limited in the browser.');
      return;
    }
    setState(() => _gpsBusy = true);
    double? startLat;
    double? startLng;
    String? startHint;
    try {
      final line = await fetchAddressLineFromDeviceGps();
      if (line != null) {
        startLat = line.latitude;
        startLng = line.longitude;
        startHint = line.street.trim();
      }
    } catch (_) {
      // Still open map so customer can drag pin manually.
    } finally {
      if (mounted) setState(() => _gpsBusy = false);
    }
    if (!mounted) return;

    final picked = await openCustomerLocationPicker(
      context,
      initialLatitude: startLat,
      initialLongitude: startLng,
      initialAddressHint: startHint,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _pickedStreet = picked.street;
      _pickedLat = picked.latitude;
      _pickedLng = picked.longitude;
      _tag = 'Current location';
    });
  }

  Future<void> _selectHit(_NominatimHit h) async {
    final picked = await openCustomerLocationPicker(
      context,
      initialLatitude: h.lat,
      initialLongitude: h.lon,
      initialAddressHint: h.displayName,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _pickedStreet = picked.street;
      _pickedLat = picked.latitude;
      _pickedLng = picked.longitude;
      _tag = 'Other';
    });
  }

  void _selectSaved(String label, String street) {
    Navigator.of(context).pop((
      label: label,
      street: street,
      latitude: null,
      longitude: null,
    ));
  }

  void _confirm() {
    final s = _pickedStreet?.trim();
    if (s == null || s.isEmpty) {
      _toast('Choose an address from search, GPS, or a saved address.');
      return;
    }
    Navigator.of(context).pop((
      label: _tag,
      street: s,
      latitude: _pickedLat,
      longitude: _pickedLng,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.94,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      builder: (context, scrollCtrl) {
        return CustomScrollView(
          controller: scrollCtrl,
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Select delivery location',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Chechi wants to know your location.',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                        height: 1.35,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(
                      'Search or pick on map — drag the pin to your exact doorstep.',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Now: ${widget.currentLabel} — ${widget.currentStreet}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 450), () {
                          _runSearch(v);
                        });
                      },
                      onSubmitted: _runSearch,
                      decoration: InputDecoration(
                        hintText: 'Search area, road, landmark…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerLow,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!kIsWeb)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: OutlinedButton.icon(
                        onPressed: _gpsBusy ? null : _useGps,
                        icon: _gpsBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location_rounded, size: 20),
                        label: Text(
                          'Choose on map (current location)',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Text(
                      'Saved',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SavedTile(
                            icon: Icons.home_outlined,
                            title: 'Home',
                            subtitle: widget.savedHomeStreet ??
                                'Tap to search & set',
                            enabled: widget.savedHomeStreet != null &&
                                widget.savedHomeStreet!.trim().isNotEmpty,
                            onTap: widget.savedHomeStreet != null &&
                                    widget.savedHomeStreet!.trim().isNotEmpty
                                ? () => _selectSaved(
                                    'Home',
                                    widget.savedHomeStreet!,
                                  )
                                : () => _toast(
                                    'Search an address, then tag as Home.',
                                  ),
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SavedTile(
                            icon: Icons.work_outline_rounded,
                            title: _secondaryTag,
                            subtitle: widget.savedWorkStreet ??
                                'Tap to search & set',
                            enabled: widget.savedWorkStreet != null &&
                                widget.savedWorkStreet!.trim().isNotEmpty,
                            onTap: widget.savedWorkStreet != null &&
                                    widget.savedWorkStreet!.trim().isNotEmpty
                                ? () => _selectSaved(
                                    _secondaryTag,
                                    widget.savedWorkStreet!,
                                  )
                                : () => _toast(
                                    'Search an address, then tag as $_secondaryTag.',
                                  ),
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SavedTile(
                            icon: Icons.place_outlined,
                            title: 'Other',
                            subtitle: widget.savedOtherStreet ??
                                'Tap to search & set',
                            enabled: widget.savedOtherStreet != null &&
                                widget.savedOtherStreet!.trim().isNotEmpty,
                            onTap: widget.savedOtherStreet != null &&
                                    widget.savedOtherStreet!.trim().isNotEmpty
                                ? () => _selectSaved(
                                    'Other',
                                    widget.savedOtherStreet!,
                                  )
                                : () => _toast(
                                    'Search an address, then tag as Other.',
                                  ),
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_pickedStreet != null) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Deliver to',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text(
                        _pickedStreet!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Home'),
                            selected: _tag == 'Home',
                            onSelected: (_) => setState(() => _tag = 'Home'),
                          ),
                          ChoiceChip(
                            label: Text(_secondaryTag),
                            selected: _tag == _secondaryTag,
                            onSelected: (_) =>
                                setState(() => _tag = _secondaryTag),
                          ),
                          ChoiceChip(
                            label: const Text('Other'),
                            selected: _tag == 'Other',
                            onSelected: (_) => setState(() => _tag = 'Other'),
                          ),
                          ChoiceChip(
                            label: const Text('Current location'),
                            selected: _tag == 'Current location',
                            onSelected: (_) =>
                                setState(() => _tag = 'Current location'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: FilledButton(
                        onPressed: _confirm,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Confirm & deliver here',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                    child: Text(
                      'Search results',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_hits.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Text(
                    'Type at least 3 letters to search, or use current location.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final hit = _hits[i];
                    final primary = hit.displayName.split(',').first.trim();
                    return ListTile(
                      leading: Icon(
                        Icons.place_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(
                        primary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        hit.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(fontSize: 12),
                      ),
                      onTap: () => _selectHit(hit),
                    );
                  },
                  childCount: _hits.length,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final pad = compact
        ? const EdgeInsets.fromLTRB(8, 10, 8, 10)
        : const EdgeInsets.fromLTRB(12, 12, 12, 12);
    final titleSize = compact ? 11.0 : 14.0;
    final subSize = compact ? 10.0 : 11.0;
    return Material(
      color: t.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: compact ? 18 : 22, color: t.colorScheme.primary),
              SizedBox(height: compact ? 4 : 6),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  fontSize: titleSize,
                ),
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: subSize,
                  color: enabled
                      ? t.colorScheme.onSurfaceVariant
                      : t.colorScheme.outline,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
