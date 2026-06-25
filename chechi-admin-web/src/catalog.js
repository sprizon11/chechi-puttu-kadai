export const CATALOG = [
  {
    section: 'Puttu',
    subtitle: 'Traditional Steamed Delights',
    dishes: [
      { title: 'Rice Puttu',              subtitle: 'Soft rice & coconut layers',        price: '₹70',  badge: 'Bestseller' },
      { title: 'Ragi Puttu',              subtitle: 'Nutty finger millet favourite',      price: '₹75' },
      { title: 'Sorghum (Cholam) Puttu',  subtitle: 'Golden cholam, homestyle',           price: '₹85' },
      { title: 'Wheat Puttu',             subtitle: 'Soft steamed wheat layers',          price: '₹85' },
      { title: 'Chemba Puttu',            subtitle: 'Red rice puttu, earthy & mild',      price: '₹85' },
      { title: 'Rice Semiya Puttu',       subtitle: 'Fine vermicelli texture',            price: '₹80' },
      { title: 'Beetroot Puttu',          subtitle: 'Naturally sweet, vibrant',           price: '₹90' },
      { title: 'Palak Puttu',             subtitle: 'Spinach goodness in every layer',    price: '₹95' },
      { title: 'Carrot Puttu',            subtitle: 'Mild sweetness, colourful',          price: '₹90' },
      { title: 'Millet Puttu',            subtitle: 'Mixed millet, fibre-rich',           price: '₹95' },
    ],
  },
  {
    section: 'Gravies & Curries',
    subtitle: 'Rich homestyle curries & gravies',
    dishes: [
      { title: 'Kadala Curry',        subtitle: 'Black chickpeas in thick gravy',         price: '₹85',  badge: 'Classic' },
      { title: 'Potato Stew',         subtitle: 'Creamy potato, coconut milk',            price: '₹100' },
      { title: 'Green Peas Curry',    subtitle: 'Sweet peas & coconut masala',            price: '₹95' },
      { title: 'Red Cow Peas Curry',  subtitle: 'Vanpayar — slow-cooked & hearty',       price: '₹110' },
      { title: 'Green Gram Curry',    subtitle: 'Moong in spiced coconut gravy',          price: '₹95' },
      { title: 'Vegetable Kuruma',    subtitle: 'Mixed veg, mild & fragrant',             price: '₹90' },
      { title: 'Tapioca (Kappa)',     subtitle: 'Seasoned kappa with curry leaves',       price: '₹75' },
    ],
  },
  {
    section: 'Desserts',
    subtitle: 'Sweet endings & payasam',
    dishes: [
      { title: 'Ada Pradhaman',     subtitle: 'Jaggery & rice ada',        price: '₹120' },
      { title: 'Elaneer Payasam',   subtitle: 'Tender coconut dessert',    price: '₹110' },
    ],
  },
  {
    section: 'Our Signature Dishes',
    subtitle: 'Chef specials, meals & festive picks',
    dishes: [
      { title: 'Chef Special Thali',  subtitle: 'Rice, curries & sides',            price: '₹180', badge: 'Chef pick' },
      { title: 'Malabar Parotta',     subtitle: 'Flaky layered flatbread',           price: '₹45' },
      { title: 'Mixed Veg Curry',     subtitle: 'Chef special coconut gravy',        price: '₹130' },
      { title: 'Ghee Rice',           subtitle: 'Aromatic neichoru',                 price: '₹120' },
    ],
  },
]

/** key used in Firestore snapshots subcollection */
export function dishKey(section, title) {
  return `${section}${title}`
}

/** All dishes flattened with their key */
export function allCatalogDishes() {
  const out = []
  for (const s of CATALOG) {
    for (const d of s.dishes) {
      out.push({ key: dishKey(s.section, d.title), section: s.section, ...d })
    }
  }
  return out
}
