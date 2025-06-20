import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../../models/bookings_services.dart';

class ReportIssuePage extends StatefulWidget {
  final String bookingId;
  final String userRole;

  const ReportIssuePage({
    required this.bookingId,
    required this.userRole,
    super.key,
  });

  @override
  State<ReportIssuePage> createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends State<ReportIssuePage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  // State variables
  Booking? _booking;
  Map<String, dynamic>? _serviceDetails;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  String? _selectedIssueCategory;
  bool _consentChecked = false;

  // --- Role-Specific Issue Categories ---
  final List<String> _homeownerCategories = [
    'Service Not as Described',
    'Handyman No-Show',
    'Property Damage',
    'Pricing Dispute',
    'Unprofessional Behavior',
    'Safety Concern',
    'Other',
  ];

  final List<String> _handymanCategories = [
    'Payment Dispute',
    'Customer No-Show or Unresponsive',
    'Unsafe Work Environment',
    'Scope of Work Changed',
    'Unreasonable Customer Demands',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadBookingSummary();
  }
  
  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadBookingSummary() async {
    try {
      final bookingSnapshot = await FirebaseDatabase.instance
          .ref('bookings')
          .child(widget.bookingId)
          .get();
      
      if (!mounted) return;

      if (bookingSnapshot.exists) {
        final bookingData = Booking.fromSnapshot(bookingSnapshot);
        final serviceSnapshot = await FirebaseDatabase.instance
            .ref('services')
            .child(bookingData.serviceId)
            .get();

        if (mounted) {
           setState(() {
            _booking = bookingData;
            if(serviceSnapshot.exists) {
              _serviceDetails = Map<String, dynamic>.from(serviceSnapshot.value as Map);
            }
            _isLoading = false;
          });
        }
      } else {
        throw Exception("Booking not found");
      }
    } catch (e) {
      if(mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load booking details.";
        });
      }
    }
  }

  void _submitReport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_consentChecked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must acknowledge the terms to proceed.'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    setState(() => _isSubmitting = true);

    // --- SIMULATION ---
    // In a real app, you would save this to a '/reports' node in Firebase.
    // For now, we simulate a network call.
    await Future.delayed(const Duration(seconds: 2));
    
    // --- END SIMULATION ---
    
    setState(() => _isSubmitting = false);
    
    if (mounted) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Report Submitted"),
          content: const Text("Thank you. Our support team will review your report and get back to you within 2-3 business days."),
          actions: [
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back from report page
              },
            ),
          ],
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report an Issue')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildReportForm(),
      bottomNavigationBar: _buildSubmitButton(),
    );
  }
  
  Widget _buildReportForm() {
    final categories = widget.userRole == 'Homeowner' ? _homeownerCategories : _handymanCategories;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildBookingSummaryCard(),
          const SizedBox(height: 24),
          Text(
            'Tell us what happened',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildDropdown('Issue Category *', categories),
          const SizedBox(height: 16),
          _buildDescriptionField('Describe the issue in detail *'),
          const SizedBox(height: 16),
          _buildConsentCheckbox(),
        ],
      ),
    );
  }

  Widget _buildBookingSummaryCard() {
    final imageUrl = _serviceDetails?['imageUrl'] as String?;

    return Card(
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300)
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 70, height: 70, color: Colors.grey[200],
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(imageUrl, fit: BoxFit.cover)
                    : const Icon(Icons.construction, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _booking?.serviceName ?? 'Service',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Booking ID: ${widget.bookingId}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                   Text(
                    'Completed: ${DateFormat.yMMMd().format(_booking!.scheduledDateTime)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDropdown(String label, List<String> items) {
    return DropdownButtonFormField<String>(
      value: _selectedIssueCategory,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      ),
      items: items.map((category) {
        return DropdownMenuItem(
          value: category,
          child: Text(category),
        );
      }).toList(),
      onChanged: (value) {
        setState(() => _selectedIssueCategory = value);
      },
      validator: (value) => value == null ? 'Please select a category' : null,
    );
  }
  
  Widget _buildDescriptionField(String label) {
    return TextFormField(
      controller: _descriptionController,
      maxLines: 6,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Please provide as much detail as possible to help us resolve your issue quickly.',
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().length < 10) {
          return 'Please provide a description of at least 10 characters.';
        }
        return null;
      },
    );
  }

  Widget _buildConsentCheckbox() {
    return FormField<bool>(
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: _consentChecked,
              onChanged: (value) => setState(() => _consentChecked = value ?? false),
              title: const Text(
                'I acknowledge that the information provided is true and consent to FixIt using my personal data to investigate this report.',
                style: TextStyle(fontSize: 12),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: Theme.of(context).primaryColor,
            ),
            if (state.errorText != null)
              Padding(
                padding: const EdgeInsets.only(left: 12.0, top: 4.0),
                child: Text(
                  state.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                ),
              ),
          ],
        );
      },
      validator: (value) {
        if (!_consentChecked) {
          return 'You must acknowledge to proceed.';
        }
        return null;
      },
    );
  }
  
  Widget _buildSubmitButton() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: SafeArea(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          onPressed: _isSubmitting ? null : _submitReport,
          child: _isSubmitting
              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Text('Submit Report'),
        ),
      ),
    );
  }
}
