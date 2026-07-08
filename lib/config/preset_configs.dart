import 'business_config.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Ready-made configs for common business types.
/// Fork the repo → open this file → uncomment your business type → done.
/// ─────────────────────────────────────────────────────────────────────────────

class BusinessPresets {

  // ── 📱 Mobile / Electronics Shop ───────────────────────────────────────────
  static const mobileShop = BusinessConfig(
    businessType: 'Mobile Shop',
    currency: 'PKR',
    currencySymbol: 'Rs',
    supplierLabel: 'Supplier',
    itemLabel: 'Phone',
    itemsLabel: 'Phones',
    invoiceHint:
        'Mobile phone shop invoice. Products are smartphones with brand, model, storage, color, and IMEI numbers.',
    productFields: [
      ProductField(key: 'brand',   label: 'Brand',   required: true,  hint: 'Samsung'),
      ProductField(key: 'model',   label: 'Model',   required: true,  hint: 'Galaxy A55'),
      ProductField(key: 'storage', label: 'Storage', hint: '128GB'),
      ProductField(key: 'color',   label: 'Color',   hint: 'Black'),
      ProductField(key: 'imei',    label: 'IMEI',    isIdentifier: true,
                   hint: '15-digit number'),
    ],
  );

  // ── 💊 Pharmacy / Medical Store ─────────────────────────────────────────────
  static const pharmacy = BusinessConfig(
    businessType: 'Pharmacy',
    currency: 'PKR',
    currencySymbol: 'Rs',
    supplierLabel: 'Distributor',
    itemLabel: 'Medicine',
    itemsLabel: 'Medicines',
    invoiceHint:
        'Pharmacy/medical store invoice. Products are medicines with name, brand, batch number, expiry date, and dosage strength.',
    productFields: [
      ProductField(key: 'name',     label: 'Medicine Name', required: true, hint: 'Paracetamol'),
      ProductField(key: 'brand',    label: 'Manufacturer',  hint: 'Gsk'),
      ProductField(key: 'dosage',   label: 'Dosage/Strength', hint: '500mg'),
      ProductField(key: 'pack',     label: 'Pack Size',     hint: '10 tablets'),
      ProductField(key: 'batch',    label: 'Batch No',      isIdentifier: true),
      ProductField(key: 'expiry',   label: 'Expiry Date',   type: FieldType.date),
    ],
  );

  // ── 🛒 Grocery Store ────────────────────────────────────────────────────────
  static const groceryStore = BusinessConfig(
    businessType: 'Grocery Store',
    currency: 'PKR',
    currencySymbol: 'Rs',
    supplierLabel: 'Vendor',
    itemLabel: 'Product',
    itemsLabel: 'Products',
    invoiceHint:
        'Grocery/general store invoice. Products are food items, household goods, beverages with name, brand, quantity unit.',
    productFields: [
      ProductField(key: 'name',     label: 'Product Name', required: true, hint: 'Rice'),
      ProductField(key: 'brand',    label: 'Brand',        hint: 'Falak'),
      ProductField(key: 'category', label: 'Category',     hint: 'Food / Beverages'),
      ProductField(key: 'unit',     label: 'Unit',         hint: 'kg / piece / box',
                   type: FieldType.select,
                   options: ['kg', 'gram', 'piece', 'box', 'dozen', 'litre', 'ml']),
    ],
  );

