import 'package:chechi_puttu_app/customer_location_picker_screen.dart';
import 'package:chechi_puttu_app/services/shop_location_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Admin sets the kadai pin on the map (saved to Firestore for routes & map center).
class AdminShopLocationScreen extends StatefulWidget {
  const AdminShopLocationScreen({super.key});

  @override
  State<AdminShopLocationScreen> createState() =>
      _AdminShopLocationScreenState();
}

class _AdminShopLocationScreenState extends State<AdminShopLocationScreen> {
  static const _maroon = Color(0xFF7C1D1B);

  final _nameCtrl = TextEditingController(text: 'Chechi Puttu Kadai');
  String _address = '';
  double? _lat;
  double? _lng;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final shop = await ShopLocationService.load();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (shop != null) {
        _nameCtrl.text = shop.name;
        _address = shop.address;
        _lat = shop.latitude;
        _lng = shop.longitude;
      }
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickOnMap() async {
    final picked = await openCustomerLocationPicker(
      context,
      initialLatitude: _lat,
      initialLongitude: _lng,
      initialAddressHint: _address.isEmpty ? null : _address,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _address = picked.street;
      _lat = picked.latitude;
      _lng = picked.longitude;
    });
  }

  Future<void> _save() async {
    if (_lat == null || _lng == null || _address.trim().isEmpty) {
      _snack('Choose the shop location on the map first.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ShopLocationService.save(
        name: _nameCtrl.text,
        address: _address,
        latitude: _lat!,
        longitude: _lng!,
        updatedByUid: FirebaseAuth.instance.currentUser?.uid,
      );
      if (!mounted) return;
      _snack('Shop location saved.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Shop location',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set where your kadai is on the map. Customer maps and delivery routes will use this pin.',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Shop name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Map address',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _address.isEmpty
                              ? 'Not set — tap the button below to pick on map'
                              : _address,
                          style: GoogleFonts.poppins(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                        if (_lat != null && _lng != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: cs.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _pickOnMap,
                    icon: const Icon(Icons.map_outlined),
                    label: Text(
                      _address.isEmpty ? 'Choose shop on map' : 'Update on map',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _maroon,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'Save shop location',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
