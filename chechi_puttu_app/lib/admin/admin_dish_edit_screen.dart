import 'dart:convert';
import 'dart:typed_data';

import 'package:chechi_puttu_app/admin/admin_dish_models.dart';
import 'package:chechi_puttu_app/menu_catalog.dart';
import 'package:chechi_puttu_app/services/menu_image_utils.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

/// Full-screen editor for one menu dish (image + text + availability).
class AdminDishEditScreen extends StatefulWidget {
  const AdminDishEditScreen({
    super.key,
    required this.sectionTitle,
    required this.catalogDish,
    required this.initial,
  });

  final String sectionTitle;
  final MenuCatalogDish catalogDish;
  final AdminDishEditSnapshot initial;

  @override
  State<AdminDishEditScreen> createState() => _AdminDishEditScreenState();
}

class _AdminDishEditScreenState extends State<AdminDishEditScreen> {
  static const _maroon = Color(0xFF5D1F1A);
  static const _muted = Color(0xFF7A6A62);
  static const _border = Color(0xFFE8E0D8);
  static const _cream = Color(0xFFFFF6ED);

  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _badgeCtrl;
  bool _available = true;

  /// New image bytes from picker; null = no new pick.
  Uint8List? _pickedBytes;

  /// User explicitly removed the image.
  bool _imageRemoved = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _titleCtrl = TextEditingController(text: i.title);
    _subtitleCtrl = TextEditingController(text: i.subtitle);
    _priceCtrl = TextEditingController(text: i.price);
    _badgeCtrl = TextEditingController(text: i.badge ?? '');
    _available = i.available;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _priceCtrl.dispose();
    _badgeCtrl.dispose();
    super.dispose();
  }

  Uint8List? _initialImageBytes() {
    final b64 = widget.initial.imageBase64;
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (!mounted || x == null) return;
      final bytes = await x.readAsBytes();
      final compressed = compressMenuImageForCloud(bytes);
      if (compressed == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not compress this photo for cloud sync. Try another image.',
              ),
            ),
          );
        }
        return;
      }
      setState(() {
        _pickedBytes = compressed;
        _imageRemoved = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open camera/gallery: $e')),
        );
      }
    }
  }

  void _clearImage() {
    setState(() {
      _pickedBytes = null;
      _imageRemoved = true;
    });
  }

  String? _buildImageBase64ForSave() {
    if (_imageRemoved) return null;
    if (_pickedBytes != null) return base64Encode(_pickedBytes!);
    return widget.initial.imageBase64;
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a dish name.')),
      );
      return;
    }
    final priceRaw = _priceCtrl.text.trim();
    if (priceRaw.isEmpty || menuCatalogParseRupees(priceRaw) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid price (e.g. ₹70 or 70).')),
      );
      return;
    }
    final badgeText = _badgeCtrl.text.trim();
    Navigator.of(context).pop(
      AdminDishEditSnapshot(
        title: title,
        subtitle: _subtitleCtrl.text.trim(),
        price: priceRaw.startsWith('₹') ? priceRaw : '₹$priceRaw',
        badge: badgeText.isEmpty ? null : badgeText,
        imageBase64: _buildImageBase64ForSave(),
        available: _available,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbBytes = _imageRemoved
        ? null
        : (_pickedBytes ?? _initialImageBytes());

    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _cream,
        foregroundColor: _maroon,
        elevation: 0,
        title: Text(
          'Edit dish',
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: _maroon,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'Save',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: _maroon,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Icon(Icons.category_outlined, size: 18, color: _muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.sectionTitle,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _maroon,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Catalog: ${widget.catalogDish.title}',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: _muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Dish photo',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _maroon,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: thumbBytes != null
                  ? Image.memory(
                      thumbBytes,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    )
                  : ColoredBox(
                      color: Colors.white,
                      child: Center(
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 56,
                          color: _muted.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 20),
                  label: Text(
                    'Gallery',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _maroon,
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 20),
                  label: Text(
                    'Camera',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _maroon,
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          if (thumbBytes != null)
            TextButton.icon(
              onPressed: _clearImage,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: Text(
                'Remove photo',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(foregroundColor: Colors.red[800]),
            ),
          const SizedBox(height: 20),
          _fieldLabel('Name'),
          const SizedBox(height: 6),
          TextField(
            controller: _titleCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _inputDecoration(hint: 'Dish name'),
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          _fieldLabel('Description'),
          const SizedBox(height: 6),
          TextField(
            controller: _subtitleCtrl,
            maxLines: 3,
            decoration: _inputDecoration(hint: 'Short description for customers'),
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          _fieldLabel('Price'),
          const SizedBox(height: 6),
          TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.text,
            decoration: _inputDecoration(hint: 'e.g. ₹70'),
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          _fieldLabel('Badge (optional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _badgeCtrl,
            decoration: _inputDecoration(hint: 'Bestseller, Chef pick…'),
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 18),
          SwitchListTile.adaptive(
            value: _available,
            onChanged: (v) => setState(() => _available = v),
            title: Text(
              'Available for ordering',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: _maroon,
              ),
            ),
            subtitle: Text(
              'Turn off to hide this dish from the customer menu list.',
              style: GoogleFonts.poppins(fontSize: 11.5, color: _muted),
            ),
            activeThumbColor: _maroon,
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: _border),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: _maroon,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Save changes',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _maroon,
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(
        fontSize: 13,
        color: _muted.withValues(alpha: 0.75),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _maroon, width: 1.5),
      ),
    );
  }
}
