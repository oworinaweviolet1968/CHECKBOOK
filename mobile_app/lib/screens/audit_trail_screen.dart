import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/audit_service.dart';
import '../utils/colors.dart';

class AuditTrailScreen extends StatefulWidget {
  const AuditTrailScreen({super.key});

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  String _searchQuery = '';
  String _selectedCategory = 'ALL';
  final TextEditingController _searchController = TextEditingController();

  final List<String> _categories = [
    'ALL',
    'DELETE_TRANSACTION',
    'REPRICING',
    'STOCK_UPDATE',
    'PAYMENT',
    'SECURITY_ALERT',
  ];

  @override
  void initState() {
    super.initState();
    AuditService.instance.refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _getActionColor(String action) {
    switch (action.toUpperCase()) {
      case 'DELETE_TRANSACTION':
      case 'DELETE_STOCK':
      case 'DELETED':
        return Colors.redAccent;
      case 'REPRICING':
      case 'PRICE_UPDATE':
        return Colors.amber;
      case 'STOCK_UPDATE':
      case 'NEW_STOCK':
        return Colors.blueAccent;
      case 'PAYMENT':
      case 'DEBT_PAYMENT':
        return Colors.greenAccent;
      case 'SECURITY_ALERT':
        return Colors.orangeAccent;
      default:
        return AppColors.accentBlue;
    }
  }

  IconData _getActionIcon(String action) {
    switch (action.toUpperCase()) {
      case 'DELETE_TRANSACTION':
      case 'DELETE_STOCK':
      case 'DELETED':
        return Icons.delete_forever_rounded;
      case 'REPRICING':
      case 'PRICE_UPDATE':
        return Icons.price_change_rounded;
      case 'STOCK_UPDATE':
      case 'NEW_STOCK':
        return Icons.inventory_2_rounded;
      case 'PAYMENT':
      case 'DEBT_PAYMENT':
        return Icons.payments_rounded;
      case 'SECURITY_ALERT':
        return Icons.security_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  String _formatTimestamp(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('MMM dd, yyyy • hh:mm a').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0,
        title: const Text(
          'Cloud Audit Trail',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.accentBlue),
            onPressed: () => AuditService.instance.refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            padding: const EdgeInsets.all(16.0),
            color: AppColors.cardBackground,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search audit logs...',
                    hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6)),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.accentBlue),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: AppColors.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(cat.replaceAll('_', ' ')),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() => _selectedCategory = cat);
                          },
                          selectedColor: AppColors.accentBlue.withValues(alpha: 0.25),
                          checkmarkColor: AppColors.accentBlue,
                          backgroundColor: AppColors.background,
                          labelStyle: TextStyle(
                            color: isSelected ? AppColors.accentBlue : AppColors.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? AppColors.accentBlue : Colors.transparent,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // Audit Stream Body
          Expanded(
            child: StreamBuilder<List<AuditLogItem>>(
              stream: AuditService.instance.auditLogsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return FutureBuilder<List<AuditLogItem>>(
                    future: AuditService.instance.getAuditLogs(),
                    builder: (context, futureSnap) {
                      if (!futureSnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _buildLogsList(futureSnap.data!);
                    },
                  );
                }

                final logs = snapshot.data ?? [];
                return _buildLogsList(logs);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList(List<AuditLogItem> logs) {
    final filtered = logs.where((item) {
      final matchesSearch = _searchQuery.isEmpty ||
          item.action.toLowerCase().contains(_searchQuery) ||
          item.details.toString().toLowerCase().contains(_searchQuery) ||
          item.deviceId.toLowerCase().contains(_searchQuery);

      final matchesCat = _selectedCategory == 'ALL' ||
          item.action.toUpperCase() == _selectedCategory.toUpperCase();

      return matchesSearch && matchesCat;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'No audit logs found',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        final actionColor = _getActionColor(item.action);
        final actionIcon = _getActionIcon(item.action);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: AppColors.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.neutralBorder.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: actionColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: actionColor.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(actionIcon, size: 16, color: actionColor),
                          const SizedBox(width: 6),
                          Text(
                            item.action.replaceAll('_', ' '),
                            style: TextStyle(
                              color: actionColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          item.isDirty ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                          size: 16,
                          color: item.isDirty ? Colors.amber : Colors.greenAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.isDirty ? 'Local Cache' : 'Synced',
                          style: TextStyle(
                            color: item.isDirty ? Colors.amber : Colors.greenAccent,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Details Content
                if (item.details.isNotEmpty)
                  Text(
                    item.details.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  )
                else
                  const Text(
                    'No detailed payload recorded',
                    style: TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                  ),

                const SizedBox(height: 12),
                const Divider(color: AppColors.neutralBorder, height: 1),
                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.devices_rounded, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          item.deviceId.length > 12
                              ? '${item.deviceId.substring(0, 12)}...'
                              : item.deviceId,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                    Text(
                      _formatTimestamp(item.timestamp),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
