import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/ocr_service.dart';
import '../../services/cloudinary_service.dart';
import '../../services/gemini_service.dart';
import '../../app/theme.dart';

class AddSaleScreen extends StatefulWidget {
  const AddSaleScreen({super.key});
  @override State<AddSaleScreen> createState() => _AddSaleScreenState();
}

class _AddSaleScreenState extends State<AddSaleScreen> {
  final _customerName  = TextEditingController();
  final _customerPhone = TextEditingController();
  String _paymentMethod = 'cash';

  final _searchCtrl = TextEditingController();
  List _searchResults = [];
  bool _searching = false;
  bool _scanning  = false;

  File?   _slipImage;
  String? _slipImageUrl;
  bool    _uploadingSlip = false;

  List<_SaleItem> _selected = [];
  bool _saving = false;

  @override void dispose() {
    _customerName.dispose(); _customerPhone.dispose();
    _searchCtrl.dispose(); super.dispose();
  }

  // ── Scan phone IMEI from camera ───────────────────────────
  Future<void> _scanImei() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 90);
    if (picked == null) return;
    setState(() => _scanning = true);
    try {
      final rawText = await OcrService.extractText(File(picked.path));
      final imeis   = OcrService.extractImeis(rawText);
      if (imeis.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No IMEI found. Try typing manually.'),
            backgroundColor: Colors.orange));
        setState(() => _scanning = false);
        return;
      }
      final imei = imeis.first;
      final data = await ApiService.get('/inventory',
          params: {'status': 'in_stock', 'q': imei}, auth: true);
      if ((data as List).isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('IMEI $imei not found in stock'),
            backgroundColor: AppTheme.error));
        setState(() => _scanning = false);
        return;
      }
      _addItem(data.first);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ ${data.first['brand']} ${data.first['model']} added'),
          backgroundColor: AppTheme.secondary));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e'), backgroundColor: AppTheme.error));
    }
    if (mounted) setState(() => _scanning = false);
  }

  // ── Upload sale slip → full auto flow ────────────────────
  Future<void> _pickSlip(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
        source: source, imageQuality: 70, maxWidth: 1200);
    if (picked == null) return;

    final file = File(picked.path);
    setState(() { _slipImage = file; _uploadingSlip = true; });

    try {
      // Vision AI reads the image directly — no ML Kit OCR middleman
      // Much better for handwritten text (brand, model, customer name, phone)
      final extracted = await GeminiService.extractSaleDataFromImage(file);
      if (!mounted) return;

      // Auto-fill customer
      if ((extracted['customer_name'] ?? '').toString().isNotEmpty) {
        _customerName.text = extracted['customer_name'];
      }
      if ((extracted['customer_phone'] ?? '').toString().isNotEmpty) {
        _customerPhone.text = extracted['customer_phone'];
      }
      final pm = extracted['payment_method'];
      if (pm == 'cash' || pm == 'card' || pm == 'transfer') {
        _paymentMethod = pm;
      }

      // Total from slip (fallback if per-item price missing)
      final slipTotal = (extracted['total_amount'] as num?)?.toDouble() ?? 0.0;
      final items = (extracted['items'] as List?) ?? [];

      for (final it in items) {
        final brand     = (it['brand'] ?? '').toString().trim();
        final model     = (it['model'] ?? '').toString().trim();
        // Clean IMEI: remove spaces/dashes that OCR inserts, must be 15 digits
        final imei      = OcrService.cleanImei((it['imei'] ?? '').toString().trim()) ?? '';
        double salePrice = (it['sale_price'] as num?)?.toDouble() ?? 0.0;

        // If no per-item price but slip has total, use total ÷ items
        if (salePrice == 0 && slipTotal > 0 && items.isNotEmpty) {
          salePrice = slipTotal / items.length;
        }

        // 1) Find by IMEI
        if (imei.length == 15) {
          try {
            final inv = await ApiService.get('/inventory',
                params: {'status': 'in_stock', 'q': imei}, auth: true);
            if ((inv as List).isNotEmpty) {
              _addItem(inv.first);
              if (salePrice > 0) _selected.last.salePrice.text = salePrice.toStringAsFixed(0);
              setState(() {});
              continue;
            }
          } catch (_) {}
        }

        // 2) Find by brand+model
        if (brand.isNotEmpty || model.isNotEmpty) {
          try {
            final inv = await ApiService.get('/inventory',
                params: {'status': 'in_stock', 'q': '$brand $model'.trim()}, auth: true);
            if ((inv as List).isNotEmpty) {
              _addItem(inv.first);
              if (salePrice > 0) _selected.last.salePrice.text = salePrice.toStringAsFixed(0);
              setState(() {});
              continue;
            }
          } catch (_) {}
        }

        // 3) Not in stock → ask purchase price → auto-create purchase
        if (mounted) {
          await _askPurchasePrice(
              brand: brand, model: model, imei: imei, salePrice: salePrice);
        }
      }

      // Cloudinary in background
      if (mounted) setState(() => _uploadingSlip = false);
      CloudinaryService.uploadInvoice(file).then((url) {
        _slipImageUrl = url;
        if (mounted) setState(() {});
      }).catchError((_) { _slipImageUrl = null; });

      // If OCR found no items, let user pick from stock manually
      if (items.isEmpty && mounted) {
        await _pickFromStock(slipTotal: slipTotal);
      }

      // After processing:
      // • All prices filled → save immediately (no extra tap needed)
      // • Missing prices  → show confirm sheet so user can type them
      if (mounted && _selected.isNotEmpty) {
        final allPriced = _selected.every(
            (s) => (double.tryParse(s.salePrice.text) ?? 0) > 0);
        if (allPriced) {
          await _save(); // direct save — user already entered all data
        } else {
          await _showSaleConfirmSheet(); // still needs price input
        }
      }

    } catch (e) {
      if (mounted) {
        setState(() => _uploadingSlip = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error reading slip: $e'),
                backgroundColor: AppTheme.error));
      }
    }
  }

  // ── No phones read from slip → let user pick from stock ──
  Future<void> _pickFromStock({double slipTotal = 0}) async {
    final searchCtrl = TextEditingController();
    List results     = [];
    bool searching   = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.search, color: Colors.orange),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Which phone was sold?',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text('Slip read — but phone not detected. Search your stock:',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ])),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: searchCtrl,
              autofocus: true,
              onChanged: (q) async {
                if (q.trim().length < 2) { setS(() { results = []; searching = false; }); return; }
                setS(() => searching = true);
                try {
                  final res = await ApiService.get('/inventory',
                      params: {'status': 'in_stock', 'q': q}, auth: true);
                  setS(() { results = res as List; searching = false; });
                } catch (_) {
                  setS(() => searching = false);
                }
              },
              decoration: const InputDecoration(
                hintText: 'Type brand, model or IMEI...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            if (searching) const Padding(
                padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
            if (results.isNotEmpty) ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final inv  = results[i];
                  final cost = double.tryParse('${inv['purchase_price']}') ?? 0.0;
                  return ListTile(
                    leading: const Icon(Icons.smartphone, color: AppTheme.primary),
                    title: Text('${inv['brand']} ${inv['model']}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        [(inv['imei'] ?? '').isNotEmpty ? 'IMEI: ${inv['imei']}' : null,
                         'Cost: Rs ${NumberFormat('#,##0').format(cost)}']
                            .where((e) => e != null).join('  •  ')),
                    trailing: const Icon(Icons.add_circle, color: AppTheme.secondary),
                    onTap: () async {
                      // Ask sale price before adding
                      final priceCtrl = TextEditingController(
                          text: slipTotal > 0 ? slipTotal.toStringAsFixed(0) : '');
                      final price = await showDialog<double>(
                        context: ctx,
                        builder: (dCtx) => AlertDialog(
                          title: Text('Sale Price for\n${inv['brand']} ${inv['model']}?',
                              style: const TextStyle(fontSize: 16)),
                          content: TextField(
                            controller: priceCtrl,
                            keyboardType: TextInputType.number,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Sale Price *',
                              prefixText: 'Rs ',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(dCtx),
                                child: const Text('Cancel')),
                            ElevatedButton(
                              onPressed: () {
                                final p = double.tryParse(priceCtrl.text.trim());
                                if (p == null || p <= 0) return;
                                Navigator.pop(dCtx, p);
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.secondary,
                                  foregroundColor: Colors.white),
                              child: const Text('Add to Sale'),
                            ),
                          ],
                        ),
                      );
                      priceCtrl.dispose();
                      if (price != null) {
                        _addItem(inv);
                        if (_selected.isNotEmpty) {
                          _selected.last.salePrice.text = price.toStringAsFixed(0);
                        }
                        if (mounted) setState(() {});
                        Navigator.pop(ctx); // close stock picker
                        // prices are set → save will auto-trigger in _pickSlip
                      }
                    },
                  );
                },
              ),
            ),
            if (results.isEmpty && searchCtrl.text.length >= 2 && !searching)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No phones in stock matching that search',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Skip — I\'ll add manually'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Confirm sheet — always shows, prices editable inline ──
  Future<void> _showSaleConfirmSheet() async {
    if (_selected.isEmpty || !mounted) return;
    final fmt = NumberFormat('#,##0', 'en_US');

    // Local price controllers so the sheet is self-contained
    final priceCtrl = {
      for (final item in _selected)
        item.inventoryId: TextEditingController(text: item.salePrice.text)
    };

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          double sheetSale = _selected.fold(0,
              (s, e) => s + (double.tryParse(priceCtrl[e.inventoryId]?.text ?? '') ?? 0));
          double sheetProfit = sheetSale - _totalCost;
          bool allPriced = _selected.every(
              (e) => (double.tryParse(priceCtrl[e.inventoryId]?.text ?? '') ?? 0) > 0);

          return Padding(
            padding: EdgeInsets.only(
                left: 20, right: 20, top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Row(children: [
                Container(width: 42, height: 42,
                    decoration: BoxDecoration(
                        color: AppTheme.secondary.withOpacity(0.12), shape: BoxShape.circle),
                    child: const Icon(Icons.check_circle, color: AppTheme.secondary)),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Confirm Sale', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text('Review prices, then confirm to save', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ])),
              ]),
              const SizedBox(height: 14),

              // Each item with editable price
              ..._selected.map((item) {
                final ctrl = priceCtrl[item.inventoryId]!;
                final sp = double.tryParse(ctrl.text) ?? 0;
                final profit = sp - item.purchasePrice;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sp > 0
                          ? Colors.green.shade200 : Colors.orange.shade200)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.smartphone, color: AppTheme.primary, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text(item.label,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    ]),
                    if (item.imei.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 22, top: 2),
                        child: Text('IMEI: ${item.imei}',
                            style: const TextStyle(fontSize: 10, color: Colors.grey,
                                fontFamily: 'monospace')),
                      ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setS(() {}),
                        decoration: InputDecoration(
                          labelText: sp > 0 ? 'Sale Price' : 'Sale Price *',
                          prefixText: 'Rs ',
                          isDense: true,
                          filled: sp <= 0,
                          fillColor: Colors.orange.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      )),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('Cost: Rs ${fmt.format(item.purchasePrice)}',
                            style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        Text(profit >= 0
                            ? '+Rs ${fmt.format(profit)}' : '-Rs ${fmt.format(profit.abs())}',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                                color: profit >= 0 ? AppTheme.secondary : AppTheme.error)),
                      ]),
                    ]),
                  ]),
                );
              }),

              if (_customerName.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(_customerName.text,
                        style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    if (_customerPhone.text.isNotEmpty)
                      Text('  •  ${_customerPhone.text}',
                          style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ]),
                ),

              const Divider(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total Sale', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('Rs ${fmt.format(sheetSale)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16,
                        color: AppTheme.primary)),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Profit', style: TextStyle(color: Colors.grey, fontSize: 13)),
                Text('Rs ${fmt.format(sheetProfit)}',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
                        color: sheetProfit >= 0 ? AppTheme.secondary : AppTheme.error)),
              ]),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: allPriced ? () => Navigator.pop(ctx, true) : null,
                  icon: const Icon(Icons.check),
                  label: Text(allPriced
                      ? 'Confirm Sale  •  Rs ${fmt.format(sheetSale)}'
                      : 'Enter sale price above first'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary, foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
              ),
            ]),
          );
        },
      ),
    );

    if (confirmed == true && mounted) {
      // Copy prices from sheet back to items
      for (final item in _selected) {
        final t = priceCtrl[item.inventoryId]?.text ?? '';
        if (t.isNotEmpty) item.salePrice.text = t;
      }
      await _save();
    }
    // Dispose controllers
    for (final c in priceCtrl.values) c.dispose();
  }

  // ── Phone not in stock → ask purchase price → create purchase ──
  Future<void> _askPurchasePrice({
    required String brand,
    required String model,
    required String imei,
    required double salePrice,
  }) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _PurchasePriceSheet(
        brand: brand, model: model, imei: imei, salePrice: salePrice,
        initialCustomerName:  _customerName.text,
        initialCustomerPhone: _customerPhone.text,
      ),
    );

    if (result == null || !mounted) return;

    // Update customer fields if user filled them in the sheet
    final custName  = (result['customer_name']  ?? '').toString().trim();
    final custPhone = (result['customer_phone'] ?? '').toString().trim();
    if (custName.isNotEmpty  && _customerName.text.isEmpty)  _customerName.text  = custName;
    if (custPhone.isNotEmpty && _customerPhone.text.isEmpty) _customerPhone.text = custPhone;

    final purchasePrice  = (result['purchase_price'] as double?) ?? 0.0;
    final finalSalePrice = (result['sale_price']     as double?) ?? salePrice;
    final finalBrand     = (result['brand']          as String?) ?? brand;
    final finalModel     = (result['model']          as String?) ?? model;
    final finalImei      = (result['imei']           as String?) ?? imei;

    if (purchasePrice <= 0) return;

    try {
      // 1. Create / find product
      final product = await ApiService.post('/products', {
        'brand':   finalBrand.isEmpty ? 'Unknown' : finalBrand,
        'model':   finalModel.isEmpty ? 'Unknown' : finalModel,
        'storage': '', 'color': '',
      }, auth: true);
      final productId = product['id'];

      // 2. Create purchase — PHP creates the inventory item as 'in_stock'
      final purchaseResult = await ApiService.post('/purchases', {
        'invoice_date': DateTime.now().toIso8601String().substring(0, 10),
        'items': [{
          'product_id': productId,
          'imei':       finalImei.length == 15 ? finalImei : null,
          'unit_price': purchasePrice,
          'quantity':   1,
        }],
      }, auth: true);

      // 3. Fetch inventory via purchase ID — reliable, no fuzzy search needed
      final purchaseId = purchaseResult['id'];
      final purchaseDetails =
          await ApiService.get('/purchases/$purchaseId', auth: true);
      List inv = (purchaseDetails['items'] as List?) ?? [];

      // Fallback: IMEI search if purchase details failed
      if (inv.isEmpty && finalImei.length == 15) {
        final res = await ApiService.get('/inventory',
            params: {'status': 'in_stock', 'q': finalImei}, auth: true);
        inv = res as List;
      }

      if (inv.isNotEmpty) {
        _addItem(inv.first);
        if (finalSalePrice > 0) {
          _selected.last.salePrice.text = finalSalePrice.toStringAsFixed(0);
        }
        if (mounted) setState(() {});
      } else {
        // Purchase created but can't link — tell user to search manually
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Purchase saved. Search the phone below to add it to the sale.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 6)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error));
    }
  }

  Widget _dlgField(TextEditingController ctrl, String label, IconData icon,
      {String? prefix, TextInputType? type}) =>
      TextField(
        controller: ctrl, keyboardType: type,
        decoration: InputDecoration(
          labelText: label, prefixIcon: Icon(icon), prefixText: prefix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      );

  void _removeSlip() => setState(() { _slipImage = null; _slipImageUrl = null; });

  // ── Manual inventory search ───────────────────────────────
  Future<void> _search(String q) async {
    if (q.trim().length < 2) { setState(() => _searchResults = []); return; }
    setState(() => _searching = true);
    try {
      final data = await ApiService.get('/inventory',
          params: {'status': 'in_stock', 'q': q}, auth: true);
      if (mounted) setState(() { _searchResults = data; _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _addItem(Map inv) {
    if (_selected.any((s) => s.inventoryId == inv['id'])) return;
    final cost = double.tryParse('${inv['purchase_price']}') ?? 0.0;
    setState(() {
      _selected.add(_SaleItem(
        inventoryId:   inv['id'] is int ? inv['id'] : int.tryParse('${inv['id']}') ?? 0,
        label:         '${inv['brand']} ${inv['model']} ${inv['storage'] ?? ''}'.trim(),
        imei:          inv['imei'] ?? '',
        purchasePrice: cost,
      ));
      _searchResults = [];
      _searchCtrl.clear();
    });
  }

  void _removeItem(int i) => setState(() => _selected.removeAt(i));

  double get _totalSale   => _selected.fold(0, (s, e) => s + (double.tryParse(e.salePrice.text) ?? 0));
  double get _totalCost   => _selected.fold(0, (s, e) => s + e.purchasePrice);
  double get _totalProfit => _totalSale - _totalCost;

  // ── Save sale to API ──────────────────────────────────────
  Future<void> _save() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add at least one phone'), backgroundColor: AppTheme.error));
      return;
    }
    for (final item in _selected) {
      if ((double.tryParse(item.salePrice.text) ?? 0) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Enter sale price for all phones'),
            backgroundColor: AppTheme.error));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await ApiService.post('/sales', {
        'customer_name':  _customerName.text.trim().isEmpty ? null : _customerName.text.trim(),
        'customer_phone': _customerPhone.text.trim().isEmpty ? null : _customerPhone.text.trim(),
        'payment_method': _paymentMethod,
        'image_url':      _slipImageUrl,
        'items': _selected.map((s) => {
          'inventory_id': s.inventoryId,
          'sale_price':   double.parse(s.salePrice.text),
        }).toList(),
      }, auth: true);
      if (mounted) {
        final saved = _totalSale;
        Navigator.pop(context);
        // Show success on the previous screen (sales list)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '✓ Sale saved! Rs ${NumberFormat('#,##0').format(saved)} recorded in Sales & Dashboard'),
            backgroundColor: AppTheme.secondary,
            duration: const Duration(seconds: 4)));
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en_US');
    return Scaffold(
      appBar: AppBar(title: const Text('New Sale')),
      body: _saving
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Recording sale...', style: TextStyle(color: Colors.grey)),
            ]))
          : Column(children: [
              Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [

                // ── SALE SLIP — top priority ─────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppTheme.primary.withOpacity(0.07),
                      AppTheme.secondary.withOpacity(0.07),
                    ]),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.receipt_long, color: AppTheme.primary, size: 20),
                      SizedBox(width: 8),
                      Text('Scan Sale Slip',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      SizedBox(width: 8),
                      Chip(label: Text('Auto', style: TextStyle(fontSize: 10, color: Colors.white)),
                          backgroundColor: AppTheme.secondary,
                          padding: EdgeInsets.zero, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    ]),
                    const SizedBox(height: 4),
                    const Text(
                      'Reads customer, IMEI & price. If phone not in stock, asks purchase price and records both Purchase & Sale.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    _slipImage == null
                        ? Row(children: [
                            Expanded(child: ElevatedButton.icon(
                              onPressed: _uploadingSlip ? null : () => _pickSlip(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt, size: 18),
                              label: const Text('Camera'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(46),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            )),
                            const SizedBox(width: 10),
                            Expanded(child: OutlinedButton.icon(
                              onPressed: _uploadingSlip ? null : () => _pickSlip(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library, size: 18),
                              label: const Text('Gallery'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            )),
                          ])
                        : Stack(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_slipImage!,
                                  width: double.infinity, height: 160, fit: BoxFit.cover),
                            ),
                            if (_uploadingSlip)
                              Positioned.fill(child: Container(
                                decoration: BoxDecoration(color: Colors.black54,
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Center(child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(color: Colors.white),
                                    SizedBox(height: 8),
                                    Text('Reading slip...', style: TextStyle(color: Colors.white, fontSize: 14)),
                                  ],
                                )),
                              )),
                            if (!_uploadingSlip && _slipImageUrl != null)
                              Positioned(top: 8, left: 8, child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: AppTheme.secondary,
                                    borderRadius: BorderRadius.circular(8)),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.cloud_done, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('Saved', style: TextStyle(color: Colors.white, fontSize: 12)),
                                ]),
                              )),
                            Positioned(top: 8, right: 8, child: GestureDetector(
                              onTap: _uploadingSlip ? null : _removeSlip,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                    color: Colors.red, shape: BoxShape.circle),
                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                              ),
                            )),
                            Positioned(bottom: 8, right: 8, child: GestureDetector(
                              onTap: () => _pickSlip(ImageSource.camera),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8)),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.camera_alt, color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text('Retake', style: TextStyle(color: Colors.white, fontSize: 12)),
                                ]),
                              ),
                            )),
                          ]),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── Divider ─────────────────────────────────
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OR ADD MANUALLY',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500,
                            fontWeight: FontWeight.w600)),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 20),

                // ── Scan IMEI ───────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.secondary.withOpacity(0.15)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                          color: AppTheme.secondary.withOpacity(0.12), shape: BoxShape.circle),
                      child: _scanning
                          ? const Padding(padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.qr_code_scanner, color: AppTheme.secondary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Scan IMEI', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('Photo of box to find in stock', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ])),
                    ElevatedButton(
                      onPressed: _scanning ? null : _scanImei,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondary, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Scan'),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Manual search ────────────────────────────
                _label('Search Stock'),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl, onChanged: _search,
                  decoration: const InputDecoration(
                    hintText: 'Type IMEI, brand or model...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                if (_searching) const Padding(
                    padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
                if (_searchResults.isNotEmpty) Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8)],
                  ),
                  child: Column(children: _searchResults.take(8).map((inv) {
                    final cost = double.tryParse('${inv['purchase_price']}') ?? 0.0;
                    return InkWell(
                      onTap: () => _addItem(inv),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(children: [
                          const Icon(Icons.smartphone, color: AppTheme.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${inv['brand']} ${inv['model']}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            if ((inv['imei'] ?? '').isNotEmpty)
                              Text('IMEI: ${inv['imei']}',
                                  style: const TextStyle(fontSize: 11, color: Colors.blueGrey,
                                      fontFamily: 'monospace')),
                          ])),
                          Text('Rs ${fmt.format(cost)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(width: 8),
                          const Icon(Icons.add_circle, color: AppTheme.secondary),
                        ]),
                      ),
                    );
                  }).toList()),
                ),
                const SizedBox(height: 20),

                // ── Selected phones ──────────────────────────
                if (_selected.isNotEmpty) ...[
                  _label('Sale Items (${_selected.length})'),
                  const SizedBox(height: 8),
                  ..._selected.asMap().entries.map((e) => _buildItem(e.key, e.value, fmt)),
                  const Divider(height: 24),
                  _totalRow('Total Cost',  'Rs ${fmt.format(_totalCost)}',  Colors.grey),
                  _totalRow('Total Sale',  'Rs ${fmt.format(_totalSale)}',  AppTheme.primary),
                  _totalRow('Profit',      'Rs ${fmt.format(_totalProfit)}',
                      _totalProfit >= 0 ? AppTheme.secondary : AppTheme.error),
                  const SizedBox(height: 20),
                ],

                // ── Customer ─────────────────────────────────
                _label('Customer (optional)'),
                const SizedBox(height: 10),
                TextField(controller: _customerName,
                    decoration: const InputDecoration(
                        labelText: 'Customer Name', prefixIcon: Icon(Icons.person_outline))),
                const SizedBox(height: 10),
                TextField(controller: _customerPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined))),
                const SizedBox(height: 16),

                // ── Payment method ───────────────────────────
                _label('Payment Method'),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'cash',     label: Text('Cash'),     icon: Icon(Icons.money)),
                    ButtonSegment(value: 'card',     label: Text('Card'),     icon: Icon(Icons.credit_card)),
                    ButtonSegment(value: 'transfer', label: Text('Transfer'), icon: Icon(Icons.swap_horiz)),
                  ],
                  selected: {_paymentMethod},
                  onSelectionChanged: (s) => setState(() => _paymentMethod = s.first),
                ),
                const SizedBox(height: 80),
              ])),

              // ── Confirm button (for manual flow) ─────────────
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    onPressed: (_uploadingSlip) ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(_uploadingSlip
                        ? 'Reading slip...'
                        : 'Confirm Sale  •  Rs ${NumberFormat('#,##0').format(_totalSale)}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondary, foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
            ]),
    );
  }

  Widget _buildItem(int i, _SaleItem item, NumberFormat fmt) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E8E8))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.smartphone, color: AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w700))),
        IconButton(onPressed: () => _removeItem(i),
            icon: const Icon(Icons.close, color: Colors.red, size: 18),
            padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      ]),
      if (item.imei.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 26, bottom: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade200)),
            child: Text('IMEI: ${item.imei}',
                style: const TextStyle(fontSize: 11, color: Colors.green,
                    fontFamily: 'monospace', fontWeight: FontWeight.w600)),
          ),
        ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(
          controller: item.salePrice,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Sale Price *', hintText: 'e.g. 55000', prefixText: 'Rs ',
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
          ),
        )),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('Profit', style: TextStyle(fontSize: 11, color: Colors.grey)),
          Builder(builder: (_) {
            final profit = (double.tryParse(item.salePrice.text) ?? 0) - item.purchasePrice;
            return Text('Rs ${fmt.format(profit)}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                    color: profit >= 0 ? AppTheme.secondary : AppTheme.error));
          }),
        ]),
      ]),
    ]),
  );

  Widget _totalRow(String l, String v, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(color: Colors.grey)),
      Text(v, style: TextStyle(fontWeight: FontWeight.w700, color: c, fontSize: 15)),
    ]),
  );

  Widget _label(String t) => Text(t,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey));
}

