import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class HistoryScreen extends StatefulWidget {
  final UserModel user;

  const HistoryScreen({super.key, required this.user});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _incidents = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedType = 'All Types';
  String _selectedStatus = 'All Statuses';

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _setupSocketListener();
  }

  void _setupSocketListener() {
    SocketService.on('incident-updated', (data) {
      if (mounted) {
        _fetchHistory(); // Refresh history when an incident is updated
      }
    });
  }

  Future<void> _fetchHistory() async {
    try {
      final res = await http.get(Uri.parse('${ApiService.baseUrl}/api/user/history/${Uri.encodeComponent(widget.user.phone)}'));
      if (res.statusCode == 200) {
        if (mounted) {
          setState(() {
            _incidents = jsonDecode(res.body);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getStatusColor(String? status) {
    String st = (status ?? 'draft').toLowerCase().replaceAll('_', ' ');
    if (st == 'draft') return const Color(0xFF475569);
    if (st == 'submitted' || st == 'new') return const Color(0xFF4338ca);
    if (st == 'pending verification') return const Color(0xFF854d0e);
    if (st == 'verified') return const Color(0xFF166534);
    if (st == 'dispatching responders') return const Color(0xFFc2410c);
    if (st == 'responders en route' || st == 'enroute') return const Color(0xFFb45309);
    if (st == 'on scene') return const Color(0xFF1e40af);
    if (st == 'rescue in progress') return const Color(0xFF5b21b6);
    if (st == 'resolved') return const Color(0xFF15803d);
    if (st == 'closed') return const Color(0xFF334155);
    if (st == 'cancelled') return const Color(0xFFb91c1c);
    return const Color(0xFF64748b);
  }

  Color _getStatusBgColor(String? status) {
    String st = (status ?? 'draft').toLowerCase().replaceAll('_', ' ');
    if (st == 'draft') return const Color(0xFFf1f5f9);
    if (st == 'submitted' || st == 'new') return const Color(0xFFe0e7ff);
    if (st == 'pending verification') return const Color(0xFFfef08a);
    if (st == 'verified') return const Color(0xFFdcfce7);
    if (st == 'dispatching responders') return const Color(0xFFfed7aa);
    if (st == 'responders en route' || st == 'enroute') return const Color(0xFFfcd34d);
    if (st == 'on scene') return const Color(0xFFbfdbfe);
    if (st == 'rescue in progress') return const Color(0xFFddd6fe);
    if (st == 'resolved') return const Color(0xFFbbf7d0);
    if (st == 'closed') return const Color(0xFFe2e8f0);
    if (st == 'cancelled') return const Color(0xFFfecaca);
    return const Color(0xFFf1f5f9);
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    int ms = (timestamp is int) ? timestamp : int.tryParse(timestamp.toString()) ?? 0;
    if (ms == 0) return 'N/A';
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateFormat('MMM dd, yyyy - hh:mm a').format(date);
  }

  String _getCategoryEmoji(String? category) {
    String cat = (category ?? '').toLowerCase();
    if (cat.contains('fire')) return '🔥';
    if (cat.contains('crime') || cat.contains('police')) return '🚨';
    if (cat.contains('medical') || cat.contains('health')) return '🚑';
    if (cat.contains('natural') || cat.contains('flood') || cat.contains('water')) return '🌊';
    if (cat.contains('utility') || cat.contains('power')) return '⚡';
    if (cat.contains('accident') || cat.contains('crash')) return '💥';
    return '⚠️';
  }

  List<dynamic> _filteredIncidents() {
    return _incidents.where((inc) {
      final category = (inc['category'] ?? '').toString().toLowerCase();
      final status = (inc['status'] ?? '').toString().toLowerCase();
      final id = (inc['id'] ?? '').toString().toLowerCase();
      
      bool matchesSearch = _searchQuery.isEmpty || 
          id.contains(_searchQuery.toLowerCase()) || 
          category.contains(_searchQuery.toLowerCase());
          
      bool matchesType = _selectedType == 'All Types' || 
          category == _selectedType.toLowerCase();
          
      bool matchesStatus = _selectedStatus == 'All Statuses' || 
          status == _selectedStatus.toLowerCase();
          
      return matchesSearch && matchesType && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredIncidents();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF475569)),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Emergency History',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24), // Balance the icon button
              ],
            ),
          ),
          
          // Filters
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            color: const Color(0xFFF8FAFC),
            child: Column(
              children: [
                // Search bar
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search by ID, location, or type...',
                    hintStyle: GoogleFonts.outfit(color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedType,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.grey),
                            items: ['All Types', 'Medical', 'Fire', 'Crime', 'Natural', 'Utility', 'Other']
                                .map((t) => DropdownMenuItem(value: t, child: Text(t, style: GoogleFonts.outfit(fontSize: 14))))
                                .toList(),
                            onChanged: (val) => setState(() => _selectedType = val!),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.grey),
                            items: ['All Statuses', 'New', 'Verified', 'Dispatching Responders', 'Resolved', 'Cancelled']
                                .map((s) => DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.outfit(fontSize: 14), overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (val) => setState(() => _selectedStatus = val!),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: Container(
              color: const Color(0xFFF1F5F9),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No emergency history found.',
                            style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 16),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final inc = filtered[index];
                            final String idStr = inc['id']?.toString() ?? '';
                            final String shortId = idStr.length >= 8 ? idStr.substring(0, 8).toUpperCase() : idStr.toUpperCase();
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Text(_getCategoryEmoji(inc['category']), style: const TextStyle(fontSize: 16)),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${(inc['category'] ?? 'Emergency').toString().toUpperCase()} EMERGENCY',
                                            style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 13, color: const Color(0xFF1E293B)),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _getStatusBgColor(inc['status']),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          (inc['status'] ?? 'Draft').toString().toUpperCase().replaceAll('_', ' '),
                                          style: GoogleFonts.outfit(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: _getStatusColor(inc['status']),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _buildDetailRow('Emergency ID', 'ALR-$shortId'),
                                  _buildDetailRow('Location', inc['locationAddress'] ?? 'N/A'),
                                  _buildDetailRow('Reported', _formatDate(inc['createdAt'])),
                                  _buildDetailRow('Agency', inc['assignedUnit'] ?? 'N/A'),
                                  _buildDetailRow('Vehicle', inc['assignedVehicle'] ?? 'N/A'),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      if ((inc['status'] ?? 'draft').toString().toLowerCase() == 'draft') ...[
                                        Expanded(
                                          child: InkWell(
                                            onTap: () async {
                                              bool? confirm = await showDialog(
                                                context: context,
                                                builder: (c) => AlertDialog(
                                                  title: const Text('Cancel Draft'),
                                                  content: const Text('Are you sure you want to cancel this draft emergency?'),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
                                                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes')),
                                                  ],
                                                ),
                                              );
                                              if (confirm == true) {
                                                try {
                                                  final userId = widget.user.id.toString();
                                                  final isDraftId = idStr.startsWith('DRAFT-');
                                                  http.Response res;
                                                  if (isDraftId) {
                                                    res = await http.delete(Uri.parse('${ApiService.baseUrl}/api/incidents/draft/$userId'));
                                                  } else {
                                                    res = await http.put(
                                                      Uri.parse('${ApiService.baseUrl}/api/incidents/$idStr'),
                                                      headers: {'Content-Type': 'application/json'},
                                                      body: jsonEncode({'status': 'cancelled'}),
                                                    );
                                                  }
                                                  if (res.statusCode == 200 && mounted) {
                                                    _fetchHistory();
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Draft cancelled.')));
                                                  }
                                                } catch (e) {
                                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error cancelling draft.')));
                                                }
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                              decoration: BoxDecoration(color: Colors.red[50], border: Border.all(color: Colors.red.shade200), borderRadius: BorderRadius.circular(8)),
                                              alignment: Alignment.center,
                                              child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.red[700], fontWeight: FontWeight.w600, fontSize: 13)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: InkWell(
                                          onTap: () {
                                            String st = (inc['status'] ?? 'draft').toString().toLowerCase();
                                            if (st != 'resolved' && st != 'cancelled' && st != 'closed') {
                                              // Navigate to active tracking (SOSChatScreen)
                                              Navigator.pushReplacementNamed(context, '/sos_chat'); // or handled via home
                                              // We'll just pop history so home screen can load it.
                                              Navigator.pop(context);
                                            } else {
                                              _showIncidentDetails(inc);
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            decoration: BoxDecoration(color: Colors.blue[50], border: Border.all(color: Colors.blue.shade200), borderRadius: BorderRadius.circular(8)),
                                            alignment: Alignment.center,
                                            child: Text(
                                              ((inc['status'] ?? 'draft').toString().toLowerCase() != 'resolved' && 
                                               (inc['status'] ?? 'draft').toString().toLowerCase() != 'cancelled' && 
                                               (inc['status'] ?? 'draft').toString().toLowerCase() != 'closed') 
                                                ? 'View / Track \u2192' : 'View Details \u2192',
                                              style: GoogleFonts.outfit(color: Colors.blue[700], fontWeight: FontWeight.w600, fontSize: 13),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF475569)),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  void _showIncidentDetails(Map<String, dynamic> inc) {
    final String idStr = inc['id']?.toString() ?? '';
    final String shortId = idStr.length >= 8 ? idStr.substring(0, 8).toUpperCase() : idStr.toUpperCase();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Emergency Details', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 16),
              _buildDetailRow('Emergency ID', 'ALR-$shortId'),
              _buildDetailRow('Category', (inc['category'] ?? 'Emergency').toString().toUpperCase()),
              _buildDetailRow('Status', (inc['status'] ?? 'Draft').toString().toUpperCase().replaceAll('_', ' ')),
              _buildDetailRow('Location', inc['locationAddress'] ?? 'N/A'),
              _buildDetailRow('Reported', _formatDate(inc['createdAt'])),
              _buildDetailRow('Details', inc['details'] ?? 'No details provided'),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _buildDetailRow('Agency', inc['assignedUnit'] ?? 'N/A'),
              _buildDetailRow('Vehicle', inc['assignedVehicle'] ?? 'N/A'),
              _buildDetailRow('Responders', inc['assignedResponders'] ?? 'N/A'),
              if (inc['resolutionDate'] != null)
                _buildDetailRow('Resolved', _formatDate(inc['resolutionDate'])),
              if (inc['notes'] != null && inc['notes'].toString().isNotEmpty)
                _buildDetailRow('Notes', inc['notes']),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
