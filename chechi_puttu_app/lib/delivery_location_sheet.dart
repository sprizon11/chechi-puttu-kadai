import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chechi_puttu_app/customer_location_picker_screen.dart';
import 'package:chechi_puttu_app/services/shop_location_service.dart';

/// Street/area line with optional exact coordinates when available.
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
  required String currentStreet,
  bool isDismissible = true,
  bool enableDrag = true,
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
    builder: (ctx) => _DeliveryLocationSheet(currentStreet: currentStreet),
  );
}

class _DeliveryLocationSheet extends StatefulWidget {
  const _DeliveryLocationSheet({required this.currentStreet});

  final String currentStreet;

  @override
  State<_DeliveryLocationSheet> createState() => _DeliveryLocationSheetState();
}

class _DeliveryLocationSheetState extends State<_DeliveryLocationSheet> {
  bool _gpsBusy = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _chooseOnMap() async {
    if (kIsWeb) {
      _toast('Map picker is available on the Android/iOS app.');
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

    final shop = await ShopLocationService.load();
    final picked = await openCustomerLocationPicker(
      context,
      initialLatitude: startLat ?? shop?.latitude,
      initialLongitude: startLng ?? shop?.longitude,
      initialAddressHint: startHint ?? shop?.address,
    );
    if (!mounted || picked == null) return;
    Navigator.of(context).pop((
      label: 'Delivery',
      street: picked.street,
      latitude: picked.latitude,
      longitude: picked.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCurrent = widget.currentStreet.trim().isNotEmpty &&
        widget.currentStreet.trim().toLowerCase() != 'choose delivery address';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
              'Pick your exact delivery point on the map. Drag the pin to your doorstep.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
          if (hasCurrent) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Current: ${widget.currentStreet}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.outline,
                  height: 1.3,
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: FilledButton.icon(
              onPressed: _gpsBusy ? null : _chooseOnMap,
              icon: _gpsBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.map_outlined, size: 22),
              label: Text(
                'Choose on map',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
