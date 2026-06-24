import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Shared map layers — OSM has the best street-name coverage in Tamil Nadu suburbs.
class AppMapTiles {
  AppMapTiles._();

  static const _userAgent = 'com.chechiputtu.kadai';

  /// Do not exceed 19 — OSM/Esri have no real tiles above this (shows "not available").
  static const double maxZoom = 19;

  /// Good default: street names visible without hitting empty tiles.
  static const double defaultZoom = 17;

  static const _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static InteractionOptions get interactions => const InteractionOptions(
        flags: InteractiveFlag.all,
      );

  /// Spread into FlutterMap `children`.
  static List<Widget> labeledStreetLayers() => [
        TileLayer(
          urlTemplate: _osmUrl,
          userAgentPackageName: _userAgent,
          maxNativeZoom: 19,
          maxZoom: maxZoom,
        ),
      ];
}
