import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

// Import your Booking model to use its properties
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

  // Static list of other payment options
  final List<Map<String, dynamic>> _newPaymentOptions = [
    {'id': 'add_card', 'name': 'Credit/Debit Card', 'icon': Icons.credit_card_outlined},
    {'id': 'tng', 'name': 'Touch \'n Go eWallet', 'icon': Icons.wallet_giftcard_outlined}, // Placeholder icon
    {'id': 'boost', 'name': 'Boost eWallet', 'icon': Icons.rocket_launch_outlined}, // Placeholder icon
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
      // Fetch booking details
      final bookingSnapshot = await _dbRef.child('bookings').child(widget.bookingId).get();
      if (!mounted) return;

      if (bookingSnapshot.exists && bookingSnapshot.value != null) {
        _booking = Booking.fromSnapshot(bookingSnapshot);
      } else {
        throw Exception('Booking details not found.');
      }
      
      // TODO: Fetch saved payment methods from users/{uid}/paymentMethods
      // For now, we will use a default list including Cash.
      _savedPaymentMethods = [
        {'id': 'cash', 'name': 'Cash', 'icon': Icons.money_outlined},
        // Example of a saved card - this would be fetched from user data
        // {'id': 'card_1234', 'name': '**** **** **** 1234', 'icon': Icons.credit_card},
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

    // --- PAYMENT SIMULATION ---
    // In a real app, you would call your payment gateway SDK here.
    // For this simulation, we'll just show a loading indicator for 2 seconds.
    await Future.delayed(const Duration(seconds: 2));
    
    // --- UPDATE BOOKING STATUS ---
    try {
      await _dbRef.child('bookings').child(widget.bookingId).update({
        'status': 'Completed',
        'updatedAt': ServerValue.timestamp,
        'paymentMethod': _selectedPaymentMethodId // Store the selected method
      });

      if (!mounted) return;
      
      // Show success dialog
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
      
      // Pop the payment page to go back to the booking details page
      if (mounted) {
        Navigator.of(context).pop();
      }

    } catch (e) {
      print("Error updating booking status to Completed: $e");
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment simulation failed: ${e.toString()}'), backgroundColor: Colors.red),
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
              // SIMULATION: Show a snackbar message
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
