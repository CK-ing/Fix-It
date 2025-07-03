import 'package:fixit_app_a186687/models/custom_request.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import 'book_service_page.dart';
import 'chat_page.dart';

// We will create this page in the next step
// import 'finalize_booking_page.dart';

class CustomRequestStatusPage extends StatefulWidget {
  final String requestId;

  const CustomRequestStatusPage({
    required this.requestId,
    super.key,
  });

  @override
  State<CustomRequestStatusPage> createState() => _CustomRequestStatusPageState();
}

class _CustomRequestStatusPageState extends State<CustomRequestStatusPage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  
  // State
  bool _isLoading = true;
  String? _error;
  bool _isProcessing = false;

  // Data Holders
  CustomRequest? _requestData;
  Map<String, dynamic>? _handymanDetails;
  Map<String, dynamic>? _homeownerDetails;

  @override
  void initState() {
    super.initState();
    _loadRequestDetails();
  }

  Future<void> _loadRequestDetails() async {
    try {
      final requestSnapshot = await _dbRef.child('custom_requests').child(widget.requestId).get();
      if (!mounted || !requestSnapshot.exists) throw Exception("Request not found.");

      final requestData = CustomRequest.fromSnapshot(requestSnapshot);

      final results = await Future.wait([
        _dbRef.child('users').child(requestData.handymanId).get(),
        _dbRef.child('users').child(requestData.homeownerId).get(),
      ]);

      if (!mounted) return;

      final handymanSnap = results[0];
      final homeownerSnap = results[1];

      setState(() {
        _requestData = requestData;
        _handymanDetails = handymanSnap.exists ? Map<String, dynamic>.from(handymanSnap.value as Map) : null;
        _homeownerDetails = homeownerSnap.exists ? Map<String, dynamic>.from(homeownerSnap.value as Map) : null;
        _isLoading = false;
      });

    } catch (e) {
      print("Error loading request details: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load request details.";
        });
      }
    }
  }

  Future<void> _declineQuote() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Decline Quote?"),
        content: const Text("Are you sure you want to decline this quote? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Decline"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      await _dbRef.child('custom_requests/${widget.requestId}/status').set('DeclinedByHomeowner');
      // Notify the handyman that their quote was declined.
      if (_requestData != null) {
        final homeownerName = _homeownerDetails?['name'] ?? 'The customer';
        final handymanId = _requestData!.handymanId;
        
        final notificationRef = _dbRef.child('notifications/$handymanId').push();
        await notificationRef.set({
          'notificationId': notificationRef.key,
          'title': 'Quote Declined',
          'body': '$homeownerName has declined your quote for the custom request.',
          'bookingId': widget.requestId, // Link to the custom request
          'type': 'custom_request_declined', // A new type for this event
          'isRead': false,
          'createdAt': ServerValue.timestamp,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Quote has been declined.")));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to decline quote: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Quote'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildBody(),
      bottomNavigationBar: _isLoading || _error != null ? null : _buildActionButtons(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHandymanQuoteCard(),
        const SizedBox(height: 24),
        _buildSectionTitle('Your Request Title'),
        const SizedBox(height: 8),
        Text(_requestData!.title, style: const TextStyle(height: 1.5, fontSize: 15)),
        const SizedBox(height: 8),
        _buildSectionTitle('Your Request Description'),
        const SizedBox(height: 8),
        Text(_requestData!.description, style: const TextStyle(height: 1.5, fontSize: 15)),
        if (_requestData!.photoUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildPhotoGallery(),
        ],
      ],
    );
  }

  Widget _buildHandymanQuoteCard() {
    final handymanName = _handymanDetails?['name'] ?? 'Handyman';
    final handymanImageUrl = _handymanDetails?['profileImageUrl'] as String?;
    final quotePrice = (_requestData as dynamic).quotePrice as double?;
    final quotePriceType = (_requestData as dynamic).quotePriceType as String?;

    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias, // Important for InkWell ripple
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell( // <-- WRAPPED WITH INKWELL
        onTap: () {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null || _requestData == null) return;
          List<String> ids = [currentUser.uid, _requestData!.handymanId];
          ids.sort();
          String chatRoomId = ids.join('_');
          Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(
            chatRoomId: chatRoomId,
            otherUserId: _requestData!.handymanId,
            otherUserName: handymanName,
            otherUserImageUrl: handymanImageUrl,
          )));
        },
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 24,
                backgroundImage: handymanImageUrl != null ? NetworkImage(handymanImageUrl) : null,
              ),
              title: Text(handymanName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text("has sent you a quote"),
            ),
            const Divider(height: 32),
            Text(
              "Handyman's Quote",
              style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'RM ${quotePrice?.toStringAsFixed(2) ?? 'N/A'}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  quotePriceType ?? '',
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "This is the final price for the described job. Service tax may apply upon booking.",
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildPhotoGallery() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _requestData!.photoUrls.length,
        itemBuilder: (context, index) {
          final imageUrl = _requestData!.photoUrls[index];
          return GestureDetector( // <-- WRAPPED WITH GESTUREDETECTOR
            onTap: () => _viewPhotoFullScreen(imageUrl),
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  imageUrl,
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _viewPhotoFullScreen(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: InteractiveViewer(
            panEnabled: true,
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 4,
            child: Center(
              child: Image.network(imageUrl),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isProcessing ? null : _declineQuote,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Decline Quote'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _isProcessing ? null : () {
  if (_requestData == null) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BookServicePage(
        // Pass the custom request ID instead of a service ID
        customRequestId: widget.requestId,
        // Pass the handyman ID from the request data
        handymanId: _requestData!.handymanId,
      ),
    ),
  );
},
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Accept & Schedule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
