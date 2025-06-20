import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../../models/bookings_services.dart';

class PaymentPage extends StatefulWidget {
  final String bookingId;

  const PaymentPage({
    required this.bookingId,
    super.key,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // State Variables
  Booking? _booking;
  String? _selectedPaymentMethodId = 'cash'; // Default to 'Cash'
  List<Map<String, dynamic>> _savedPaymentMethods = [];

  bool _isLoading = true;
  String? _error;
  bool _isProcessingPayment = false;

  final List<Map<String, dynamic>> _newPaymentOptions = [
    {'id': 'add_card', 'name': 'Credit/Debit Card', 'icon': Icons.credit_card_outlined},
    {'id': 'tng', 'name': 'Touch \'n Go eWallet', 'icon': Icons.wallet_giftcard_outlined},
    {'id': 'boost', 'name': 'Boost eWallet', 'icon': Icons.rocket_launch_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _loadPaymentDetails();
  }
  
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  Future<void> _loadPaymentDetails() async {
    setStateIfMounted(() { _isLoading = true; _error = null; });
    final userId = _auth.currentUser?.uid;

    if (userId == null) {
      setStateIfMounted(() {
        _isLoading = false;
        _error = "User not authenticated. Please log in again.";
      });
      return;
    }

    try {
      final bookingSnapshot = await _dbRef.child('bookings').child(widget.bookingId).get();
      if (!mounted) return;

      if (bookingSnapshot.exists && bookingSnapshot.value != null) {
        _booking = Booking.fromSnapshot(bookingSnapshot);
      } else {
        throw Exception('Booking details not found.');
      }
      
      _savedPaymentMethods = [
        {'id': 'cash', 'name': 'Cash', 'icon': Icons.money_outlined},
      ];

    } catch (e) {
      print("Error loading payment details: $e");
      if (mounted) _error = "Failed to load payment details.";
    } finally {
      if (mounted) setStateIfMounted(() { _isLoading = false; });
    }
  }
  
  Future<void> _processPayment() async {
    if (_isProcessingPayment || _booking == null) return;

    setStateIfMounted(() { _isProcessingPayment = true; });

    await Future.delayed(const Duration(seconds: 2));
    
    try {
      final newPaymentRef = _dbRef.child('payments').push();
      final paymentId = newPaymentRef.key;
      if (paymentId == null) {
        throw Exception("Could not generate a payment ID.");
      }

      // 1. Prepare the new payment data
      final Map<String, dynamic> paymentData = {
        'paymentId': paymentId,
        'bookingId': widget.bookingId,
        'homeownerId': _booking!.homeownerId,
        'handymanId': _booking!.handymanId,
        'amount': _booking!.total, // Store total amount in sen
        'paymentMethod': _selectedPaymentMethodId,
        'status': 'Success',
        'createdAt': ServerValue.timestamp,
      };

      // 2. Prepare the booking update data
      final Map<String, dynamic> bookingUpdates = {
        'status': 'Completed',
        'paymentId': paymentId, // This is good practice for linking
        'updatedAt': ServerValue.timestamp,
      };

      // 3. Create a map for the multi-path atomic update
      final Map<String, dynamic> atomicUpdate = {};
      atomicUpdate['/payments/$paymentId'] = paymentData;
      
      final bookingMap = {
          'address': _booking!.address,
          'bookingDateTime': _booking!.bookingDateTime.millisecondsSinceEpoch,
          'bookingId': _booking!.bookingId,
          'cancellationReason': _booking!.cancellationReason,
          'couponCode': _booking!.couponCode,
          'declineReason': _booking!.declineReason,
          'description': _booking!.description,
          'handymanId': _booking!.handymanId,
          'homeownerId': _booking!.homeownerId,
          'price': _booking!.price,
          'priceType': _booking!.priceType,
          'quantity': _booking!.quantity,
          'scheduledDateTime': _booking!.scheduledDateTime.toIso8601String(),
          'serviceId': _booking!.serviceId,
          'serviceName': _booking!.serviceName,
          'status': _booking!.status,
          'subtotal': _booking!.subtotal,
          'tax': _booking!.tax,
          'total': _booking!.total,
      };

      bookingMap.addAll(bookingUpdates);
      
      atomicUpdate['/bookings/${widget.bookingId}'] = bookingMap;


      // 4. Execute the atomic update
      await _dbRef.root.update(atomicUpdate);

      // Create Notification for Handyman ---
      final homeownerSnapshot = await _dbRef.child('users/${_booking!.homeownerId}/name').get();
      final homeownerName = homeownerSnapshot.value as String? ?? 'Your customer';
      
      await _dbRef.child('notifications/${_booking!.handymanId}').push().set({
        'title': 'Payment Received!',
        'body': '$homeownerName has paid for the booking "${_booking!.serviceName}".',
        'bookingId': widget.bookingId,
        'type': 'payment_received',
        'isRead': false,
        'createdAt': ServerValue.timestamp,
      });

      if (!mounted) return;
      
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Payment Successful!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                radius: 30,
                backgroundColor: Colors.green,
                child: Icon(Icons.check, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                'Thank you for your payment. Your booking is now completed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      
      if (mounted) {
        Navigator.of(context).pop();
      }

    } catch (e) {
      print("Error during atomic payment update: $e");
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment processing failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setStateIfMounted(() { _isProcessingPayment = false; });
    }
  }

  // --- WIDGET BUILDERS ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Payment'),
        elevation: 1,
        backgroundColor: Theme.of(context).cardColor,
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildPayButton(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_error!, style: const TextStyle(color: Colors.red))));
    }
    if (_booking == null) {
      return const Center(child: Text('Booking details could not be loaded.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildPriceBreakdownCard(),
        const SizedBox(height: 24),
        _buildSectionTitle('Choose Payment Method'),
        _buildPaymentMethodsList(),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        _buildSectionTitle('Add a New Method'),
        _buildAddNewMethodsList(),
      ],
    );
  }

  Widget _buildPriceBreakdownCard() {
    final double price = (_booking!.price ?? 0.0);
    final int quantity = _booking!.quantity > 0 ? _booking!.quantity : 1;
    final double subtotal = (_booking!.subtotal / 100.0);
    final double tax = (_booking!.tax / 100.0);
    final double total = (_booking!.total / 100.0);

    return Card(
      elevation: 0,
      color: Colors.blue[50]?.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Summary for "${_booking!.serviceName}"',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_booking!.priceType == 'Hourly')
              _buildPriceRow('Service Price', 'RM ${price.toStringAsFixed(2)} x $quantity Hours'),
            _buildPriceRow('Subtotal', 'RM ${subtotal.toStringAsFixed(2)}'),
            _buildPriceRow('SST (8%)', 'RM ${tax.toStringAsFixed(2)}'),
            const Divider(height: 24, thickness: 1),
            _buildPriceRow('Total Amount', 'RM ${total.toStringAsFixed(2)}', isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: isTotal ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildPaymentMethodsList() {
    return Column(
      children: _savedPaymentMethods.map((method) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey[300]!)
          ),
          child: RadioListTile<String>(
            value: method['id'],
            groupValue: _selectedPaymentMethodId,
            onChanged: (value) {
              setState(() {
                _selectedPaymentMethodId = value;
              });
            },
            title: Text(method['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
            secondary: Icon(method['icon'] as IconData?, color: Theme.of(context).primaryColor),
            activeColor: Theme.of(context).primaryColor,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAddNewMethodsList() {
    return Column(
      children: _newPaymentOptions.map((option) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
           elevation: 0,
           shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey[200]!)
          ),
          child: ListTile(
            leading: Icon(option['icon'] as IconData?, color: Colors.grey[700]),
            title: Text(option['name']),
            trailing: const Icon(Icons.add, size: 20),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Simulating adding a new ${option['name']}...'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        );
      }).toList(),
    );
  }
  
  Widget _buildPayButton() {
    if (_isLoading || _booking == null) return const SizedBox.shrink();
    
    final double total = _booking!.total / 100.0;
    
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: (_isProcessingPayment || _selectedPaymentMethodId == null)
              ? null
              : _processPayment,
          child: _isProcessingPayment
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
              : Text('Pay RM ${total.toStringAsFixed(2)}'),
        ),
      ),
    );
  }
}
