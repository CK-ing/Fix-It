import 'package:fixit_app_a186687/models/custom_request.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

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

      // Send notification to homeowner
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
        'bookingId': widget.requestViewModel.request.requestId, // Link to the custom request
        'type': 'custom_request_update',
        'isRead': false,
        'createdAt': ServerValue.timestamp,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Request has been $status.'),
          backgroundColor: Colors.green,
        ));
        Navigator.of(context).pop(); // Go back to the list page
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
    _selectedPriceType = 'Fixed'; // Reset to default

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
                      Navigator.of(context).pop(); // Close dialog
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
        title: const Text('Job Request Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildHomeownerCard(),
          const SizedBox(height: 24),
          _buildSectionTitle('Job Description'),
          Text(widget.requestViewModel.request.description, style: const TextStyle(fontSize: 16, height: 1.5)),
          const SizedBox(height: 24),
          if(widget.requestViewModel.request.photoUrls.isNotEmpty) ...[
            _buildSectionTitle('Photos from Customer'),
            _buildPhotoGallery(),
            const SizedBox(height: 24),
          ],
          _buildSectionTitle('Customer\'s Budget'),
          Text(
            widget.requestViewModel.request.budgetRange,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
        ],
      ),
      bottomNavigationBar: _buildActionButtons(),
    );
  }

  Widget _buildHomeownerCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundImage: widget.requestViewModel.homeownerImageUrl != null
                  ? NetworkImage(widget.requestViewModel.homeownerImageUrl!)
                  : null,
              child: widget.requestViewModel.homeownerImageUrl == null
                  ? const Icon(Icons.person)
                  : null,
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("REQUEST FROM", style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text(widget.requestViewModel.homeownerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          // Using a heavier bold weight for more emphasis
          fontWeight: FontWeight.w700, 
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildPhotoGallery() {
    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: widget.requestViewModel.request.photoUrls.length,
        itemBuilder: (context, index) {
          final imageUrl = widget.requestViewModel.request.photoUrls[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (c, o, s) => Container(
                  width: 120, height: 120, color: Colors.grey[200],
                  child: const Icon(Icons.error),
                ),
              ),
            ),
          );
        },
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
                onPressed: _isProcessing ? null : () => _updateRequestStatus('Declined'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _showSubmitQuoteDialog,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Submit Quote'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
