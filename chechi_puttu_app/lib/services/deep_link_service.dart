import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Which tab a deep link should open. Values match the IndexedStack order in
/// HomeScreen, and the tab numbers _handlePushDeepLink already uses for
/// notifications — the two paths deliberately agree, so a link and a push that
/// mean the same thing land in the same place.
abstract final class DeepLinkTab {
  static const int menu = 0;
  static const int cart = 1;
  static const int orders = 2;
  static const int chat = 4;
}

/// Handles `chechiputtu://` links, which is how an advert opens the app on a
/// customer's phone.
///
/// Adverts point at `chechiputtu://menu`, so a customer who already has the
/// app lands on the dishes rather than a cold start at whatever screen they
/// last used. Unknown links fall back to the menu instead of being dropped: an
/// advert that opens nothing looks broken, and the menu is never a wrong
/// answer for someone arriving from one.
class DeepLinkService {
  DeepLinkService({required this.onOpenTab});

  /// Called with a [DeepLinkTab] value when a link arrives.
  final void Function(int tabIndex) onOpenTab;

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  /// Starts listening. Handles both the link that launched the app from cold
  /// and any that arrive while it is already running.
  Future<void> init() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e) {
      debugPrint('DeepLinkService initial link failed: $e');
    }
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) => debugPrint('DeepLinkService stream error: $e'),
    );
  }

  void _handle(Uri uri) {
    if (uri.scheme != 'chechiputtu') return;
    // The target is the host for chechiputtu://menu, but the first path
    // segment for chechiputtu:///menu — accept both rather than depend on how
    // whoever built the advert typed it.
    final target = uri.host.isNotEmpty
        ? uri.host.toLowerCase()
        : (uri.pathSegments.isNotEmpty
            ? uri.pathSegments.first.toLowerCase()
            : '');
    switch (target) {
      case 'cart':
        onOpenTab(DeepLinkTab.cart);
      case 'orders':
        onOpenTab(DeepLinkTab.orders);
      case 'chat':
      case 'support':
        onOpenTab(DeepLinkTab.chat);
      case 'menu':
      case 'home':
      case '':
      default:
        onOpenTab(DeepLinkTab.menu);
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