class _SaleItem {
  final int    inventoryId;
  final String label;
  final String imei;
  final double purchasePrice;
  final salePrice = TextEditingController();
  _SaleItem({required this.inventoryId, required this.label,
             required this.imei, required this.purchasePrice});
}

// ── "Phone Not in Stock" sheet — proper StatefulWidget ───────────────────────
class _PurchasePriceSheet extends StatefulWidget {
  final String brand, model, imei;
  final double salePrice;
  final String initialCustomerName, initialCustomerPhone;

  const _PurchasePriceSheet({
    required this.brand, required this.model,
    required this.imei,  required this.salePrice,
    required this.initialCustomerName,
    required this.initialCustomerPhone,
  });

  @override
  State<_PurchasePriceSheet> createState() => _PurchasePriceSheetState();
}

class _PurchasePriceSheetState extends State<_PurchasePriceSheet> {
  late final TextEditingController brandCtrl;
  late final TextEditingController modelCtrl;
  late final TextEditingController imeiCtrl;
  late final TextEditingController purchasePriceCtrl;
  late final TextEditingController salePriceCtrl;
  late final TextEditingController customerNameCtrl;
  late final TextEditingController customerPhoneCtrl;
  String? errorMsg;

  @override
  void initState() {
    super.initState();
    brandCtrl         = TextEditingController(text: widget.brand);
    modelCtrl         = TextEditingController(text: widget.model);
    imeiCtrl          = TextEditingController(text: widget.imei);
    purchasePriceCtrl = TextEditingController();
    salePriceCtrl     = TextEditingController(
        text: widget.salePrice > 0 ? widget.salePrice.toStringAsFixed(0) : '');
    customerNameCtrl  = TextEditingController(text: widget.initialCustomerName);
    customerPhoneCtrl = TextEditingController(text: widget.initialCustomerPhone);
  }

