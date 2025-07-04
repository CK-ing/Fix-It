import 'dart:async';
import 'package:fixit_app_a186687/models/custom_request.dart';
import 'package:fixit_app_a186687/views/pages/custom_request_status_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// A view model to combine the request with the handyman's details for display
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

class QuotesReceivedPage extends StatefulWidget {
  const QuotesReceivedPage({super.key});

  @override
  State<QuotesReceivedPage> createState() => _QuotesReceivedPageState();
}

class _QuotesReceivedPageState extends State<QuotesReceivedPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  User? _currentUser;

  StreamSubscription? _requestsSubscription;
  List<QuoteViewModel> _receivedQuotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _listenForQuotes();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _requestsSubscription?.cancel();
    super.dispose();
  }

  void _listenForQuotes() {
    final query = _dbRef
        .child('custom_requests')
        .orderByChild('homeownerId')
        .equalTo(_currentUser!.uid);

    _requestsSubscription = query.onValue.listen((event) async {
      if (!mounted) return;
      if (!event.snapshot.exists) {
        setState(() {
          _receivedQuotes = [];
          _isLoading = false;
        });
        return;
      }

      final requestsData = Map<String, dynamic>.from(event.snapshot.value as Map);
      final List<CustomRequest> tempRequests = [];
      final Set<String> handymanIds = {};

      requestsData.forEach((key, value) {
        final request = CustomRequest.fromSnapshot(event.snapshot.child(key));
        // Only show requests with a "Quoted" status
        if (request.status == 'Quoted') {
          tempRequests.add(request);
          handymanIds.add(request.handymanId);
        }
      });

      // Fetch all unique handyman details
      final Map<String, Map<String, dynamic>> handymanData = {};
      final handymanFutures = handymanIds.map((id) => _dbRef.child('users/$id').get()).toList();
      final handymanSnapshots = await Future.wait(handymanFutures);

      for (final snap in handymanSnapshots) {
        if (snap.exists) {
          handymanData[snap.key!] = Map<String, dynamic>.from(snap.value as Map);
        }
      }

      // Combine request data with handyman data
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
        _receivedQuotes = viewModels;
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
        title: const Text('Quotes Received'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_receivedQuotes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.request_quote_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('No Quotes Yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Quotes from handymen will appear here.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _receivedQuotes.length,
      itemBuilder: (context, index) {
        final quoteViewModel = _receivedQuotes[index];
        return _buildQuoteCard(quoteViewModel);
      },
    );
  }

  Widget _buildQuoteCard(QuoteViewModel viewModel) {
    final request = viewModel.request;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CustomRequestStatusPage(requestId: request.requestId)),
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
                    backgroundImage: viewModel.handymanImageUrl != null
                        ? NetworkImage(viewModel.handymanImageUrl!)
                        : null,
                    child: viewModel.handymanImageUrl == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      viewModel.handymanName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    _formatTimestamp(request.createdAt),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
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
                  Icon(Icons.local_offer, size: 16, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    'Quote: RM${request.quotePrice?.toStringAsFixed(2) ?? 'N/A'}',
                    style: TextStyle(fontWeight: FontWeight.w500, color: Theme.of(context).primaryColor),
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
}
