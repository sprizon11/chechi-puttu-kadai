import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:chechi_puttu_app/theme/chechi_motion.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:chechi_puttu_app/services/address_format.dart';
import 'package:chechi_puttu_app/services/app_map_tiles.dart';
import 'package:chechi_puttu_app/services/delivery_area.dart';
import 'package:chechi_puttu_app/services/shop_location_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

/// Result from the draggable map pin location picker.
typedef CustomerMapPickResult = ({
  String street,
  double latitude,
  double longitude,
});

/// Full-screen map: customer drags map under a fixed pin to choose exact delivery point.
class CustomerLocationPickerScreen extends StatefulWidget {
  const CustomerLocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddressHint,
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddressHint;

  @override
  State<CustomerLocationPickerScreen> createState() =>
      _CustomerLocationPickerScreenState();
}

class _CustomerLocationPickerScreenState
    extends State<CustomerLocationPickerScreen> {
  static const _maroon = Color(0xFF7C1D1B);
  // Coimbatore city centre — the only area served, and a sane fallback when
  // no GPS or shop pin is available.
  static const _defaultCenter = LatLng(
    DeliveryArea.centerLatitude,
    DeliveryArea.centerLongitude,
  );
  static const _nominatimUa =
      'ChechiPuttuKadai/1.0 (location picker; +https://github.com)';

  final _mapController = MapController();
  StreamSubscription<MapEvent>? _mapSub;
  Timer? _geocodeDebounce;

  String _addressLine = 'Move the map to place your pin';
  bool _geocoding = false;
  bool _locating = false;
  LatLng _pinCenter = _defaultCenter;

  bool get _pinOutsideServiceArea => !DeliveryArea.isWithinServiceArea(
    _pinCenter.latitude,
    _pinCenter.longitude,
  );

  @override
  void initState() {
    super.initState();
    _pinCenter = _initialCenter();
    if (widget.initialAddressHint != null &&
        widget.initialAddressHint!.trim().isNotEmpty) {
      _addressLine = widget.initialAddressHint!.trim();
    }
    _mapSub = _mapController.mapEventStream.listen((event) {
      if (event is MapEventMoveEnd) {
        _onMapCenterChanged(_mapController.camera.center);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initMapCenter());
    });
  }

  LatLng _initialCenter() {
    final lat = widget.initialLatitude;
    final lng = widget.initialLongitude;
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }
    return _defaultCenter;
  }

  Future<void> _initMapCenter() async {
    var center = _pinCenter;
    if (widget.initialLatitude == null && widget.initialLongitude == null) {
      final shop = await ShopLocationService.load();
      if (shop != null) {
        center = LatLng(shop.latitude, shop.longitude);
        if (mounted) {
          setState(() => _pinCenter = center);
        }
      }
    }
    if (!mounted) return;
    _mapController.move(center, AppMapTiles.defaultZoom);
    _reverseGeocode(center);
  }

  @override
  void dispose() {
    _mapSub?.cancel();
    _geocodeDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onMapCenterChanged(LatLng center) {
    setState(() => _pinCenter = center);
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 350), () {
      _reverseGeocode(center);
    });
  }

  Future<String?> _reverseGeocodeNominatim(LatLng point) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'format': 'jsonv2',
        'addressdetails': '1',
        'zoom': '18',
      });
      final res = await http
          .get(uri, headers: {'User-Agent': _nominatimUa})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr != null) {
        final line = formatNominatimAddress(addr);
        if (line.isNotEmpty) return line;
      }
      final display = (data['display_name'] as String?)?.trim();
      return display?.isEmpty ?? true ? null : display;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _reverseGeocodePlatform(LatLng point) async {
    try {
      final marks = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (marks.isEmpty) return null;
      final p = marks.first;
      final line = formatPlacemarkParts(
        name: p.name,
        subThoroughfare: p.subThoroughfare,
        thoroughfare: p.thoroughfare,
        subLocality: p.subLocality,
        locality: p.locality,
        subAdministrativeArea: p.subAdministrativeArea,
        administrativeArea: p.administrativeArea,
        postalCode: p.postalCode,
      );
      return line.isEmpty ? null : line;
    } catch (_) {
      return null;
    }
  }

  /// Number of comma-separated components — a proxy for how complete an
  /// address line is, used to pick the richer of two geocoders.
  static int _detailCount(String? line) {
    if (line == null) return 0;
    return line.split(',').where((p) => p.trim().isNotEmpty).length;
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _geocoding = true);
    try {
      // OSM is thin on locality names in Tamil Nadu suburbs while the platform
      // geocoder (Google/Apple) is strong there, and vice-versa for some
      // streets — so query both and keep whichever names more of the address.
      final results = await Future.wait([
        _reverseGeocodeNominatim(point),
        _reverseGeocodePlatform(point),
      ]);
      if (!mounted) return;
      final nominatim = results[0]?.trim();
      final platform = results[1]?.trim();

      String? best;
      if (_detailCount(platform) > _detailCount(nominatim)) {
        best = platform;
      } else {
        best = nominatim;
      }
      best ??= platform;

      setState(() {
        _addressLine = (best != null && best.isNotEmpty)
            ? best
            : 'Pinned location (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addressLine =
            'Pinned location (${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)})';
      });
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _goToMyLocation() async {
    if (kIsWeb) {
      _showSnack('GPS is limited on web. Drag the map to your area.');
      return;
    }
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showSnack('Turn on location services.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _showSnack('Location permission is required.');
        return;
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
      if (pos == null) {
        _showSnack('Could not detect your location.');
        return;
      }
      final here = LatLng(pos.latitude, pos.longitude);
      _mapController.move(here, AppMapTiles.defaultZoom);
      _onMapCenterChanged(here);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  void _confirm() {
    final street = _addressLine.trim();
    if (street.isEmpty) {
      _showSnack('Wait for address to load, or move the map again.');
      return;
    }
    if (!DeliveryArea.isWithinServiceArea(
      _pinCenter.latitude,
      _pinCenter.longitude,
    )) {
      _showSnack(DeliveryArea.outsideMessage);
      return;
    }
    Navigator.of(context).pop((
      street: street,
      latitude: _pinCenter.latitude,
      longitude: _pinCenter.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pinCenter,
              initialZoom: AppMapTiles.defaultZoom,
              minZoom: 3,
              maxZoom: AppMapTiles.maxZoom,
              interactionOptions: AppMapTiles.interactions,
            ),
            children: [
              ...AppMapTiles.labeledStreetLayers(),
            ],
          ),
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 52,
                    color: _maroon,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _maroon.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Text(
                        'Drag map & place pin on your doorstep',
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 200,
            child: SafeArea(
              top: false,
              child: FloatingActionButton(
                heroTag: 'gps_recenter',
                backgroundColor: cs.surface,
                foregroundColor: _maroon,
                onPressed: _locating ? null : _goToMyLocation,
                child: _locating
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.my_location_rounded),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cs.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Delivery point',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.place_rounded, color: _maroon, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _addressLine,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          if (_geocoding)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                        ],
                      ),
                      if (_pinOutsideServiceArea) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDECEA),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFF3C6C1)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: Color(0xFFB3261E),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  DeliveryArea.outsideMessage,
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFFB3261E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: (_geocoding || _pinOutsideServiceArea)
                            ? null
                            : _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: _maroon,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Confirm this location',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
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

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: cs.onSurface),
        ),
      ),
    );
  }
}

/// Opens the map picker; returns picked address + coordinates or null.
Future<CustomerMapPickResult?> openCustomerLocationPicker(
  BuildContext context, {
  double? initialLatitude,
  double? initialLongitude,
  String? initialAddressHint,
}) {
  return Navigator.of(context).push<CustomerMapPickResult>(
    ChechiPageRoute(
      builder: (_) => CustomerLocationPickerScreen(
        initialLatitude: initialLatitude,
        initialLongitude: initialLongitude,
        initialAddressHint: initialAddressHint,
      ),
    ),
  );
}
