import 'dart:async'; // For Future
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';

// Assuming your Booking model is correctly defined
// import '../../models/bookings_services.dart'; // If you create a model for Booking

class BookServicePage extends StatefulWidget {
  final String serviceId;
  final String? handymanId; // Made handymanId explicitly nullable for clarity

  const BookServicePage({
    required this.serviceId,
    this.handymanId, // Can be null if serviceData provides it
    super.key,
  });

  @override
  State<BookServicePage> createState() => _BookServicePageState();
}

class _BookServicePageState extends State<BookServicePage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  // Controllers
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _couponController = TextEditingController();

  // State Variables
  Map<String, dynamic>? _serviceData; // Holds fetched service details
  String? _userHomeAddress;
  int _quantity = 1; // Default quantity, adjustable for hourly services

  // Date and Time Slot Selection
  DateTime? _selectedDateOnly; // Stores only the date part (YYYY-MM-DD)
  TimeOfDay? _selectedTimeSlot; // Stores the START TimeOfDay of the selected slot/block
  Set<TimeOfDay> _allOccupiedOneHourSegments = {}; // Stores all individual 1-hour segments that are occupied
  bool _isLoadingSlots = false; // For loading indicator when fetching slots

  // Getter to construct the full DateTime for the start of the selected service
  DateTime? get _finalSelectedDateTime {
    if (_selectedDateOnly != null && _selectedTimeSlot != null) {
      return DateTime(
        _selectedDateOnly!.year,
        _selectedDateOnly!.month,
        _selectedDateOnly!.day,
        _selectedTimeSlot!.hour,
        _selectedTimeSlot!.minute,
      );
    }
    return null;
  }

  // Pricing
  int _subtotal = 0; // In sen
  int _tax = 0;      // In sen
  int _total = 0;    // In sen

  // Other states
  bool _termsAccepted = false; // For confirmation dialog
  bool _isLoading = true;      // Initial page load
  bool _isProcessingLocation = false;
  bool _isBooking = false;     // For final booking submission
  String? _error;

  // Constants
  static const double TAX_RATE = 0.08; // 8% SST
  // Define all possible 1-hour start times for services (8 AM to 4 PM)
  static final List<TimeOfDay> _allPossibleTimeSlots = List.generate(
    9, // 8:00, 9:00, ..., 16:00 (4 PM)
    (index) => TimeOfDay(hour: 8 + index, minute: 0),
  );
  // Services cannot extend beyond 5 PM (17:00)
  static const int _serviceEndTimeHour = 17;

  // *** NEW: Define statuses that block time slots ***
  static const List<String> _slotBlockingStatuses = [
    "Pending",
    "Accepted",
    "En Route",
    "Ongoing",
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _descriptionController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  // Helper function to create a notification
  Future<void> _createNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    String? bookingId,
  }) async {
    final notificationsRef = _dbRef.child('notifications/$userId').push();
    // Set notification data in Firebase
    await notificationsRef.set({
      'notificationId': notificationsRef.key,
      'title': title,
      'body': body,
      'type': type,
      'bookingId': bookingId,
      'isRead': false, // Always set as unread initially
      'createdAt': ServerValue.timestamp,
    });
  }

  // Helper to safely call setState only if the widget is still mounted
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // Fetch service details and user's home address
  Future<void> _loadInitialData() async {
    setStateIfMounted(() { _isLoading = true; _error = null; });
    final userId = _auth.currentUser?.uid;
    try {
      final serviceSnapshot = await _dbRef.child('services').child(widget.serviceId).get();
      if (!mounted) return;
      if (serviceSnapshot.exists && serviceSnapshot.value != null) {
        _serviceData = Map<String, dynamic>.from(serviceSnapshot.value as Map);
        // Initialize quantity based on service type
        if (_serviceData?['priceType'] == 'Fixed') {
          _quantity = 1; // Fixed price services have a quantity of 1 hour implicitly
        } else { // Hourly
          // You could have a default quantity for hourly services or let it be 1
          _quantity = 1; // Default to 1 hour for hourly, user can adjust
        }
      } else {
        throw Exception('Service details not found.');
      }

      if (userId != null) {
        final userSnapshot = await _dbRef.child('users').child(userId).child('address').get();
        if (mounted && userSnapshot.exists && userSnapshot.value != null) {
          _userHomeAddress = userSnapshot.value.toString();
        }
      }
      _calculatePriceDetails(); // Calculate price after loading service data
    } catch (e) {
      print("Error loading initial booking data: $e");
      if (mounted) _error = "Failed to load booking details.";
    } finally {
      if (mounted) setStateIfMounted(() { _isLoading = false; });
    }
  }

  // Calculate prices in sen (integers)
  void _calculatePriceDetails() {
    if (_serviceData == null) return;

    final double priceDouble = (_serviceData!['price'] as num?)?.toDouble() ?? 0.0;
    final int priceInSen = (priceDouble * 100).round();
    final String priceType = _serviceData!['priceType'] ?? 'Fixed';
    
    // For hourly services, price depends on quantity. For fixed, it's a one-time price.
    final int calculationQuantity = (priceType == 'Hourly') ? _quantity : 1;

    final int subtotalInSen = priceInSen * calculationQuantity;
    final int taxInSen = (subtotalInSen * TAX_RATE).round();
    final int totalInSen = subtotalInSen + taxInSen;

    setStateIfMounted(() {
        _subtotal = subtotalInSen;
        _tax = taxInSen;
        _total = totalInSen;
    });
  }

  // Increment quantity for hourly services
  void _incrementQuantity() {
    if (_serviceData?['priceType'] == 'Hourly') {
      setState(() {
        _quantity++;
        _calculatePriceDetails();
        _selectedTimeSlot = null; // Reset slot selection as duration changed
        if(_selectedDateOnly != null) _fetchBookedSlotsForDate(_selectedDateOnly!); // Re-evaluate slots
      });
    }
  }

  // Decrement quantity for hourly services
  void _decrementQuantity() {
    if (_serviceData?['priceType'] == 'Hourly' && _quantity > 1) {
      setState(() {
        _quantity--;
        _calculatePriceDetails();
        _selectedTimeSlot = null; // Reset slot selection
        if(_selectedDateOnly != null) _fetchBookedSlotsForDate(_selectedDateOnly!); // Re-evaluate slots
      });
    }
  }

  void _useHomeAddress() {
    if (_userHomeAddress != null && _userHomeAddress!.isNotEmpty) {
      setState(() { _addressController.text = _userHomeAddress!; });
    } else {
      ScaffoldMessenger.of(context).showSnackBar( const SnackBar( content: Text('Home address not found in your profile. Please update it first.'), backgroundColor: Colors.orange,),);
    }
  }

  Future<void> _getCurrentLocationForAddress() async {
    if (_isProcessingLocation) return;
    setStateIfMounted(() { _isProcessingLocation = true; });
    LocationPermission permission; bool serviceEnabled; serviceEnabled = await Geolocator.isLocationServiceEnabled(); if (!serviceEnabled) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.'))); setStateIfMounted(() { _isProcessingLocation = false; }); return; } permission = await Geolocator.checkPermission(); if (permission == LocationPermission.denied) { permission = await Geolocator.requestPermission(); if (permission == LocationPermission.denied) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions denied.'))); setStateIfMounted(() { _isProcessingLocation = false; }); return; } } if (permission == LocationPermission.deniedForever) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions permanently denied.'))); setStateIfMounted(() { _isProcessingLocation = false; }); return; } try { Position position = await Geolocator.getCurrentPosition(); List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude); if (placemarks.isNotEmpty && mounted) { final p = placemarks.first; final String formattedAddress = [p.street, p.subLocality, p.locality, p.postalCode, p.administrativeArea].where((s) => s != null && s.isNotEmpty).join(', '); setState(() { _addressController.text = formattedAddress; }); } } catch (e) { print("Error getting location for address: $e"); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not determine current address.'))); } finally { if (mounted) setStateIfMounted(() { _isProcessingLocation = false; }); }
  }

  // Date Picker now also triggers fetching slots for the selected date
  Future<void> _pickDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDateOnly ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (pickedDate != null && pickedDate != _selectedDateOnly) {
      setState(() {
        _selectedDateOnly = pickedDate;
        _selectedTimeSlot = null; // Reset selected time slot when date changes
        _allOccupiedOneHourSegments.clear(); // Clear previously fetched booked slots
      });
      // Fetch available slots for the newly selected date
      _fetchBookedSlotsForDate(pickedDate);
    }
  }

  // Fetch booked slots for a specific date and handyman, considering service duration and booking status
  Future<void> _fetchBookedSlotsForDate(DateTime date) async {
    if (!mounted) return;
    setStateIfMounted(() { _isLoadingSlots = true; });

    final String? handymanIdToQuery = widget.handymanId ?? _serviceData?['handymanId'];
    if (handymanIdToQuery == null) {
      print("Error: Handyman ID is not available for fetching slots.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not fetch slots: Handyman details missing.'), backgroundColor: Colors.red,));
        setStateIfMounted(() { _isLoadingSlots = false; });
      }
      return;
    }

    _allOccupiedOneHourSegments.clear(); 

    try {
      final query = _dbRef
          .child('bookings')
          .orderByChild('handymanId')
          .equalTo(handymanIdToQuery);

      final snapshot = await query.get();
      if (snapshot.exists && snapshot.value != null) {
        final bookingsData = Map<String, dynamic>.from(snapshot.value as Map);
        bookingsData.forEach((bookingId, bookingData) {
          if (bookingData is Map) {
            final bookingMap = Map<String, dynamic>.from(bookingData);
            final String? bookingStatus = bookingMap['status'] as String?;
            final scheduledDateTimeString = bookingMap['scheduledDateTime'] as String?;

            // Only consider bookings with slot-blocking statuses
            if (bookingStatus != null && _slotBlockingStatuses.contains(bookingStatus) && scheduledDateTimeString != null) {
              final scheduledDateTime = DateTime.tryParse(scheduledDateTimeString);
              if (scheduledDateTime != null &&
                  scheduledDateTime.year == date.year &&
                  scheduledDateTime.month == date.month &&
                  scheduledDateTime.day == date.day) {
                
                int durationHours = 1;
                if (bookingMap['priceType'] == 'Hourly') {
                  durationHours = (bookingMap['quantity'] as int?) ?? 1;
                  if (durationHours < 1) durationHours = 1;
                }
                for (int i = 0; i < durationHours; i++) {
                  final int slotHour = scheduledDateTime.hour + i;
                  if (slotHour < _serviceEndTimeHour) { 
                    _allOccupiedOneHourSegments.add(TimeOfDay(hour: slotHour, minute: 0));
                  }
                }
              }
            }
          }
        });
      }
    } catch (e) {
      print("Error fetching booked slots: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error fetching available slots.'), backgroundColor: Colors.red,));
      }
    } finally {
      if (mounted) {
        setStateIfMounted(() { _isLoadingSlots = false; });
      }
    }
  }

  // Show Confirmation Dialog
  void _showConfirmationDialog() {
    if (!_formKey.currentState!.validate()) { 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields correctly.'), backgroundColor: Colors.orange));
      return; 
    }
    if (_selectedDateOnly == null || _selectedTimeSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date and an available time slot.'), backgroundColor: Colors.orange,));
      return;
    }
    
    final DateTime finalDateTime = _finalSelectedDateTime!;
    bool dialogTermsAccepted = _termsAccepted; 

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final String displayTotal = (_total / 100.0).toStringAsFixed(2);
            int displayDuration = (_serviceData?['priceType'] == 'Hourly' ? _quantity : 1);
            if (displayDuration < 1) displayDuration = 1;
            DateTime endTime = finalDateTime.add(Duration(hours: displayDuration));

            return AlertDialog(
              title: const Text("Confirm Booking"),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    const Text("Would you like to proceed to confirm this booking?"),
                    const SizedBox(height: 16),
                    Text('Service: ${_serviceData?['name'] ?? 'N/A'}'),
                    Text('Date: ${DateFormat('EEE, MMM d, yyyy').format(finalDateTime)}'),
                    Text('Time: ${DateFormat('hh:mm a').format(finalDateTime)} - ${DateFormat('hh:mm a').format(endTime)} ($displayDuration hour${displayDuration > 1 ? 's' : ''})'),
                    const SizedBox(height: 8),
                    Text('Total Price: RM $displayTotal', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: dialogTermsAccepted,
                          onChanged: (bool? value) { setDialogState(() { dialogTermsAccepted = value ?? false; }); },
                        ),
                        const Expanded(child: Text("By confirming, you agree to our terms of service.", style: TextStyle(fontSize: 12))),
                      ],
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop(),),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
                  onPressed: dialogTermsAccepted ? () { Navigator.of(context).pop(); _confirmBooking(finalDateTime); } : null,
                  child: const Text("Confirm"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Final booking logic with integer prices and real-time slot check
  Future<void> _confirmBooking(DateTime finalScheduledDateTime) async {
    if (_isBooking) return;
    final currentUser = _auth.currentUser;
    final currentServiceData = _serviceData;
    final address = _addressController.text.trim();
    final String? handymanIdToBook = widget.handymanId ?? currentServiceData?['handymanId'];

    if (currentUser == null || currentServiceData == null || address.isEmpty || handymanIdToBook == null) {
      ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Missing required information to book.'), backgroundColor: Colors.red),);
      return;
    }

    setStateIfMounted(() { _isBooking = true; });

    try {
      final int durationNeeded = (currentServiceData['priceType'] == 'Hourly') ? _quantity : 1;
      final isSlotStillAvailable = await _checkSlotAvailabilityRealtime(handymanIdToBook, finalScheduledDateTime, durationNeeded, _slotBlockingStatuses);

      if (!mounted) return; 
      if (!isSlotStillAvailable) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sorry, one or more selected time slots were just booked. Please select another.'), backgroundColor: Colors.orange, duration: Duration(seconds: 3),));
         setStateIfMounted(() {
            _isBooking = false;
            if (_selectedDateOnly != null) _fetchBookedSlotsForDate(_selectedDateOnly!); 
        });
        return;
      }
      
      final newBookingRef = _dbRef.child('bookings').push();
      final bookingId = newBookingRef.key;
      if (bookingId == null) throw Exception("Failed to generate booking ID.");

      final Map<String, dynamic> bookingData = {
        'bookingId': bookingId, 'serviceId': widget.serviceId, 'serviceName': currentServiceData['name'] ?? 'N/A',
        'handymanId': handymanIdToBook, 'homeownerId': currentUser.uid,
        'scheduledDateTime': finalScheduledDateTime.toIso8601String(),
        'address': address, 'description': _descriptionController.text.trim(),
        'quantity': _quantity, 
        'price': currentServiceData['price'] ?? 0.0, 'priceType': currentServiceData['priceType'] ?? 'Fixed',
        'subtotal': _subtotal, 'tax': _tax, 'total': _total,
        'couponCode': _couponController.text.trim().isEmpty ? null : _couponController.text.trim(),
        'status': "Pending", 'bookingDateTime': ServerValue.timestamp,
      };
      await newBookingRef.set(bookingData);
      // Create Notification for Handyman 
      final homeownerSnapshot = await _dbRef.child('users/${currentUser.uid}/name').get();
      final homeownerName = homeownerSnapshot.value as String? ?? 'A new customer';
      await _createNotification(
        userId: handymanIdToBook,
        title: 'New Booking Request!',
        body: '$homeownerName has requested a booking for "${currentServiceData['name']}".',
        bookingId: bookingId,
        type: 'new_booking', // Use a new type for this notification
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking request submitted successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("Error saving booking: $e");
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Failed to submit booking: ${e.toString()}'), backgroundColor: Colors.red),); }
    } finally {
      if (mounted) setStateIfMounted(() { _isBooking = false; });
    }
  }

  // Real-time check for slot availability before final booking, considering duration and blocking statuses
  Future<bool> _checkSlotAvailabilityRealtime(String handymanId, DateTime startTime, int durationHours, List<String> blockingStatuses) async {
    final dateOnly = DateTime(startTime.year, startTime.month, startTime.day);
    Set<TimeOfDay> currentlyOccupiedOneHourSegments = {};

    try {
      final query = _dbRef.child('bookings').orderByChild('handymanId').equalTo(handymanId);
      final snapshot = await query.get();

      if (snapshot.exists && snapshot.value != null) {
        final bookingsData = Map<String, dynamic>.from(snapshot.value as Map);
        bookingsData.forEach((bookingId, bookingData) {
          if (bookingData is Map) {
            final bookingMap = Map<String, dynamic>.from(bookingData);
            final String? bookingStatus = bookingMap['status'] as String?;
            final scheduledDateTimeString = bookingMap['scheduledDateTime'] as String?;

            if (bookingStatus != null && blockingStatuses.contains(bookingStatus) && scheduledDateTimeString != null) {
              final scheduledDateTime = DateTime.tryParse(scheduledDateTimeString);
              if (scheduledDateTime != null &&
                  scheduledDateTime.year == dateOnly.year &&
                  scheduledDateTime.month == dateOnly.month &&
                  scheduledDateTime.day == dateOnly.day) {
                
                int existingBookingDuration = 1;
                if (bookingMap['priceType'] == 'Hourly') {
                  existingBookingDuration = (bookingMap['quantity'] as int?) ?? 1;
                  if (existingBookingDuration < 1) existingBookingDuration = 1;
                }
                for (int i = 0; i < existingBookingDuration; i++) {
                  final int slotHour = scheduledDateTime.hour + i;
                  if (slotHour < _serviceEndTimeHour) {
                    currentlyOccupiedOneHourSegments.add(TimeOfDay(hour: slotHour, minute: 0));
                  }
                }
              }
            }
          }
        });
      }
      for (int i = 0; i < durationHours; i++) {
        final int currentHour = startTime.hour + i;
        if (currentHour >= _serviceEndTimeHour) return false;
        if (currentlyOccupiedOneHourSegments.contains(TimeOfDay(hour: currentHour, minute: 0))) {
          return false;
        }
      }
      return true;
    } catch (e) {
      print("Error checking slot availability in realtime: $e");
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book Service'), elevation: 1,),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_error!, style: const TextStyle(color: Colors.red))))
              : _buildBookingForm(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[400],
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            onPressed: (_isBooking || _isLoadingSlots) ? null : _showConfirmationDialog,
            child: _isBooking
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0))
                : const Text('Confirm Booking'),
          ),
        ),
      ),
    );
  }

  Widget _buildBookingForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildQuantitySection(),
          const SizedBox(height: 24),
          _buildSectionTitle('Service Address'),
          _buildAddressSection(),
          const SizedBox(height: 24),
          _buildSectionTitle('Booking Notes (Optional)'),
          _buildDescriptionSection(),
          const SizedBox(height: 24),
          _buildSectionTitle('Select Date & Time'),
          _buildDateTimePickerSection(),
          const SizedBox(height: 24),
          _buildSectionTitle('Coupon Code'),
          _buildCouponSection(),
          const SizedBox(height: 24),
          _buildSectionTitle('Price Details'),
          _buildPriceDetailsSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildQuantitySection() {
    final priceType = _serviceData?['priceType'] ?? 'Fixed';
    final isHourly = priceType == 'Hourly';
    final serviceName = _serviceData?['name'] ?? 'Service';
    final imageUrl = _serviceData?['imageUrl'] as String?;
    return Card(
      elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(serviceName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(isHourly ? 'per hour (Qty: $_quantity)' : 'Fixed Price', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            _buildCounter(enabled: isHourly),
          ],),),
          const SizedBox(width: 16),
          ClipRRect(borderRadius: BorderRadius.circular(8.0), child: Container(width: 70, height: 70, color: Colors.grey[200], child: (imageUrl != null && imageUrl.isNotEmpty) ? Image.network(imageUrl, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2.0)), errorBuilder: (context, error, stack) => const Icon(Icons.error_outline, color: Colors.grey),) : const Icon(Icons.construction, size: 30, color: Colors.grey),),),
        ],),
      ),
    );
  }

  Widget _buildCounter({required bool enabled}) {
    return Row( mainAxisSize: MainAxisSize.min, children: [
      IconButton(icon: const Icon(Icons.remove_circle_outline), iconSize: 28, color: enabled && _quantity > 1 ? Theme.of(context).colorScheme.primary : Colors.grey, onPressed: enabled && _quantity > 1 ? _decrementQuantity : null, padding: EdgeInsets.zero, constraints: const BoxConstraints(),),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12.0), child: Text('$_quantity', style: Theme.of(context).textTheme.titleMedium),),
      IconButton(icon: const Icon(Icons.add_circle_outline), iconSize: 28, color: enabled ? Theme.of(context).colorScheme.primary : Colors.grey, onPressed: enabled ? _incrementQuantity : null, padding: EdgeInsets.zero, constraints: const BoxConstraints(),),
    ],);
  }

  Widget _buildAddressSection() {
    return Column( children: [
      TextFormField( controller: _addressController, maxLines: 3, minLines: 1, keyboardType: TextInputType.streetAddress, decoration: const InputDecoration( hintText: 'Enter service address (e.g., Street, City, Postcode, State)', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),), validator: (value) { if (value == null || value.trim().isEmpty) { return 'Please enter the service address'; } return null; }, autovalidateMode: AutovalidateMode.onUserInteraction,),
      const SizedBox(height: 8),
      Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        TextButton.icon( icon: const Icon(Icons.home_outlined, size: 18), label: const Text('Use Home Address'), onPressed: _isProcessingLocation ? null : _useHomeAddress,),
        TextButton.icon( icon: _isProcessingLocation ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.0)) : const Icon(Icons.my_location, size: 18), label: const Text('Use Current Location'), onPressed: _isProcessingLocation ? null : _getCurrentLocationForAddress,),
      ],),
    ],);
  }

  Widget _buildDescriptionSection() {
    return TextFormField( controller: _descriptionController, maxLines: 4, minLines: 2, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration( hintText: 'Add any specific requirements or notes for the handyman (optional)...', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),),);
  }

  Widget _buildDateTimePickerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0, shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            title: Text(
              _selectedDateOnly == null ? 'Select Date *' : 'Date: ${DateFormat('EEE, MMM d, yyyy').format(_selectedDateOnly!)}',
              style: TextStyle(fontSize: 16, color: _selectedDateOnly == null ? Colors.grey[600] : null,),
            ),
            trailing: Icon(Icons.calendar_today_outlined, color: Theme.of(context).primaryColor),
            onTap: _isLoadingSlots || _isBooking ? null : _pickDate,
          ),
        ),
        if (_selectedDateOnly != null) ...[
          const SizedBox(height: 16),
          _buildSectionTitle("Available Time Slots"),
          _isLoadingSlots
              ? const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 16.0), child: CircularProgressIndicator(strokeWidth: 2.0)))
              : _buildTimeSlotChips(),
        ]
      ],
    );
  }

  Widget _buildTimeSlotChips() {
    if (_allPossibleTimeSlots.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Text("No service slots defined.", style: TextStyle(color: Colors.grey)));
    }

    int currentBookingDuration = 1;
    if (_serviceData?['priceType'] == 'Hourly') {
      currentBookingDuration = _quantity;
      if (currentBookingDuration < 1) currentBookingDuration = 1;
    }

    return Wrap(
      spacing: 8.0, runSpacing: 8.0,
      children: _allPossibleTimeSlots.map((slot) {
        bool canSelectThisSlot = true;
        bool isPartOfOccupiedBlock = false;

        for (int i = 0; i < currentBookingDuration; i++) {
          final int checkHour = slot.hour + i;
          if (checkHour >= _serviceEndTimeHour) {
            canSelectThisSlot = false; break;
          }
          if (_allOccupiedOneHourSegments.contains(TimeOfDay(hour: checkHour, minute: 0))) {
            canSelectThisSlot = false; break;
          }
        }
        
        if(_allOccupiedOneHourSegments.contains(slot)){
            isPartOfOccupiedBlock = true;
        }

        final bool isCurrentlySelectedStartSlot = _selectedTimeSlot == slot;
        
        bool isPastSlot = false;
        if (_selectedDateOnly != null &&
            _selectedDateOnly!.year == DateTime.now().year &&
            _selectedDateOnly!.month == DateTime.now().month &&
            _selectedDateOnly!.day == DateTime.now().day) {
              final now = TimeOfDay.fromDateTime(DateTime.now());
              if (slot.hour < now.hour || (slot.hour == now.hour && slot.minute < now.minute)) {
                isPastSlot = true;
              }
        }
        
        final bool isDisabledChip = isPartOfOccupiedBlock || !canSelectThisSlot || isPastSlot;

        return ChoiceChip(
          label: Text(
            DateFormat.jm().format(DateTime(2022, 1, 1, slot.hour, slot.minute)),
            style: TextStyle(
              color: isDisabledChip ? Colors.grey[500] : (isCurrentlySelectedStartSlot ? Colors.white : Theme.of(context).colorScheme.onSurface),
              fontWeight: isCurrentlySelectedStartSlot ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          selected: isCurrentlySelectedStartSlot,
          selectedColor: Theme.of(context).primaryColor,
          backgroundColor: isDisabledChip ? Colors.grey[300] : (isCurrentlySelectedStartSlot ? Theme.of(context).primaryColor : Colors.grey[100]),
          disabledColor: Colors.grey[350],
          onSelected: (isDisabledChip || _isBooking || _isLoadingSlots)
              ? null
              : (bool selected) {
                  setState(() {
                    if (selected) {
                      _selectedTimeSlot = slot;
                    } else {
                       if (_selectedTimeSlot == slot) _selectedTimeSlot = null;
                    }
                  });
                },
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(
              color: isDisabledChip ? Colors.grey[400]! : (isCurrentlySelectedStartSlot ? Theme.of(context).primaryColor : Colors.grey[400]!),
            ),
          ),
          showCheckmark: false,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        );
      }).toList(),
    );
  }

  Widget _buildCouponSection() {
    return TextField( controller: _couponController, decoration: InputDecoration( hintText: 'Enter coupon code (optional)', prefixIcon: Icon(Icons.local_offer_outlined, color: Colors.grey[600]), suffixIcon: TextButton( onPressed: () { print('Apply Coupon: ${_couponController.text}'); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coupon feature coming soon!'))); }, child: const Text('Apply'),), border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0), isDense: true,),);
  }

  Widget _buildPriceDetailsSection() {
    return Card(elevation: 0, color: Colors.blue[50]?.withOpacity(0.5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), child: Padding( padding: const EdgeInsets.all(16.0), child: Column(children: [ _buildPriceRow('Subtotal', _subtotal), _buildPriceRow('SST (8%)', _tax), const Divider(height: 16, thickness: 1), _buildPriceRow('Total Amount', _total, isTotal: true),],),),);
  }

  Widget _buildPriceRow(String label, int amountInSen, {bool isTotal = false}) {
    final double amountRM = amountInSen / 100.0; return Padding( padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text(label, style: TextStyle(fontSize: isTotal ? 16 : 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)), Text( 'RM ${amountRM.toStringAsFixed(2)}', style: TextStyle(fontSize: isTotal ? 16 : 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal))],),);
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}