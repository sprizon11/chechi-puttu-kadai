import 'dart:convert';
import 'dart:typed_data';

import 'package:chechi_puttu_app/admin/admin_dish_models.dart';
import 'package:chechi_puttu_app/services/menu_image_utils.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

/// Full-screen editor for a menu category (title, subtitle, cover image).
class AdminCategoryEditScreen extends StatefulWidget {
  const AdminCategoryEditScreen({
    super.key,
    required this.sectionId,
    required this.initial,
    this.isCustomCategory = false,
  });

  /// Stable id — catalog section title or custom category name.
  final String sectionId;
  final AdminSectionEditSnapshot initial;
  final bool isCustomCategory;

  @override
  State<AdminCategoryEditScreen> createState() => _AdminCategoryEditScreenState();
}

class _AdminCategoryEditScreenState extends State<AdminCategoryEditScreen> {
  static const _maroon = Color(0xFF5D1F1A);
  static const _muted = Color(0xFF7A6A62);
  static const _border = Color(0xFFE8E0D8);
  static const _cream = Color(0xFFFFF6ED);

  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  Uint8List? _pickedBytes;
  bool _imageRemoved = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initial.title);
    _subtitleCtrl = TextEditingController(text: widget.initial.subtitle);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
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
        const SnackBar(content: Text('Please enter a category name.')),
      );
      return;
    }
    Navigator.of(context).pop(
      AdminCategorySaveResult(
        snapshot: AdminSectionEditSnapshot(
          title: title,
          subtitle: _subtitleCtrl.text.trim(),
          imageBase64: _buildImageBase64ForSave(),
        ),
        renamedSectionId: widget.isCustomCategory && title != widget.sectionId
            ? title
            : null,
      ),
    );
  }

  Future<void> _confirmDeleteCategory() async {
    final label = _titleCtrl.text.trim().isNotEmpty
        ? _titleCtrl.text.trim()
        : widget.sectionId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete category?',
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: _maroon,
          ),
        ),
        content: Text(
          'Delete "$label" and all dishes inside it? '
          'This hides them from the customer menu on this device.',
          style: GoogleFonts.poppins(
            fontSize: 13,
            height: 1.4,
            color: _muted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Delete category',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    Navigator.of(context).pop(const AdminCategoryDeleteRequest());
  }

  @override
  Widget build(BuildContext context) {
    final thumbBytes =
        _imageRemoved ? null : (_pickedBytes ?? _initialImageBytes());

    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _cream,
        foregroundColor: _maroon,
        elevation: 0,
        title: Text(
          'Edit category',
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
          Text(
            'Section id: ${widget.sectionId}',
            style: GoogleFonts.poppins(fontSize: 11, color: _muted),
          ),
          const SizedBox(height: 16),
          Text(
            'Category cover image',
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
              aspectRatio: 16 / 9,
              child: thumbBytes != null
                  ? Image.memory(thumbBytes, fit: BoxFit.cover, width: double.infinity)
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
          Text(
            'Category name',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _maroon,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _titleCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'e.g. Puttu, Evening Snacks',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
            ),
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          Text(
            'Subtitle (shown to customers)',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _maroon,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _subtitleCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Short line under category name',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
            ),
            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: _confirmDeleteCategory,
            icon: const Icon(Icons.delete_forever_rounded, size: 22),
            label: Text(
              'Delete category & all dishes',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade800,
              side: BorderSide(color: Colors.red.shade300),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminCategorySaveResult {
  const AdminCategorySaveResult({
    required this.snapshot,
    this.renamedSectionId,
  });

  final AdminSectionEditSnapshot snapshot;
  final String? renamedSectionId;
}

/// Returned when admin confirms category delete from the editor.
class AdminCategoryDeleteRequest {
  const AdminCategoryDeleteRequest();
}
