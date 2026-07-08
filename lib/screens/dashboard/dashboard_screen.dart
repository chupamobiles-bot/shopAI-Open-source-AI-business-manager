import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../app/theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.get('/dashboard');
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopName = context.read<AuthService>().shopName;
    final fmt      = NumberFormat('#,##0', 'en_US');
    final today    = _data?['today']      as Map? ?? {};
    final month    = _data?['this_month'] as Map? ?? {};
    final inStock  = _data?['in_stock']   as int? ?? 0;
    final recent   = (_data?['recent_sales'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(shopName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(DateFormat('EEEE, d MMM').format(DateTime.now()),
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.normal)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Today stats ─────────────────────────────
                  _sectionLabel('Today'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _statCard('Sales', '${today['count'] ?? 0}',
                        Icons.receipt_long, AppTheme.primary)),
                    const SizedBox(width: 10),
                    Expanded(child: _statCard('Revenue',
                        'Rs ${fmt.format(num.tryParse('${today['revenue']}') ?? 0)}',
                        Icons.payments_outlined, AppTheme.secondary)),
                    const SizedBox(width: 10),
                    Expanded(child: _statCard('Profit',
                        'Rs ${fmt.format(num.tryParse('${today['profit']}') ?? 0)}',
                        Icons.trending_up, Colors.orange)),
                  ]),
                  const SizedBox(height: 20),

                  // ── This month ──────────────────────────────
                  _sectionLabel('This Month'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _statCard('Sales', '${month['count'] ?? 0}',
                        Icons.receipt_long, AppTheme.primary)),
                    const SizedBox(width: 10),
                    Expanded(child: _statCard('Revenue',
                        'Rs ${fmt.format(num.tryParse('${month['revenue']}') ?? 0)}',
                        Icons.payments_outlined, AppTheme.secondary)),
                    const SizedBox(width: 10),
                    Expanded(child: _statCard('Profit',
                        'Rs ${fmt.format(num.tryParse('${month['profit']}') ?? 0)}',
                        Icons.trending_up, Colors.orange)),
                  ]),
                  const SizedBox(height: 20),

                  // ── Stock ────────────────────────────────────
                  _sectionLabel('Inventory'),
                  const SizedBox(height: 10),
                  _bigStatCard('Phones in Stock', '$inStock units',
                      Icons.inventory_2_outlined, AppTheme.primary),
                  const SizedBox(height: 20),

                  // ── Recent sales ─────────────────────────────
                  if (recent.isNotEmpty) ...[
                    _sectionLabel('Recent Sales'),
                    const SizedBox(height: 10),
                    ...recent.map((s) => _saleCard(s, fmt)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey));

  Widget _statCard(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      );

  Widget _bigStatCard(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ]),
        ]),
      );

  Widget _saleCard(Map s, NumberFormat fmt) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppTheme.secondary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.sell_outlined, color: AppTheme.secondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['customer_name'] ?? 'Walk-in Customer',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${s['items'] ?? 1} item(s) • ${s['payment_method']}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Rs ${fmt.format(num.tryParse('${s['total_amount']}') ?? 0)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Profit: Rs ${fmt.format(num.tryParse('${s['total_profit']}') ?? 0)}',
                style: const TextStyle(fontSize: 11, color: AppTheme.secondary)),
          ]),
        ]),
      );
}