  @override
  void dispose() {
    brandCtrl.dispose(); modelCtrl.dispose(); imeiCtrl.dispose();
    purchasePriceCtrl.dispose(); salePriceCtrl.dispose();
    customerNameCtrl.dispose(); customerPhoneCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (purchasePriceCtrl.text.trim().isEmpty) {
      setState(() => errorMsg = 'Enter purchase price (what you paid for the phone)');
      return;
    }
    if (salePriceCtrl.text.trim().isEmpty) {
      setState(() => errorMsg = 'Enter sale price (what you sold it for)');
      return;
    }
    Navigator.pop(context, {
      'purchase_price':  double.tryParse(purchasePriceCtrl.text.trim()) ?? 0.0,
      'sale_price':      double.tryParse(salePriceCtrl.text.trim()) ?? 0.0,
      'brand':           brandCtrl.text.trim(),
      'model':           modelCtrl.text.trim(),
      'imei':            imeiCtrl.text.trim(),
      'customer_name':   customerNameCtrl.text.trim(),
      'customer_phone':  customerPhoneCtrl.text.trim(),
    });
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? type, bool autofocus = false}) =>
      TextField(
        controller: ctrl,
        keyboardType: type,
        autofocus: autofocus,
        onChanged: (_) { if (errorMsg != null) setState(() => errorMsg = null); },
        decoration: InputDecoration(
          labelText: label, prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Container(width: 44, height: 44,
                decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12), shape: BoxShape.circle),
                child: const Icon(Icons.smartphone, color: Colors.orange),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Phone Not in Stock',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text('Enter details — saved in Purchases & Sale',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ])),
            ]),
            const SizedBox(height: 20),

            // Brand + Model
            Row(children: [
              Expanded(child: _field(brandCtrl, 'Brand', Icons.business)),
              const SizedBox(width: 12),
              Expanded(child: _field(modelCtrl, 'Model', Icons.smartphone)),
            ]),
            const SizedBox(height: 12),

            // IMEI
            _field(imeiCtrl, 'IMEI (15 digits)', Icons.tag,
                type: TextInputType.number),
            const SizedBox(height: 12),

            // Purchase + Sale price
            Row(children: [
              Expanded(child: TextField(
                controller: purchasePriceCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                onChanged: (_) { if (errorMsg != null) setState(() => errorMsg = null); },
                decoration: InputDecoration(
                  labelText: 'Purchase Price *', hintText: 'What you paid',
                  prefixText: 'Rs ',
                  prefixIcon: const Icon(Icons.shopping_bag_outlined, color: AppTheme.primary),
                  filled: true, fillColor: AppTheme.primary.withOpacity(0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
                ),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: salePriceCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) { if (errorMsg != null) setState(() => errorMsg = null); },
                decoration: InputDecoration(
                  labelText: 'Sale Price *', hintText: 'What you sold for',
                  prefixText: 'Rs ',
                  prefixIcon: const Icon(Icons.sell_outlined, color: AppTheme.secondary),
                  filled: true, fillColor: AppTheme.secondary.withOpacity(0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.secondary, width: 2)),
                ),
              )),
            ]),
            const SizedBox(height: 12),

            // Customer Name + Phone (pre-filled from OCR, editable)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.person_outline, size: 14, color: Colors.blue),
                  SizedBox(width: 6),
                  Text('Customer Info (optional)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: Colors.blue)),
                  SizedBox(width: 6),
                  Text('— auto-filled from slip if found',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _field(customerNameCtrl, 'Customer Name', Icons.person_outline)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(customerPhoneCtrl, 'Phone Number',
                      Icons.phone_outlined, type: TextInputType.phone)),
                ]),
              ]),
            ),

            if (errorMsg != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(errorMsg!,
                      style: const TextStyle(color: Colors.red, fontSize: 13))),
                ]),
              ),
            ],
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check_circle),
                label: const Text('Save in Purchase & Add to Sale'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Skip this phone'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
