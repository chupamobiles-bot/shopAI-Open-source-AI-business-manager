import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../app/theme.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List _items    = [];
  bool _loading  = true;
  String _search = '';

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.get('/inventory',
          params: {'status': 'in_stock', if (_search.isNotEmpty) 'q': _search});
      if (mounted) setState(() { _items = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en_US');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (v) { _search = v; _load(); },
            decoration: const InputDecoration(
              hintText: 'Search by IMEI, brand or model...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        // Count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text('${_items.length} phones in stock',
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 8),
        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No phones in stock', style: TextStyle(color: Colors.grey)),
                      ]))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _items.length,
                        itemBuilder: (ctx, i) {
                          final item = _items[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
                              ],
                            ),
                            child: Row(children: [
                              Container(
                                width: 44, height: 44,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.smartphone, color: AppTheme.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${item['brand']} ${item['model']}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                if ((item['storage'] ?? '').isNotEmpty || (item['color'] ?? '').isNotEmpty)
                                  Text('${item['storage'] ?? ''} ${item['color'] ?? ''}'.trim(),
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                if ((item['imei'] ?? '').isNotEmpty)
                                  Text('IMEI: ${item['imei']}',
                                      style: const TextStyle(fontSize: 11, color: Colors.blueGrey,
                                          fontFamily: 'monospace')),
                              ])),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text('Rs ${fmt.format(num.tryParse('${item['purchase_price']}') ?? 0)}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary)),
                                const Text('Cost', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ]),
                            ]),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}
