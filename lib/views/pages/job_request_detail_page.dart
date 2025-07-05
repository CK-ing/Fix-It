import 'package:fixit_app_a186687/models/custom_request.dart';
import 'package:fixit_app_a186687/views/pages/bookings_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import 'chat_page.dart';

class JobRequestDetailPage extends StatefulWidget {
  final CustomRequestViewModel requestViewModel;

  const JobRequestDetailPage({
    required this.requestViewModel,
    super.key,
  });

  @override
  State<JobRequestDetailPage> createState() => _JobRequestDetailPageState();
}

class _JobRequestDetailPageState extends State<JobRequestDetailPage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  bool _isProcessing = false;

  // For the quote dialog
  final _quoteFormKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  String? _selectedPriceType = 'Fixed'; // Default to Fixed

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _updateRequestStatus(String status, {Map<String, dynamic>? quoteData}) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final updateData = {
        'status': status,
        'updatedAt': ServerValue.timestamp,
        if (quoteData != null) ...quoteData,
      };
      
      await _dbRef.child('custom_requests/${widget.requestViewModel.request.requestId}').update(updateData);

      final actorSnapshot = await _dbRef.child('users/${FirebaseAuth.instance.currentUser!.uid}/name').get();
      final handymanName = actorSnapshot.value as String? ?? 'Your handyman';
      String title = '';
      String body = '';

      if (status == 'Declined') {
        title = 'Request Declined';
        body = '$handymanName was unable to take on your custom request.';
      } else if (status == 'Quoted') {
        title = 'You\'ve Received a Quote!';
        body = '$handymanName has sent you a quote for your custom request.';
      }
      
      final notificationRef = _dbRef.child('notifications/${widget.requestViewModel.request.homeownerId}').push();
      await notificationRef.set({
        'notificationId': notificationRef.key,
        'title': title,
        'body': body,
        'bookingId': widget.requestViewModel.request.requestId,
        'type': 'custom_request_update',
        'isRead': false,
        'createdAt': ServerValue.timestamp,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Request has been $status.'),
          backgroundColor: Colors.green,
        ));
        Navigator.of(context).pop();
      }

    } catch (e) {
      print("Error updating request status: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to update request: ${e.toString()}'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSubmitQuoteDialog() {
    _priceController.clear();
    _selectedPriceType = 'Fixed';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Submit Your Quote'),
              content: Form(
                key: _quoteFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Your Price (RM)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Price is required.';
                        if (double.tryParse(value) == null || double.parse(value) <= 0) return 'Please enter a valid price.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedPriceType,
                      decoration: const InputDecoration(
                        labelText: 'Price Type',
                        border: OutlineInputBorder(),
                      ),
                      items: ['Fixed', 'Hourly'].map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() => _selectedPriceType = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_quoteFormKey.currentState!.validate()) {
                      final quoteData = {
                        'quotePrice': double.parse(_priceController.text.trim()),
                        'quotePriceType': _selectedPriceType,
                      };
                      Navigator.of(context).pop();
                      _updateRequestStatus('Quoted', quoteData: quoteData);
                    }
                  },
                  child: const Text('Submit Quote'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.requestViewModel.request.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildStatusSpecificContent(), // Dynamic content based on status
          const SizedBox(height: 24),
          _buildSectionTitle('Job Description'),
          const SizedBox(height: 8),
          Text(widget.requestViewModel.request.description, style: const TextStyle(fontSize: 16, height: 1.5)),
          const SizedBox(height: 24),
          if(widget.requestViewModel.request.photoUrls.isNotEmpty) ...[
            _buildSectionTitle('Photos from Customer'),
            const SizedBox(height: 16),
            _buildPhotoGallery(),
            const SizedBox(height: 24),
          ],
          _buildSectionTitle('Customer\'s Budget'),
          const SizedBox(height: 8),
          Text(
            widget.requestViewModel.request.budgetRange,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
        ],
      ),
      bottomNavigationBar: _buildActionButtons(),
    );
  }

  // --- NEW: This widget conditionally builds the top card based on status ---
  Widget _buildStatusSpecificContent() {
    final request = widget.requestViewModel.request;
    switch (request.status) {
      case 'Pending':
        return _buildHomeownerCard();
      case 'Quoted':
        return _buildStatusInfoCard(
          icon: Icons.request_quote_outlined,
          color: Colors.blue,
          title: 'Quote Sent',
          subtitle: 'You have sent a quote of RM${request.quotePrice?.toStringAsFixed(2)}. Waiting for the customer to respond.',
        );
      case 'Declined':
      case 'DeclinedByHomeowner':
      case 'Cancelled':
         return _buildStatusInfoCard(
          icon: Icons.cancel_outlined,
          color: Colors.red,
          title: 'Request Closed',
          subtitle: 'This request was declined or cancelled and requires no further action.',
        );
      case 'Booked':
        return _buildStatusInfoCard(
          icon: Icons.check_circle_outline_rounded,
          color: Colors.green,
          title: 'Request Booked!',
          subtitle: 'The customer has accepted your quote and this request has been converted to a booking.',
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildHomeownerCard() {
    final homeownerName = widget.requestViewModel.homeownerName;
    final homeownerImageUrl = widget.requestViewModel.homeownerImageUrl;
    final homeownerId = widget.requestViewModel.request.homeownerId;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    // Get the budget range from the view model
    final budgetRange = widget.requestViewModel.request.budgetRange;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: () {
          if (currentUserId == null) return;
          List<String> ids = [currentUserId, homeownerId];
          ids.sort();
          String chatRoomId = ids.join('_');
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatPage(
              chatRoomId: chatRoomId,
              otherUserId: homeownerId,
              otherUserName: homeownerName,
              otherUserImageUrl: homeownerImageUrl,
            )),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          // --- MODIFIED: Wrapped content in a Column to match the quote card design ---
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 24,
                  backgroundImage: homeownerImageUrl != null ? NetworkImage(homeownerImageUrl) : null,
                  child: homeownerImageUrl == null ? const Icon(Icons.person, size: 24) : null,
                ),
                title: Text(homeownerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: const Text("sent you a request"),
                trailing: const Icon(Icons.chat_bubble_outline, color: Colors.grey),
              ),
              const Divider(height: 24),
              Text(
                "Customer's Budget",
                style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                budgetRange,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 28),
              ),
              const SizedBox(height: 8),
              Text(
                "This is the customer's budget. Your quote should be based on your professional assessment of the job.",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatusInfoCard({required IconData icon, required Color color, required String title, required String subtitle}) {
    return Card(
      elevation: 2,
      color: color.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3))
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.grey[700], height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
        itemCount: widget.requestViewModel.request.photoUrls.length, 
        itemBuilder: (context, index) { 
          final imageUrl = widget.requestViewModel.request.photoUrls[index]; 
          return GestureDetector( 
            onTap: () => _viewPhotoFullScreen(imageUrl), 
            child: Padding( 
              padding: const EdgeInsets.only(right: 8.0), 
              child: ClipRRect( borderRadius: 
              BorderRadius.circular(8), 
              child: Image.network( 
                imageUrl, 
                width: 100, 
                height: 100, 
                fit: BoxFit.cover, 
                errorBuilder: (c, o, s) => Container( 
                  width: 100, 
                  height: 100, 
                  color: Colors.grey[200], 
                  child: const Icon(
                    Icons.error, color: Colors.grey
                    ), 
                  ), 
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
            body: Center( child: InteractiveViewer( 
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
            ), 
            ); 
            }

  Widget? _buildActionButtons() {
    final status = widget.requestViewModel.request.status;
    switch (status) {
      case 'Pending':
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : () => _updateRequestStatus('Declined'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _showSubmitQuoteDialog,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Submit Quote'),
                  ),
                ),
              ],
            ),
          ),
        );
      
      case 'Booked':
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('View Booking'),
                onPressed: () async {
                  final query = _dbRef.child('bookings').orderByChild('customRequestId').equalTo(widget.requestViewModel.request.requestId);
                  final snapshot = await query.get();
                  if (snapshot.exists && snapshot.value != null) {
                    final bookingsData = Map<String, dynamic>.from(snapshot.value as Map);
                    final bookingId = bookingsData.keys.first;
                    if (mounted) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailPage(
                        bookingId: bookingId,
                        userRole: 'Handyman',
                      )));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ),
        );

      default:
        // For Quoted, Declined, Cancelled, etc., show no action buttons
        return null;
    }
  }
}
