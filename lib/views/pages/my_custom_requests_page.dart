import 'dart:async';

import 'package:fixit_app_a186687/models/custom_request.dart';
import 'package:fixit_app_a186687/views/pages/bookings_detail_page.dart';
import 'package:fixit_app_a186687/views/pages/custom_request_status_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// --- NEW: Local helper class specifically for this page ---
// This will not conflict with the CustomRequestViewModel in the model file.
class QuoteViewModel {
  final CustomRequest request;
  final String handymanName;
  final String? handymanImageUrl;

  QuoteViewModel({
    required this.request,
    required this.handymanName,
    this.handymanImageUrl,
  });
}

class MyCustomRequestsPage extends StatefulWidget {
  const MyCustomRequestsPage({super.key});

  @override
  State<MyCustomRequestsPage> createState() => _MyCustomRequestsPageState();
}

class _MyCustomRequestsPageState extends State<MyCustomRequestsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  User? _currentUser;

  StreamSubscription? _requestsSubscription;
  // --- MODIFIED: Use the new local QuoteViewModel ---
  List<QuoteViewModel> _allRequests = [];
  List<QuoteViewModel> _pendingRequests = [];
  List<QuoteViewModel> _quotedRequests = [];
  List<QuoteViewModel> _historyRequests = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _listenForRequests();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _requestsSubscription?.cancel();
    super.dispose();
  }

  void _listenForRequests() {
    final query = _dbRef
        .child('custom_requests')
        .orderByChild('homeownerId')
        .equalTo(_currentUser!.uid);

    _requestsSubscription = query.onValue.listen((event) async {
      if (!mounted) return;
      if (!event.snapshot.exists) {
        setState(() {
          _allRequests = [];
          _categorizeRequests();
          _isLoading = false;
        });
        return;
      }

      final requestsData = Map<String, dynamic>.from(event.snapshot.value as Map);
      final List<CustomRequest> tempRequests = [];
      final Set<String> handymanIds = {};

      requestsData.forEach((key, value) {
        final request = CustomRequest.fromSnapshot(event.snapshot.child(key));
        tempRequests.add(request);
        handymanIds.add(request.handymanId);
      });

      final Map<String, Map<String, dynamic>> handymanData = {};
      if (handymanIds.isNotEmpty) {
        final handymanFutures = handymanIds.map((id) => _dbRef.child('users/$id').get()).toList();
        final handymanSnapshots = await Future.wait(handymanFutures);
        for (final snap in handymanSnapshots) {
          if (snap.exists) {
            handymanData[snap.key!] = Map<String, dynamic>.from(snap.value as Map);
          }
        }
      }

      // --- MODIFIED: Create instances of the new local QuoteViewModel ---
      final List<QuoteViewModel> viewModels = [];
      for (final request in tempRequests) {
        final handymanInfo = handymanData[request.handymanId];
        viewModels.add(QuoteViewModel(
          request: request,
          handymanName: handymanInfo?['name'] ?? 'Unknown Handyman',
          handymanImageUrl: handymanInfo?['profileImageUrl'],
        ));
      }
      
      viewModels.sort((a, b) => b.request.createdAt.compareTo(a.request.createdAt));

      setState(() {
        _allRequests = viewModels;
        _categorizeRequests();
        _isLoading = false;
      });
    });
  }

  void _categorizeRequests() {
    _pendingRequests = _allRequests.where((r) => r.request.status == 'Pending').toList();
    _quotedRequests = _allRequests.where((r) => r.request.status == 'Quoted').toList();
    _historyRequests = _allRequests.where((r) => r.request.status != 'Pending' && r.request.status != 'Quoted').toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Custom Requests'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Pending (${_pendingRequests.length})'),
            Tab(text: 'Quoted (${_quotedRequests.length})'),
            Tab(text: 'History (${_historyRequests.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRequestList(_pendingRequests, "No Pending Requests", "Requests you've sent that are awaiting a quote will appear here."),
                _buildRequestList(_quotedRequests, "No Quotes Received", "Quotes from handymen will appear here. Tap to review and accept."),
                _buildRequestList(_historyRequests, "No Request History", "Your past custom requests will appear here."),
              ],
            ),
    );
  }

  Widget _buildRequestList(List<QuoteViewModel> requests, String title, String subtitle) {
    if (requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        return _buildRequestCard(requests[index]);
      },
    );
  }

  Widget _buildRequestCard(QuoteViewModel viewModel) {
    final request = viewModel.request;
    final statusColor = _getStatusColor(request.status);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      child: InkWell(
        onTap: () async {
          // --- NEW NAVIGATION LOGIC ---
          switch (request.status) {
            case 'Booked':
              // Find the booking that corresponds to this custom request
              final query = _dbRef.child('bookings').orderByChild('customRequestId').equalTo(request.requestId);
              final snapshot = await query.get();
              if (snapshot.exists && snapshot.value != null) {
                final bookingsData = Map<String, dynamic>.from(snapshot.value as Map);
                final bookingId = bookingsData.keys.first; // Get the first (and only) booking ID
                 if (mounted) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailPage(
                      bookingId: bookingId,
                      userRole: 'Homeowner',
                    )));
                 }
              } else {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not find the final booking.")));
              }
              break;
            
            case 'Pending':
            case 'Quoted':
            case 'Declined':
            case 'Cancelled':
              // For all these statuses, go to the status page.
              // The status page will show/hide buttons based on the status.
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CustomRequestStatusPage(requestId: request.requestId)),
              );
              break;
            
            default:
              // Do nothing for other statuses
              break;
          }
        },
        borderRadius: BorderRadius.circular(10.0),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: viewModel.handymanImageUrl != null
                        ? NetworkImage(viewModel.handymanImageUrl!)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      viewModel.handymanName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Chip(
                    label: Text(request.status, style: const TextStyle(color: Colors.white, fontSize: 10)),
                    backgroundColor: statusColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  )
                ],
              ),
              const Divider(height: 24),
              Text(
                request.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.attach_money, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Budget: ${request.budgetRange}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                  const Spacer(),
                  Text('View Details', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Color _getStatusColor(String status) {
    switch (status) {
      case "Pending": return Colors.orange.shade700;
      case "Quoted": return Colors.blue.shade700;
      case "Booked": return Colors.green.shade700;
      case "Declined": return Colors.red.shade700;
      case "Cancelled": return Colors.grey;
      default: return Colors.grey;
    }
  }
}
