import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../app/theme.dart';
import 'add_purchase_screen.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  List _purchases = [];
  bool _loading   = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.get('/purchases');
      if (mounted) setState(() { _purchases = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAdd() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AddPurchaseScreen()));
    _load();
  }

  // ── Delete purchase ───────────────────────────────────────
  Future<void> _delete(Map p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Purchase?'),
        content: Text(
            'Delete purchase from "${p['supplier_name'] ?? 'Unknown Supplier'}"?\n\n'
            'This also removes the phones from your stock.\n'
            'Cannot delete if phones are already sold.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ApiService.delete('/purchases/${p['id']}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Purchase deleted'),
            backgroundColor: AppTheme.secondary));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.error));
    }
  }

  // ── Edit purchase ─────────────────────────────────────────
  Future<void> _edit(Map p) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EditPurchaseSheet(purchase: p),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Purchase updated'),
          backgroundColor: AppTheme.secondary));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat('#,##0', 'en_US');
    final dateFmt = DateFormat('d MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.add),
        label: const Text('Scan Invoice'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _purchases.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('No purchases yet', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _openAdd,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Scan First Invoice'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                  ),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _purchases.length,
                    itemBuilder: (ctx, i) {
                      final p    = _purchases[i];
                      final date = p['invoice_date'] != null
                          ? dateFmt.format(DateTime.parse(p['invoice_date'])) : 'No date';

                      return Dismissible(
                        key: ValueKey(p['id']),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async { await _delete(p); return false; },
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                              color: AppTheme.error,
                              borderRadius: BorderRadius.circular(14)),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.delete_outline, color: Colors.white, size: 28),
                            Text('Delete', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ]),
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(
                                color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                          ),
                          child: Row(children: [
                            Container(
                              width: 46, height: 46,
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.download, color: Colors.blue),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p['supplier_name'] ?? 'Unknown Supplier',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('$date  •  ${p['unit_count'] ?? 0} phones',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              if ((p['invoice_number'] ?? '').isNotEmpty)
                                Text('Invoice: ${p['invoice_number']}',
                                    style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                            ])),
                            Text('Rs ${fmt.format(num.tryParse('${p['total_amount']}') ?? 0)}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(width: 8),
                            // Edit + Delete buttons
                            Column(children: [
                              GestureDetector(
                                onTap: () => _edit(p),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                      color: AppTheme.primary.withOpacity(0.08),
                                      shape: BoxShape.circle),
                                  child: Icon(Icons.edit_outlined,
                                      color: AppTheme.primary.withOpacity(0.8), size: 16),
                                ),
                              ),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () => _delete(p),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                      color: AppTheme.error.withOpacity(0.08),
                                      shape: BoxShape.circle),
                                  child: Icon(Icons.delete_outline,
                                      color: AppTheme.error.withOpacity(0.7), size: 16),
                                ),
                              ),
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ── Edit Purchase Sheet (proper StatefulWidget to avoid context/lifecycle bugs) ──
class _EditPurchaseSheet extends StatefulWidget {
  final Map purchase;
  const _EditPurchaseSheet({required this.purchase});
  @override
  State<_EditPurchaseSheet> createState() => _EditPurchaseSheetState();
}

class _EditPurchaseSheetState extends State<_EditPurchaseSheet> {
  late final TextEditingController supplierCtrl;
  late final TextEditingController invoiceCtrl;
  late final TextEditingController notesCtrl;
  DateTime? invoiceDate;
  String?   errorMsg;
  bool      saving = false;

  @override
  void initState() {
    super.initState();
    supplierCtrl = TextEditingController(text: widget.purchase['supplier_name'] ?? '');
    invoiceCtrl  = TextEditingController(text: widget.purchase['invoice_number'] ?? '');
    notesCtrl    = TextEditingController(text: widget.purchase['notes'] ?? '');
    invoiceDate  = widget.purchase['invoice_date'] != null
        ? DateTime.tryParse(widget.purchase['invoice_date']) : null;
  }

  @override
  void dispose() {
    supplierCtrl.dispose();
    invoiceCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { saving = true; errorMsg = null; });
    try {
      await ApiService.patch('/purchases/${widget.purchase['id']}', {
        'supplier_name':  supplierCtrl.text.trim().isEmpty ? null : supplierCtrl.text.trim(),
        'invoice_number': invoiceCtrl.text.trim().isEmpty ? null : invoiceCtrl.text.trim(),
        'invoice_date':   invoiceDate?.toIso8601String().substring(0, 10),
        'notes':          notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { saving = false; errorMsg = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Edit Purchase',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
        ]),
        const SizedBox(height: 16),
        TextField(controller: supplierCtrl,
            decoration: const InputDecoration(labelText: 'Supplier Name',
                prefixIcon: Icon(Icons.store_outlined), border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: invoiceCtrl,
            decoration: const InputDecoration(labelText: 'Invoice Number',
                prefixIcon: Icon(Icons.receipt_outlined), border: OutlineInputBorder())),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(
                context: context,
                initialDate: invoiceDate ?? DateTime.now(),
                firstDate: DateTime(2020), lastDate: DateTime.now());
            if (d != null && mounted) setState(() => invoiceDate = d);
          },
          child: InputDecorator(
            decoration: const InputDecoration(
                labelText: 'Invoice Date', prefixIcon: Icon(Icons.calendar_today),
                border: OutlineInputBorder()),
            child: Text(invoiceDate != null
                ? DateFormat('d MMM yyyy').format(invoiceDate!) : 'Tap to pick date'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: notesCtrl, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes',
                prefixIcon: Icon(Icons.notes), border: OutlineInputBorder())),
        if (errorMsg != null) ...[
          const SizedBox(height: 8),
          Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: saving ? null : _save,
            icon: saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: Text(saving ? 'Saving…' : 'Save Changes'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
