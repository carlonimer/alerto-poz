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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Emergency History', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _incidents.isEmpty
              ? Center(
                  child: Text(
                    'No emergency history found.',
                    style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _incidents.length,
                  itemBuilder: (context, index) {
                    final inc = _incidents[index];
                    final String idStr = inc['id']?.toString() ?? '';
                    final String shortId = idStr.length >= 8 ? idStr.substring(0, 8).toUpperCase() : idStr.toUpperCase();
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '#$shortId - ${inc['category'] ?? 'Emergency'}',
                                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15, color: const Color(0xFF1E293B)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDate(inc['createdAt']),
                                      style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
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
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _getStatusColor(inc['status']),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          _buildDetailRow('Agency', inc['assignedUnit'] ?? 'Unassigned'),
                          _buildDetailRow('Vehicle', inc['assignedVehicle'] ?? 'Unassigned'),
                          _buildDetailRow('Responders', inc['assignedResponders'] ?? 'Unassigned'),
                          _buildDetailRow('Resolved', _formatDate(inc['resolutionDate'])),
                          if (inc['notes'] != null && inc['notes'].toString().isNotEmpty)
                            _buildDetailRow('Notes', inc['notes']),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