  // ── 👗 Clothing / Garment Store ─────────────────────────────────────────────
  static const clothingStore = BusinessConfig(
    businessType: 'Clothing Store',
    currency: 'PKR',
    currencySymbol: 'Rs',
    supplierLabel: 'Supplier',
    itemLabel: 'Item',
    itemsLabel: 'Items',
    invoiceHint:
        'Clothing/garment store invoice. Products are clothes with brand, type, size, color, and fabric/material.',
    productFields: [
      ProductField(key: 'brand',    label: 'Brand',     required: true, hint: 'Gul Ahmed'),
      ProductField(key: 'type',     label: 'Type',      required: true, hint: 'Shirt / Pant / Suit'),
      ProductField(key: 'size',     label: 'Size',      hint: 'S / M / L / XL',
                   type: FieldType.select,
                   options: ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'Free Size']),
      ProductField(key: 'color',    label: 'Color',     hint: 'White'),
      ProductField(key: 'material', label: 'Fabric',    hint: 'Cotton / Linen'),
      ProductField(key: 'article',  label: 'Article No', isIdentifier: true),
    ],
  );

  // ── 🔧 Auto Parts / Spare Parts ─────────────────────────────────────────────
  static const autoParts = BusinessConfig(
    businessType: 'Auto Parts Shop',
    currency: 'PKR',
    currencySymbol: 'Rs',
    supplierLabel: 'Supplier',
    itemLabel: 'Part',
    itemsLabel: 'Parts',
    invoiceHint:
        'Auto parts / spare parts shop invoice. Products are vehicle parts with part number, name, brand, compatible vehicle model.',
    productFields: [
      ProductField(key: 'name',       label: 'Part Name',       required: true, hint: 'Oil Filter'),
      ProductField(key: 'part_no',    label: 'Part Number',     isIdentifier: true),
      ProductField(key: 'brand',      label: 'Brand',           hint: 'Bosch / Denso'),
      ProductField(key: 'compatible', label: 'Compatible With', hint: 'Toyota Corolla 2015-2020'),
      ProductField(key: 'condition',  label: 'Condition',       type: FieldType.select,
                   options: ['New', 'Used', 'Refurbished']),
    ],
  );

  // ── 💻 Electronics / Computer Shop ─────────────────────────────────────────
  static const electronicsShop = BusinessConfig(
    businessType: 'Electronics Shop',
    currency: 'PKR',
    currencySymbol: 'Rs',
    supplierLabel: 'Supplier',
    itemLabel: 'Product',
    itemsLabel: 'Products',
    invoiceHint:
        'Electronics/computer shop invoice. Products are electronic items with brand, model, serial number, specs.',
    productFields: [
      ProductField(key: 'brand',    label: 'Brand',    required: true, hint: 'Dell'),
      ProductField(key: 'model',    label: 'Model',    required: true, hint: 'Inspiron 15'),
      ProductField(key: 'category', label: 'Category', hint: 'Laptop / Printer / Monitor'),
      ProductField(key: 'specs',    label: 'Specs',    hint: 'i5 / 8GB / 512GB'),
      ProductField(key: 'serial',   label: 'Serial No', isIdentifier: true),
    ],
  );

  // ── 📚 Bookstore / Stationery ───────────────────────────────────────────────
  static const bookstore = BusinessConfig(
    businessType: 'Bookstore',
    currency: 'PKR',
    currencySymbol: 'Rs',
    supplierLabel: 'Publisher / Distributor',
    itemLabel: 'Book',
    itemsLabel: 'Books',
    invoiceHint:
        'Bookstore or stationery shop invoice. Products are books with title, author, ISBN, publisher, edition.',
    productFields: [
      ProductField(key: 'title',     label: 'Title',     required: true, hint: 'Mathematics 9'),
      ProductField(key: 'author',    label: 'Author',    hint: 'Dr. Karamat'),
      ProductField(key: 'publisher', label: 'Publisher', hint: 'Punjab Textbook Board'),
      ProductField(key: 'isbn',      label: 'ISBN',      isIdentifier: true),
      ProductField(key: 'edition',   label: 'Edition',   hint: '2024'),
      ProductField(key: 'subject',   label: 'Subject',   hint: 'Science / Arts / Commerce'),
    ],
  );

  // ── 🍕 Restaurant / Food ────────────────────────────────────────────────────
  static const restaurant = BusinessConfig(
    businessType: 'Restaurant / Cafe',
    currency: 'PKR',
    currencySymbol: 'Rs',
    supplierLabel: 'Supplier',
    itemLabel: 'Ingredient',
    itemsLabel: 'Ingredients',
    invoiceHint:
        'Restaurant or cafe supply invoice. Products are raw ingredients and food supplies with name, category, unit of measure.',
    productFields: [
      ProductField(key: 'name',     label: 'Item Name', required: true, hint: 'Chicken'),
      ProductField(key: 'category', label: 'Category',  hint: 'Meat / Vegetable / Spice'),
      ProductField(key: 'unit',     label: 'Unit',      hint: 'kg / litre / box',
                   type: FieldType.select,
                   options: ['kg', 'gram', 'litre', 'ml', 'piece', 'box', 'bag']),
      ProductField(key: 'brand',    label: 'Brand',     hint: 'National / Shan'),
    ],
  );

  /// All presets — used in the business selector screen
  static const all = [
    mobileShop,
    pharmacy,
    groceryStore,
    clothingStore,
    autoParts,
    electronicsShop,
    bookstore,
    restaurant,
  ];
}
