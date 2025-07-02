import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../../models/bookings_services.dart';

class ReportIssuePage extends StatefulWidget {
  // *** MODIFIED: Make parameters optional to handle different report types ***
  final String? bookingId;
  final String? handymanId;
  final String userRole;

  const ReportIssuePage({
    this.bookingId,
    this.handymanId,
    required this.userRole,
    super.key,
  }) : assert(bookingId != null || handymanId != null, 'Either bookingId or handymanId must be provided');

  @override
  State<ReportIssuePage> createState() => _ReportIssuePageState();
}

class _ReportIssuePageState extends State<ReportIssuePage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  // State variables
  Booking? _booking;
  Map<String, dynamic>? _serviceDetails;
  Map<String, dynamic>? _handymanDetails; // For handyman reports
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  String? _selectedIssueCategory;
  bool _consentChecked = false;

  // --- MODIFIED: Added categories for reporting a handyman profile ---
  final List<String> _homeownerBookingCategories = [
    'Service Not as Described', 'Handyman No-Show', 'Property Damage', 'Pricing Dispute', 'Unprofessional Behavior', 'Safety Concern', 'Other',
  ];

  final List<String> _handymanBookingCategories = [
    'Payment Dispute', 'Customer No-Show or Unresponsive', 'Unsafe Work Environment', 'Scope of Work Changed', 'Unreasonable Customer Demands', 'Other',
  ];
  
  final List<String> _reportHandymanCategories = [
    'Misleading Profile Information', 'Inappropriate Profile Photo', 'Fake Reviews or Ratings', 'Unresponsive to Enquiries', 'Spam or Scam Behavior', 'Other',
  ];

  @override
  void initState() {
    super.initState();
    // *** MODIFIED: Load data based on which ID is provided ***
    _loadContextData();
  }
  
  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  // --- NEW: Main data loading function that decides what to fetch ---
  Future<void> _loadContextData() async {
    if (widget.bookingId != null) {
      // It's a report about a specific booking
      await _loadBookingSummary();
    } else if (widget.handymanId != null) {
      // It's a report about a handyman's profile
      await _loadHandymanSummary();
    }
  }

  Future<void> _loadBookingSummary() async {
    try {
      final bookingSnapshot = await FirebaseDatabase.instance.ref('bookings').child(widget.bookingId!).get();
      if (!mounted) return;

      if (bookingSnapshot.exists) {
        final bookingData = Booking.fromSnapshot(bookingSnapshot);
        final serviceSnapshot = await FirebaseDatabase.instance.ref('services').child(bookingData.serviceId).get();

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
  
  // --- NEW: Function to load handyman profile for reporting ---
  Future<void> _loadHandymanSummary() async {
    try {
      final handymanSnapshot = await FirebaseDatabase.instance.ref('users').child(widget.handymanId!).get();
      if (!mounted) return;
      
      if (handymanSnapshot.exists) {
        setState(() {
          _handymanDetails = Map<String, dynamic>.from(handymanSnapshot.value as Map);
          _isLoading = false;
        });
      } else {
         throw Exception("Handyman profile not found");
      }
    } catch (e) {
      if(mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load handyman details.";
        });
      }
    }
  }

  void _submitReport() async {
    if (!_formKey.currentState!.validate()) { return; }
    if (!_consentChecked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must acknowledge the terms to proceed.'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _isSubmitting = true);

    // In a real app, you would save this to a '/reports' node in Firebase.
    await Future.delayed(const Duration(seconds: 2));
    
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
    // *** MODIFIED: Choose the correct category list based on context ***
    List<String> categories;
    if (widget.bookingId != null && widget.bookingId!.startsWith('profile_report_')) {
      categories = _reportHandymanCategories;
    } else if (widget.userRole == 'Homeowner') {
      categories = _homeownerBookingCategories;
    } else {
      categories = _handymanBookingCategories;
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // *** MODIFIED: Conditionally show the correct summary card ***
          if (widget.bookingId != null && !_booking!.bookingId.startsWith('profile_report_'))
            _buildBookingSummaryCard()
          else
            _buildHandymanSummaryCard(),
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
  
  // --- NEW: Summary card for reporting a handyman profile ---
  Widget _buildHandymanSummaryCard() {
    final imageUrl = _handymanDetails?['profileImageUrl'] as String?;
    final name = _handymanDetails?['name'] ?? 'Handyman';

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
            CircleAvatar(
              radius: 35,
              backgroundColor: Colors.grey[200],
              backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
              child: imageUrl == null ? const Icon(Icons.person, color: Colors.grey, size: 35) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Reporting Handyman", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${widget.handymanId}',
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
