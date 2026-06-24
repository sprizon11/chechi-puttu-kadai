import 'dart:convert';

import 'package:chechi_puttu_app/services/app_map_tiles.dart';
import 'package:chechi_puttu_app/services/shop_location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Full-screen map with route line and Google Maps navigation for admin.
class AdminCustomerMapScreen extends StatefulWidget {
  const AdminCustomerMapScreen({
    super.key,
    required this.customerName,
    required this.latitude,
    required this.longitude,
    this.addressLine,
  });

  final String customerName;
  final double latitude;
  final double longitude;
  final String? addressLine;

  @override
  State<AdminCustomerMapScreen> createState() => _AdminCustomerMapScreenState();
}

class _AdminCustomerMapScreenState extends State<AdminCustomerMapScreen> {
  static const _maroon = Color(0xFF7C1D1B);

  final _mapController = MapController();
  LatLng? _originPoint;
  bool _originIsShop = false;
  List<LatLng> _routePoints = [];
  String? _routeSummary;
  bool _loadingRoute = true;
  String? _routeError;

  LatLng get _customerPoint => LatLng(widget.latitude, widget.longitude);

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<LatLng?> _readAdminLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
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
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<({List<LatLng> points, double km, int minutes})?> _fetchDrivingRoute(
    LatLng from,
    LatLng to,
  ) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${from.longitude},${from.latitude};'
      '${to.longitude},${to.latitude}'
      '?overview=full&geometries=geojson',
    );
    final res = await http.get(url).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['code'] != 'Ok') return null;
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;
    final route = routes.first as Map<String, dynamic>;
    final coords =
        (route['geometry'] as Map<String, dynamic>)['coordinates'] as List;
    final points = coords
        .map(
          (c) => LatLng(
            (c[1] as num).toDouble(),
            (c[0] as num).toDouble(),
          ),
        )
        .toList();
    final km = ((route['distance'] as num?) ?? 0) / 1000.0;
    final minutes = (((route['duration'] as num?) ?? 0) / 60).round();
    return (points: points, km: km, minutes: minutes);
  }

  Future<void> _loadRoute() async {
    setState(() {
      _loadingRoute = true;
      _routeError = null;
      _routePoints = [];
      _routeSummary = null;
    });

    final shop = await ShopLocationService.load();
    LatLng? origin;
    var originIsShop = false;

    if (shop != null) {
      origin = LatLng(shop.latitude, shop.longitude);
      originIsShop = true;
    } else {
      origin = await _readAdminLocation();
    }
    if (!mounted) return;

    if (origin == null) {
      setState(() {
        _loadingRoute = false;
        _originPoint = null;
        _originIsShop = false;
        _routeError =
            'Set shop location in Settings, or enable GPS for your position.';
      });
      _fitMapToPoints([_customerPoint]);
      return;
    }

    final route = await _fetchDrivingRoute(origin, _customerPoint);
    if (!mounted) return;

    if (route == null) {
      setState(() {
        _originPoint = origin;
        _originIsShop = originIsShop;
        _loadingRoute = false;
        _routeError = 'Could not load route. You can still open Google Maps.';
      });
      _fitMapToPoints([origin, _customerPoint]);
      return;
    }

    setState(() {
      _originPoint = origin;
      _originIsShop = originIsShop;
      _routePoints = route.points;
      _routeSummary =
          '${originIsShop ? 'From shop' : 'From you'} · ${route.km.toStringAsFixed(1)} km · ~${route.minutes} min';
      _loadingRoute = false;
    });
    _fitMapToPoints([origin, _customerPoint, ...route.points]);
  }

  void _fitMapToPoints(List<LatLng> points) {
    if (points.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(56, 120, 56, 200),
        ),
      );
    });
  }

  Future<void> _openGoogleMapsDirections() async {
    final dest = '${widget.latitude},${widget.longitude}';
    final origin = _originPoint == null
        ? null
        : '${_originPoint!.latitude},${_originPoint!.longitude}';
    final uri = origin == null
        ? Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving',
          )
        : Uri.parse(
            'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$dest&travelmode=driving',
          );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not open Google Maps.',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final address = (widget.addressLine ?? '').trim();

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _customerPoint,
              initialZoom: AppMapTiles.defaultZoom,
              minZoom: 3,
              maxZoom: AppMapTiles.maxZoom,
              interactionOptions: AppMapTiles.interactions,
            ),
            children: [
              ...AppMapTiles.labeledStreetLayers(),
              if (_routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: _maroon,
                      strokeWidth: 5.5,
                      borderColor: Colors.white,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_originPoint != null)
                    Marker(
                      point: _originPoint!,
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _originIsShop
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFF1565C0),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(
                          _originIsShop
                              ? Icons.storefront_rounded
                              : Icons.navigation_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  Marker(
                    point: _customerPoint,
                    width: 44,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: _maroon,
                      size: 44,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _TopIconButton(
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
                        color: cs.surface.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                          if (address.isNotEmpty && address != '—')
                            Text(
                              address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loadingRoute)
            const Align(
              alignment: Alignment.center,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                      SizedBox(width: 12),
                      Text('Loading directions...'),
                    ],
                  ),
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
                      Row(
                        children: [
                          Icon(Icons.route_rounded, color: _maroon, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _routeSummary ??
                                  (_routeError ??
                                      'Pinch to zoom · street names on map'),
                              style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                                height: 1.3,
                              ),
                            ),
                          ),
                          if (!_loadingRoute)
                            IconButton(
                              tooltip: 'Refresh route',
                              onPressed: _loadRoute,
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _openGoogleMapsDirections,
                        style: FilledButton.styleFrom(
                          backgroundColor: _maroon,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.directions_rounded),
                        label: Text(
                          'Start navigation in Google Maps',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
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

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.95),
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
