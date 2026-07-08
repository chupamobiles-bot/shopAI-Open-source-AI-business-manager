import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../app/theme.dart';
import 'add_sale_screen.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});
  @override State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List _sales   = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final data = await ApiService.get('/sales', auth: true);
      if (mounted) setState(() { _sales = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNewSale() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AddSaleScreen()));
    _load();
  }

  // ── Delete ────────────────────────────────────────────────
  Future<void> _delete(Map sale) async {
    final name = sale['customer_name'] ?? 'Walk-in';
    final amt  = NumberFormat('#,##0').format(
        num.tryParse('${sale['total_amount']}') ?? 0);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sale?'),
        content: Text('Delete sale for $name (Rs $amt)?\n\nPhone(s) will be restored to stock.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
      await ApiService.delete('/sales/${sale['id']}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sale deleted — phone restored to stock'),
            backgroundColor: AppTheme.secondary));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.error));
    }
  }

  // ── Edit (customer info + payment method only) ───────────
  Future<void> _edit(Map sale) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _EditSaleSheet(sale: sale),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sale updated'),
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
        title: const Text('Sales'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewSale,
        icon: const Icon(Icons.add),
        label: const Text('New Sale'),
        backgroundColor: AppTheme.secondary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('No sales yet', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _openNewSale,
                    icon: const Icon(Icons.add),
                    label: const Text('Record First Sale'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary,
                        foregroundColor: Colors.white),
                  ),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    itemCount: _sales.length,
                    itemBuilder: (ctx, i) {
                      final s      = _sales[i];
                      final date   = s['sale_date'] != null
                          ? dateFmt.format(DateTime.parse(s['sale_date'])) : '';
                      final profit = num.tryParse('${s['total_profit']}') ?? 0;
                      final amount = num.tryParse('${s['total_amount']}') ?? 0;

                      return Dismissible(
                        key: ValueKey(s['id']),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async { await _delete(s); return false; },
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(color: AppTheme.error,
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
                                color: AppTheme.secondary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.sell_outlined, color: AppTheme.secondary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s['customer_name'] ?? 'Walk-in Customer',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text('$date  •  ${s['payment_method'] ?? ''}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('Rs ${fmt.format(amount)}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              Text('+Rs ${fmt.format(profit)}',
                                  style: TextStyle(fontSize: 12,
                                      color: profit >= 0 ? AppTheme.secondary : AppTheme.error,
                                      fontWeight: FontWeight.w600)),
                            ]),
                            const SizedBox(width: 8),
                            Column(children: [
                              GestureDetector(
                                onTap: () => _edit(s),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                      color: AppTheme.secondary.withOpacity(0.08),
                                      shape: BoxShape.circle),
                                  child: Icon(Icons.edit_outlined,
                                      color: AppTheme.secondary.withOpacity(0.8), size: 16),
                                ),
                              ),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () => _delete(s),
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

// ── Edit Sale Sheet ───────────────────────────────────────────────────────────
class _EditSaleSheet extends StatefulWidget {
  final Map sale;
  const _EditSaleSheet({required this.sale});
  @override
  State<_EditSaleSheet> createState() => _EditSaleSheetState();
}

class _EditSaleSheetState extends State<_EditSaleSheet> {
  late final TextEditingController nameCtrl;
  late final TextEditingController phoneCtrl;
  late final TextEditingController notesCtrl;
  late String payment;
  DateTime?   saleDate;
  String?     errorMsg;
  bool        saving = false;

  @override
  void initState() {
    super.initState();
    nameCtrl  = TextEditingController(text: widget.sale['customer_name']  ?? '');
    phoneCtrl = TextEditingController(text: widget.sale['customer_phone'] ?? '');
    notesCtrl = TextEditingController(text: widget.sale['notes']          ?? '');
    payment   = widget.sale['payment_method'] ?? 'cash';
    saleDate  = widget.sale['sale_date'] != null
        ? DateTime.tryParse(widget.sale['sale_date']) : null;
  }

  @override
  void dispose() {
    nameCtrl.dispose(); phoneCtrl.dispose(); notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { saving = true; errorMsg = null; });
    try {
      await ApiService.patch('/sales/${widget.sale['id']}', {
        'customer_name':  nameCtrl.text.trim().isEmpty  ? null : nameCtrl.text.trim(),
        'customer_phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
        'payment_method': payment,
        'notes':          notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        if (saleDate != null)
          'sale_date': saleDate!.toIso8601String().substring(0, 10),
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
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Edit Sale',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
          ]),
          const SizedBox(height: 16),

          // Customer Name
          TextField(controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),

          // Phone Number
          TextField(controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder())),
          const SizedBox(height: 14),

          // Payment Method
          const Align(alignment: Alignment.centerLeft,
              child: Text('Payment Method',
                  style: TextStyle(fontSize: 12, color: Colors.grey,
                      fontWeight: FontWeight.w600))),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cash',     label: Text('Cash'),     icon: Icon(Icons.money)),
              ButtonSegment(value: 'card',     label: Text('Card'),     icon: Icon(Icons.credit_card)),
              ButtonSegment(value: 'transfer', label: Text('Transfer'), icon: Icon(Icons.swap_horiz)),
            ],
            selected: {payment},
            onSelectionChanged: (s) => setState(() => payment = s.first),
          ),
          const SizedBox(height: 14),

          // Sale Date
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                  context: context,
                  initialDate: saleDate ?? DateTime.now(),
                  firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null && mounted) setState(() => saleDate = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Sale Date',
                  prefixIcon: Icon(Icons.calendar_today),
                  border: OutlineInputBorder()),
              child: Text(saleDate != null
                  ? DateFormat('d MMM yyyy').format(saleDate!) : 'Tap to change date'),
            ),
          ),
          const SizedBox(height: 12),

          // Notes
          TextField(controller: notesCtrl, maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'e.g. warranty given, accessories included...',
                  prefixIcon: Icon(Icons.notes),
                  border: OutlineInputBorder())),

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
                  backgroundColor: AppTheme.secondary, foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
