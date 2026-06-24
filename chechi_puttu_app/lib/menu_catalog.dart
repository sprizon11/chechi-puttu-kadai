// Customer-facing menu — single source for Home, search, cart, and admin.

/// One dish on the customer menu.
class MenuCatalogDish {
  const MenuCatalogDish(
    this.title,
    this.subtitle,
    this.price, {
    this.badge,
  });

  final String title;
  final String subtitle;
  final String price;
  final String? badge;
}

/// One category row (title + dishes) on the home screen.
class MenuCatalogSection {
  const MenuCatalogSection({
    required this.title,
    required this.subtitle,
    required this.dishes,
  });

  final String title;
  final String subtitle;
  final List<MenuCatalogDish> dishes;
}

/// Storage key for admin snapshots / delete list (section + catalog dish title).
String catalogDishStorageKey(String sectionTitle, String catalogDishTitle) =>
    '$sectionTitle\u001f$catalogDishTitle';

/// Same sections and dishes as the customer Home menu.
const kCustomerMenuSections = <MenuCatalogSection>[
  MenuCatalogSection(
    title: 'Puttu',
    subtitle: 'Traditional Steamed Delights',
    dishes: <MenuCatalogDish>[
      MenuCatalogDish('Rice Puttu', 'Soft rice & coconut layers', '₹70',
          badge: 'Bestseller'),
      MenuCatalogDish('Ragi Puttu', 'Nutty finger millet favourite', '₹75'),
      MenuCatalogDish(
        'Sorghum (Cholam) Puttu',
        'Golden cholam, homestyle',
        '₹85',
      ),
      MenuCatalogDish('Wheat Puttu', 'Soft steamed wheat layers', '₹85'),
      MenuCatalogDish('Chemba Puttu', 'Red rice puttu, earthy & mild', '₹85'),
      MenuCatalogDish('Rice Semiya Puttu', 'Fine vermicelli texture', '₹80'),
      MenuCatalogDish('Beetroot Puttu', 'Naturally sweet, vibrant', '₹90'),
      MenuCatalogDish('Palak Puttu', 'Spinach goodness in every layer', '₹95'),
      MenuCatalogDish('Carrot Puttu', 'Mild sweetness, colourful', '₹90'),
      MenuCatalogDish('Millet Puttu', 'Mixed millet, fibre-rich', '₹95'),
    ],
  ),
  MenuCatalogSection(
    title: 'Gravies & Curries',
    subtitle: 'Rich homestyle curries & gravies',
    dishes: <MenuCatalogDish>[
      MenuCatalogDish('Kadala Curry', 'Black chickpeas in thick gravy', '₹85',
          badge: 'Classic'),
      MenuCatalogDish('Potato Stew', 'Creamy potato, coconut milk', '₹100'),
      MenuCatalogDish('Green Peas Curry', 'Sweet peas & coconut masala', '₹95'),
      MenuCatalogDish(
        'Red Cow Peas Curry',
        'Vanpayar — slow-cooked & hearty',
        '₹110',
      ),
      MenuCatalogDish(
        'Green Gram Curry',
        'Moong in spiced coconut gravy',
        '₹95',
      ),
      MenuCatalogDish('Vegetable Kuruma', 'Mixed veg, mild & fragrant', '₹90'),
      MenuCatalogDish(
        'Tapioca (Kappa)',
        'Seasoned kappa with curry leaves',
        '₹75',
      ),
    ],
  ),
  MenuCatalogSection(
    title: 'Desserts',
    subtitle: 'Sweet endings & payasam',
    dishes: <MenuCatalogDish>[
      MenuCatalogDish('Ada Pradhaman', 'Jaggery & rice ada', '₹120'),
      MenuCatalogDish('Elaneer Payasam', 'Tender coconut dessert', '₹110'),
    ],
  ),
  MenuCatalogSection(
    title: 'Our Signature Dishes',
    subtitle: 'Chef specials, meals & festive picks',
    dishes: <MenuCatalogDish>[
      MenuCatalogDish('Chef Special Thali', 'Rice, curries & sides', '₹180',
          badge: 'Chef pick'),
      MenuCatalogDish('Malabar Parotta', 'Flaky layered flatbread', '₹45'),
      MenuCatalogDish(
        'Mixed Veg Curry',
        'Chef special coconut gravy',
        '₹130',
      ),
      MenuCatalogDish('Ghee Rice', 'Aromatic neichoru', '₹120'),
    ],
  ),
  MenuCatalogSection(
    title: 'Combo Offers',
    subtitle: 'Value meals & bundled favourites',
    dishes: <MenuCatalogDish>[
      MenuCatalogDish(
        'Puttu + Kadala Combo',
        'Rice puttu with kadala curry',
        '₹140',
        badge: 'Combo',
      ),
      MenuCatalogDish(
        'Family Breakfast Combo',
        '2 puttu + kadala + green peas curry',
        '₹320',
        badge: 'Best value',
      ),
      MenuCatalogDish(
        'Evening Snack Combo',
        'Wheat puttu + potato stew + payasam',
        '₹220',
        badge: 'Combo',
      ),
      MenuCatalogDish(
        'Party Combo Pack',
        'Assorted puttu & gravies (serves 4–5)',
        '₹599',
        badge: 'Party',
      ),
    ],
  ),
];

int menuCatalogParseRupees(String displayPrice) {
  final digits = displayPrice.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

/// Flattened rows excluding dishes whose keys appear in [deletedKeys]
/// or whose section is in [deletedSectionIds].
List<({String sectionTitle, MenuCatalogDish dish})> menuCatalogAllDishesHidingDeleted(
  Set<String> deletedKeys, {
  Set<String> deletedSectionIds = const {},
}) {
  final out = <({String sectionTitle, MenuCatalogDish dish})>[];
  for (final s in kCustomerMenuSections) {
    if (deletedSectionIds.contains(s.title)) continue;
    for (final d in s.dishes) {
      if (!deletedKeys.contains(catalogDishStorageKey(s.title, d.title))) {
        out.add((sectionTitle: s.title, dish: d));
      }
    }
  }
  return out;
}

/// Flattened rows for admin / reports (preserves section title per dish).
List<({String sectionTitle, MenuCatalogDish dish})> menuCatalogAllDishes() {
  final out = <({String sectionTitle, MenuCatalogDish dish})>[];
  for (final s in kCustomerMenuSections) {
    for (final d in s.dishes) {
      out.add((sectionTitle: s.title, dish: d));
    }
  }
  return out;
}
