import 'dart:async';
import 'package:fixit_app_a186687/models/custom_request.dart';
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

class _JobRequestsPageState extends State<JobRequestsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  User? _currentUser;

  StreamSubscription? _requestsSubscription;
  List<CustomRequestViewModel> _jobRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _listenForJobRequests();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
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
          _jobRequests = [];
          _isLoading = false;
        });
        return;
      }

      final requestsData = Map<String, dynamic>.from(event.snapshot.value as Map);
      final List<CustomRequest> tempRequests = [];
      final Set<String> homeownerIds = {};

      requestsData.forEach((key, value) {
        final request = CustomRequest.fromSnapshot(event.snapshot.child(key));
        // We only want to show requests that need action
        if (request.status == 'Pending') {
          tempRequests.add(request);
          homeownerIds.add(request.homeownerId);
        }
      });

      // Fetch all unique homeowner details
      final Map<String, Map<String, dynamic>> homeownersData = {};
      final homeownerFutures = homeownerIds.map((id) => _dbRef.child('users/$id').get()).toList();
      final homeownerSnapshots = await Future.wait(homeownerFutures);

      for (final snap in homeownerSnapshots) {
        if (snap.exists) {
          homeownersData[snap.key!] = Map<String, dynamic>.from(snap.value as Map);
        }
      }

      // Combine request data with homeowner data
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
        _jobRequests = viewModels;
        _isLoading = false;
      });
    });
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToFormat = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (dateToFormat == today) return 'Today';
    if (dateToFormat == yesterday) return 'Yesterday';
    return DateFormat('dd MMM yyyy').format(timestamp);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Job Requests'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_jobRequests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('No New Job Requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Custom requests from homeowners will appear here.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _jobRequests.length,
      itemBuilder: (context, index) {
        final requestViewModel = _jobRequests[index];
        return _buildRequestCard(requestViewModel);
      },
    );
  }

  Widget _buildRequestCard(CustomRequestViewModel viewModel) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      child: InkWell(
        onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => JobRequestDetailPage(
      requestViewModel: viewModel,
    )),
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
                    backgroundColor: Colors.grey[200],
                    backgroundImage: viewModel.homeownerImageUrl != null
                        ? NetworkImage(viewModel.homeownerImageUrl!)
                        : null,
                    child: viewModel.homeownerImageUrl == null
                        ? const Icon(Icons.person, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      viewModel.homeownerName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    _formatTimestamp(viewModel.request.createdAt),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  )
                ],
              ),
              const Divider(height: 24),
              Text(
                viewModel.request.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[800]),
              ),
              const SizedBox(height: 8),
              Chip(
                label: Text('Budget: ${viewModel.request.budgetRange}'),
                avatar: const Icon(Icons.attach_money, size: 16),
                backgroundColor: Colors.green.withOpacity(0.1),
                labelStyle: TextStyle(color: Colors.green[800]),
              )
            ],
          ),
        ),
      ),
    );
  }
}
