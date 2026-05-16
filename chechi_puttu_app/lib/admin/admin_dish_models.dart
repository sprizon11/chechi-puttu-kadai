import 'package:chechi_puttu_app/menu_catalog.dart';

/// Stable id for storage: section + catalog dish title (title in [MenuCatalogDish]).
String adminDishStorageKey(String sectionTitle, String catalogDishTitle) =>
    catalogDishStorageKey(sectionTitle, catalogDishTitle);

/// Same key as [AdminMenuManagementBody] — admin writes, customer Home reads.
const kAdminDishSnapshotsPrefsKey = 'chechi_admin_dish_edit_snapshots_v1';

/// Menu category (section) overrides — title, subtitle, cover image.
const kAdminSectionOverridesPrefsKey = 'chechi_admin_section_overrides_v1';

const _sectionKeyPrefix = '__section__\u001f';

/// Stable section id (catalog title or custom category name).
String adminSectionStorageKey(String sectionId) => '$_sectionKeyPrefix$sectionId';

/// Admin-edited fields for one catalog dish (persisted locally).
class AdminDishEditSnapshot {
  const AdminDishEditSnapshot({
    required this.title,
    required this.subtitle,
    required this.price,
    this.badge,
    this.imageBase64,
    this.available = true,
  });

  final String title;
  final String subtitle;
  final String price;
  final String? badge;
  final String? imageBase64;
  final bool available;

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'price': price,
        'badge': badge,
        'imageBase64': imageBase64,
        'available': available,
      };

  factory AdminDishEditSnapshot.fromJson(Map<String, dynamic> j) {
    return AdminDishEditSnapshot(
      title: j['title'] as String? ?? '',
      subtitle: j['subtitle'] as String? ?? '',
      price: j['price'] as String? ?? '₹0',
      badge: j['badge'] as String?,
      imageBase64: j['imageBase64'] as String?,
      available: j['available'] as bool? ?? true,
    );
  }

  AdminDishEditSnapshot copyWith({
    String? title,
    String? subtitle,
    String? price,
    String? badge,
    bool clearBadge = false,
    String? imageBase64,
    bool clearImage = false,
    bool? available,
  }) {
    return AdminDishEditSnapshot(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      price: price ?? this.price,
      badge: clearBadge ? null : (badge ?? this.badge),
      imageBase64: clearImage ? null : (imageBase64 ?? this.imageBase64),
      available: available ?? this.available,
    );
  }
}

AdminDishEditSnapshot snapshotFromCatalog(MenuCatalogDish dish) {
  return AdminDishEditSnapshot(
    title: dish.title,
    subtitle: dish.subtitle,
    price: dish.price,
    badge: dish.badge,
    imageBase64: null,
    available: true,
  );
}

AdminDishEditSnapshot mergeWithCatalog(
  MenuCatalogDish dish,
  AdminDishEditSnapshot? saved,
) {
  return saved ?? snapshotFromCatalog(dish);
}

/// Admin-edited menu category fields (persisted + cloud sync).
class AdminSectionEditSnapshot {
  const AdminSectionEditSnapshot({
    required this.title,
    required this.subtitle,
    this.imageBase64,
  });

  final String title;
  final String subtitle;
  final String? imageBase64;

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'imageBase64': imageBase64,
      };

  factory AdminSectionEditSnapshot.fromJson(Map<String, dynamic> j) {
    return AdminSectionEditSnapshot(
      title: j['title'] as String? ?? '',
      subtitle: j['subtitle'] as String? ?? '',
      imageBase64: j['imageBase64'] as String?,
    );
  }

  AdminSectionEditSnapshot copyWith({
    String? title,
    String? subtitle,
    String? imageBase64,
    bool clearImage = false,
  }) {
    return AdminSectionEditSnapshot(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      imageBase64: clearImage ? null : (imageBase64 ?? this.imageBase64),
    );
  }
}

AdminSectionEditSnapshot snapshotFromCatalogSection(MenuCatalogSection section) {
  return AdminSectionEditSnapshot(
    title: section.title,
    subtitle: section.subtitle,
    imageBase64: null,
  );
}

AdminSectionEditSnapshot mergeSectionWithCatalog(
  MenuCatalogSection section,
  AdminSectionEditSnapshot? saved,
) {
  if (saved == null) return snapshotFromCatalogSection(section);
  return AdminSectionEditSnapshot(
    title: saved.title.trim().isNotEmpty ? saved.title : section.title,
    subtitle:
        saved.subtitle.trim().isNotEmpty ? saved.subtitle : section.subtitle,
    imageBase64: saved.imageBase64,
  );
}
