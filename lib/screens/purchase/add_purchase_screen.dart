import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/gemini_service.dart';
import '../../services/cloudinary_service.dart';
import '../../services/api_service.dart';
import '../../app/theme.dart';

class AddPurchaseScreen extends StatefulWidget {
  const AddPurchaseScreen({super.key});
  @override State<AddPurchaseScreen> createState() => _AddPurchaseScreenState();
}

class _AddPurchaseScreenState extends State<AddPurchaseScreen> {
  // ── State ─────────────────────────────────────────────────
  File?   _image;
  String  _step    = 'idle'; // idle | scanning | reviewing | saving
  String  _stepMsg = '';

  // Extracted invoice data (editable)
  final _supplier      = TextEditingController();
  final _invoiceNumber = TextEditingController();
  final _invoiceDate   = TextEditingController();
  List<_ItemRow> _items = [];

  String? _imageUrl; // Cloudinary URL after upload

  @override void dispose() {
    _supplier.dispose(); _invoiceNumber.dispose();
    _invoiceDate.dispose(); super.dispose();
  }

  // ── Step 1: Pick image ────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
        source: source, imageQuality: 90, maxWidth: 1920);
    if (picked == null) return;
    setState(() { _image = File(picked.path); _step = 'scanning'; _stepMsg = 'Reading text...'; });
    await _processImage(File(picked.path));
  }

  // ── Step 2: Vision AI reads image directly ───────────────
  Future<void> _processImage(File img) async {
    try {
      setState(() => _stepMsg = 'AI is reading invoice...');

      // Send image directly to Groq Vision — no ML Kit OCR middleman
      final extracted = await GeminiService.extractInvoiceDataFromImage(img);

      // Upload image to Cloudinary in background
      _uploadImageAsync(img);

      // Populate fields
      _supplier.text      = extracted['supplier_name'] ?? '';
      _invoiceNumber.text = extracted['invoice_number'] ?? '';
      _invoiceDate.text   = extracted['invoice_date'] ??
          DateFormat('yyyy-MM-dd').format(DateTime.now());

      final rawItems = (extracted['items'] as List?) ?? [];
      _items = rawItems.map((it) => _ItemRow.fromMap(it)).toList();

      if (_items.isEmpty) _items.add(_ItemRow());

      setState(() => _step = 'reviewing');
    } catch (e) {
      setState(() { _step = 'idle'; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error));
      }
    }
  }

  void _uploadImageAsync(File img) async {
    try {
      _imageUrl = await CloudinaryService.uploadInvoice(img);
    } catch (_) {} // non-blocking
  }

  // ── Step 3: Add/remove item rows ─────────────────────────
  void _addItem()      => setState(() => _items.add(_ItemRow()));
  void _removeItem(int i) => setState(() => _items.removeAt(i));

  // ── Step 4: Save to API ───────────────────────────────────
  Future<void> _save() async {
    // Validate
    for (final item in _items) {
      if (item.brand.text.isEmpty || item.model.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Fill brand & model for all items'),
            backgroundColor: AppTheme.error));
        return;
      }
      if (double.tryParse(item.price.text) == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Enter valid purchase price'),
            backgroundColor: AppTheme.error));
        return;
      }
    }

    setState(() { _step = 'saving'; _stepMsg = 'Creating products...'; });

    try {
      // For each item: ensure product exists, then build purchase items
      final purchaseItems = <Map<String, dynamic>>[];
      for (final item in _items) {
        // Create/get product
        final pRes = await ApiService.post('/products', {
          'brand':   item.brand.text.trim(),
          'model':   item.model.text.trim(),
          'storage': item.storage.text.trim(),
          'color':   item.color.text.trim(),
        }, auth: true);
        final productId = pRes['id'];

        purchaseItems.add({
          'product_id': productId,
          'imei':       item.imei.trim().isEmpty ? null : item.imei.trim(),
          'quantity':   int.tryParse(item.qty.text) ?? 1,
          'unit_price': double.parse(item.price.text),
        });
      }

      setState(() => _stepMsg = 'Saving purchase...');
      await ApiService.post('/purchases', {
        'supplier_name':  _supplier.text.trim(),
        'invoice_number': _invoiceNumber.text.trim(),
        'invoice_date':   _invoiceDate.text.trim(),
        'image_url':      _imageUrl,
        'items':          purchaseItems,
      }, auth: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Purchase saved! Inventory updated.'),
            backgroundColor: AppTheme.secondary));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _step = 'reviewing');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error));
    }
  }

  // ── UI ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Purchase')),
      body: _step == 'idle'
          ? _buildIdleState()
          : _step == 'scanning'
              ? _buildLoading()
              : _step == 'saving'
                  ? _buildLoading()
                  : _buildReviewForm(),
    );
  }

  Widget _buildIdleState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.document_scanner_outlined,
              size: 56, color: AppTheme.primary),
        ),
        const SizedBox(height: 28),
        const Text('Scan Invoice', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Take a photo of the supplier invoice.\nAI will extract all phone details automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, height: 1.5)),
        const SizedBox(height: 36),
        ElevatedButton.icon(
          onPressed: () => _pickImage(ImageSource.camera),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Take Photo'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pickImage(ImageSource.gallery),
          icon: const Icon(Icons.photo_library),
          label: const Text('Choose from Gallery'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]),
    ),
  );

  Widget _buildLoading() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (_image != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(_image!, height: 200, fit: BoxFit.cover),
        ),
      const SizedBox(height: 28),
      const CircularProgressIndicator(),
      const SizedBox(height: 16),
      Text(_stepMsg, style: const TextStyle(color: Colors.grey, fontSize: 15)),
    ]),
  );

  Widget _buildReviewForm() => Column(children: [
    // Invoice image preview
    if (_image != null)
      Container(
        height: 140,
        width: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(image: FileImage(_image!), fit: BoxFit.cover),
        ),
        child: Container(
          color: Colors.black38,
          alignment: Alignment.bottomRight,
          padding: const EdgeInsets.all(10),
          child: TextButton.icon(
            onPressed: () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
            label: const Text('Retake', style: TextStyle(color: Colors.white)),
          ),
        ),
      ),

    Expanded(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Invoice header fields
          _sectionLabel('Invoice Details'),
          const SizedBox(height: 10),
          TextField(controller: _supplier,
              decoration: const InputDecoration(labelText: 'Supplier Name', prefixIcon: Icon(Icons.store))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _invoiceNumber,
                decoration: const InputDecoration(labelText: 'Invoice #', prefixIcon: Icon(Icons.numbers)))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _invoiceDate,
                decoration: const InputDecoration(labelText: 'Date', prefixIcon: Icon(Icons.calendar_today)))),
          ]),
          const SizedBox(height: 20),

          // Items
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _sectionLabel('Phones (${_items.length})'),
            TextButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Phone'),
            ),
          ]),

          ..._items.asMap().entries.map((e) => _ItemCard(
                item: e.value, index: e.key,
                onRemove: () => _removeItem(e.key),
              )),

          const SizedBox(height: 80), // space for button
        ],
      ),
    ),

    // Save button
    Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.save),
        label: Text('Save ${_items.length} Phone(s) to Inventory'),
      ),
    ),
  ]);

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey));
}

