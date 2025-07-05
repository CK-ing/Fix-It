import 'dart:async';
import 'package:fixit_app_a186687/models/custom_request.dart';
import 'package:fixit_app_a186687/views/pages/bookings_detail_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'job_request_detail_page.dart';

class JobRequestsPage extends StatefulWidget {
  const JobRequestsPage({super.key});

  @override
  State<JobRequestsPage> createState() => _JobRequestsPageState();
}

class _JobRequestsPageState extends State<JobRequestsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  User? _currentUser;

  StreamSubscription? _requestsSubscription;
  // --- MODIFIED: State now holds lists for each tab ---
  List<CustomRequestViewModel> _allRequests = [];
  List<CustomRequestViewModel> _pendingRequests = [];
  List<CustomRequestViewModel> _quotedRequests = [];
  List<CustomRequestViewModel> _historyRequests = [];
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _listenForJobRequests();
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

  void _listenForJobRequests() {
    final query = _dbRef
        .child('custom_requests')
        .orderByChild('handymanId')
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
      final Set<String> homeownerIds = {};

      requestsData.forEach((key, value) {
        final request = CustomRequest.fromSnapshot(event.snapshot.child(key));
        tempRequests.add(request);
        homeownerIds.add(request.homeownerId);
      });

      final Map<String, Map<String, dynamic>> homeownersData = {};
      if (homeownerIds.isNotEmpty) {
        final homeownerFutures = homeownerIds.map((id) => _dbRef.child('users/$id').get()).toList();
        final homeownerSnapshots = await Future.wait(homeownerFutures);
        for (final snap in homeownerSnapshots) {
          if (snap.exists) {
            homeownersData[snap.key!] = Map<String, dynamic>.from(snap.value as Map);
          }
        }
      }

      final List<CustomRequestViewModel> viewModels = [];
      for (final request in tempRequests) {
        final homeownerInfo = homeownersData[request.homeownerId];
        viewModels.add(CustomRequestViewModel(
          request: request,
          homeownerName: homeownerInfo?['name'] ?? 'Unknown Customer',
          homeownerImageUrl: homeownerInfo?['profileImageUrl'],
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
  
  // --- NEW: Function to split all requests into the correct tab lists ---
  void _categorizeRequests() {
    _pendingRequests = _allRequests.where((r) => r.request.status == 'Pending').toList();
    _quotedRequests = _allRequests.where((r) => r.request.status == 'Quoted').toList();
    _historyRequests = _allRequests.where((r) => r.request.status != 'Pending' && r.request.status != 'Quoted').toList();
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToFormat = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (dateToFormat == today) return 'Today';
    if (dateToFormat == yesterday) return 'Yesterday';
    return DateFormat('dd MMM yy').format(timestamp);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job Requests'),
        // --- NEW: TabBar for different request statuses ---
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Pending (${_pendingRequests.length})'),
            Tab(text: 'Quoted (${_quotedRequests.length})'),
            Tab(text: 'History (${_historyRequests.length})'),
          ],
        ),
      ),
      // --- MODIFIED: Body is now a TabBarView ---
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRequestList(_pendingRequests, "No Pending Requests", "New job requests from homeowners will appear here."),
                _buildRequestList(_quotedRequests, "No Quoted Requests", "Requests you have sent a quote for will appear here."),
                _buildRequestList(_historyRequests, "No Request History", "Your past job requests will appear here."),
              ],
            ),
    );
  }

  Widget _buildRequestList(List<CustomRequestViewModel> requests, String title, String subtitle) {
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

  Widget _buildRequestCard(CustomRequestViewModel viewModel) {
    final request = viewModel.request;
    final statusColor = _getStatusColor(request.status);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      child: InkWell(
        onTap: () {
  // --- MODIFIED: Always navigate to the detail page, regardless of status ---
  // The detail page itself will now handle what to show.
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => JobRequestDetailPage(requestViewModel: viewModel)),
  );
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
                    backgroundImage: viewModel.homeownerImageUrl != null
                        ? NetworkImage(viewModel.homeownerImageUrl!)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      viewModel.homeownerName,
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
                  const Text('View Details', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
