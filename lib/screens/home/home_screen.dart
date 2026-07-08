import 'package:flutter/material.dart';
import '../dashboard/dashboard_screen.dart';
import '../inventory/inventory_screen.dart';
import '../purchase/purchases_screen.dart';
import '../sale/sales_screen.dart';
import '../../app/theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  // Incrementing these keys forces Dashboard/Sales to rebuild (fresh load) on tab switch
  int _dashboardKey = 0;
  int _salesKey     = 0;

  void _onTabChanged(int i) {
    setState(() {
      if (i == 0) _dashboardKey++; // refresh dashboard on every visit
      if (i == 3) _salesKey++;     // refresh sales on every visit
      _tab = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          DashboardScreen(key: ValueKey('dash-$_dashboardKey')),
          const InventoryScreen(),
          const PurchasesScreen(),
          SalesScreen(key: ValueKey('sales-$_salesKey')),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _onTabChanged,
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.primary.withOpacity(0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: AppTheme.primary),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2, color: AppTheme.primary),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download, color: AppTheme.primary),
            label: 'Purchase',
          ),
          NavigationDestination(
            icon: Icon(Icons.upload_outlined),
            selectedIcon: Icon(Icons.upload, color: AppTheme.primary),
            label: 'Sale',
          ),
        ],
      ),
    );
  }
}