// ── Editable item row ─────────────────────────────────────────
class _ItemRow {
  final brand   = TextEditingController();
  final model   = TextEditingController();
  final storage = TextEditingController();
  final color   = TextEditingController();
  final qty     = TextEditingController(text: '1');
  final price   = TextEditingController();
  String imei   = '';

  _ItemRow({String? brand, String? model, String? storage,
            String? color, String? imei, int? qty, double? price}) {
    if (brand   != null) this.brand.text   = brand;
    if (model   != null) this.model.text   = model;
    if (storage != null) this.storage.text = storage;
    if (color   != null) this.color.text   = color;
    if (qty     != null) this.qty.text     = '$qty';
    if (price   != null) this.price.text   = '${price.toStringAsFixed(0)}';
    this.imei = imei ?? '';
  }

  factory _ItemRow.fromMap(Map m) => _ItemRow(
    brand:   m['brand'],
    model:   m['model'],
    storage: m['storage'],
    color:   m['color'],
    imei:    m['imei'],
    qty:     m['quantity'],
    price:   (m['unit_price'] as num?)?.toDouble(),
  );
}

class _ItemCard extends StatelessWidget {
  final _ItemRow item;
  final int index;
  final VoidCallback onRemove;
  const _ItemCard({required this.item, required this.index, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: AppTheme.primary, shape: BoxShape.circle),
            child: Center(child: Text('${index + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 8),
          const Text('Phone', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _tf(item.brand, 'Brand *', hint: 'Samsung')),
          const SizedBox(width: 8),
          Expanded(child: _tf(item.model, 'Model *', hint: 'Galaxy A55')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _tf(item.storage, 'Storage', hint: '128GB')),
          const SizedBox(width: 8),
          Expanded(child: _tf(item.color, 'Color', hint: 'Black')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(flex: 2, child: _tf(item.price, 'Price *',
              hint: '45000', keyboardType: TextInputType.number)),
          const SizedBox(width: 8),
          Expanded(child: _tf(item.qty, 'Qty',
              keyboardType: TextInputType.number)),
        ]),
        if (item.imei.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(children: [
              const Icon(Icons.verified, color: Colors.green, size: 14),
              const SizedBox(width: 6),
              Text('IMEI: ${item.imei}',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace',
                      color: Colors.green, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _tf(TextEditingController ctrl, String label, {
    String? hint,
    TextInputType keyboardType = TextInputType.text,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
        ),
      );
}
