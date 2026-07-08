/// ─────────────────────────────────────────────────────────────────────────────
/// ShopAI — Universal Business Config
/// ─────────────────────────────────────────────────────────────────────────────
/// Change ONE config to turn this app into a manager for any shop type.
/// The AI prompts, forms, and inventory screens all adapt automatically.
/// ─────────────────────────────────────────────────────────────────────────────

enum FieldType { text, number, date, select }

/// A single field on a product (e.g. "Brand", "Expiry Date", "Serial No")
class ProductField {
  final String key;           // used as JSON key & DB column
  final String label;         // shown in UI
  final FieldType type;
  final bool required;
  final bool isIdentifier;    // unique per unit (IMEI, serial no, batch no)
  final String? hint;         // placeholder text
  final List<String>? options; // for FieldType.select

  const ProductField({
    required this.key,
    required this.label,
    this.type = FieldType.text,
    this.required = false,
    this.isIdentifier = false,
    this.hint,
    this.options,
  });

  Map<String, dynamic> toMap() => {
    'key': key,
    'label': label,
    'type': type.name,
    'required': required,
    'isIdentifier': isIdentifier,
  };
}

/// Full config for a business — change this to switch shop types
class BusinessConfig {
  final String businessType;        // e.g. "Pharmacy", "Grocery Store"
  final String currency;            // e.g. "PKR", "USD", "INR"
  final String currencySymbol;      // e.g. "Rs", "$", "₹"

  /// What fields each product/item has
  final List<ProductField> productFields;

  /// Label overrides for common UI strings
  final String supplierLabel;       // "Supplier" / "Vendor" / "Distributor"
  final String itemLabel;           // "Phone" / "Medicine" / "Item"
  final String itemsLabel;          // plural

  /// AI hint — helps Groq understand what kind of invoice to expect
  final String invoiceHint;

  const BusinessConfig({
    required this.businessType,
    required this.currency,
    required this.currencySymbol,
    required this.productFields,
    this.supplierLabel = 'Supplier',
    this.itemLabel = 'Item',
    this.itemsLabel = 'Items',
    required this.invoiceHint,
  });

  /// The identifier field (IMEI / serial / batch) — null if none
  ProductField? get identifierField =>
      productFields.where((f) => f.isIdentifier).isNotEmpty
          ? productFields.firstWhere((f) => f.isIdentifier)
          : null;

  /// Required fields only
  List<ProductField> get requiredFields =>
      productFields.where((f) => f.required).toList();

  /// Build the JSON schema string for AI prompt injection
  String get aiProductSchema {
    final fields = productFields
        .map((f) => '      "${f.key}": "${f.label}${f.required ? " (required)" : " or null"}"')
        .join(',\n');
    return '{\n$fields\n    }';
  }
}
