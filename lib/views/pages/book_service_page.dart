import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart'; // For date/time formatting

class BookServicePage extends StatefulWidget {
  final String serviceId;
  final String? handymanId;

  const BookServicePage({
    required this.serviceId,
    this.handymanId,
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
  Map<String, dynamic>? _serviceData;
  String? _userHomeAddress;
  int _quantity = 1;
  DateTime? _selectedDateTime;
  // *** Store prices as Integers (sen) ***
  int _subtotal = 0; // In sen
  int _tax = 0;      // In sen
  int _total = 0;    // In sen
  // *** End of change ***
  bool _termsAccepted = false;
  bool _isLoading = true;
  bool _isProcessingLocation = false;
  bool _isBooking = false;
  String? _error;

  // Constants
  static const double TAX_RATE = 0.08; // 8% SST

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

  // Fetch service details and user's home address
  Future<void> _loadInitialData() async {
    setStateIfMounted(() { _isLoading = true; _error = null; });
    final userId = _auth.currentUser?.uid;
    try {
      final serviceSnapshot = await _dbRef.child('services').child(widget.serviceId).get();
      if (!mounted) return;
      if (serviceSnapshot.exists && serviceSnapshot.value != null) {
        _serviceData = Map<String, dynamic>.from(serviceSnapshot.value as Map);
        if (_serviceData?['priceType'] == 'Fixed') { _quantity = 1; }
      } else { throw Exception('Service details not found.'); }
      if (userId != null) {
        final userSnapshot = await _dbRef.child('users').child(userId).child('address').get();
         if (mounted && userSnapshot.exists && userSnapshot.value != null) {
           _userHomeAddress = userSnapshot.value.toString();
         }
      }
      // Calculate initial price after loading service data
      _calculatePriceDetails();
    } catch (e) {
      print("Error loading initial booking data: $e");
      if (mounted) _error = "Failed to load booking details.";
    } finally {
      if (mounted) setStateIfMounted(() { _isLoading = false; });
    }
  }

  // *** MODIFIED: Calculate prices in sen (integers) ***
  void _calculatePriceDetails() {
    if (_serviceData == null) return;

    // Best practice: Store service price as sen (int) in DB.
    // Workaround: Convert double price from DB to sen here.
    final double priceDouble = (_serviceData!['price'] as num?)?.toDouble() ?? 0.0;
    final int priceInSen = (priceDouble * 100).round(); // Convert RM (e.g., 69.90) to sen (6990)

    final priceType = _serviceData!['priceType'] ?? 'Fixed';
    final calculationQuantity = (priceType == 'Hourly') ? _quantity : 1;

    // Perform calculations using integers (sen)
    final int subtotalInSen = priceInSen * calculationQuantity;
    final int taxInSen = (subtotalInSen * TAX_RATE).round(); // Calculate tax in sen and round
    final int totalInSen = subtotalInSen + taxInSen;

    // Update state variables (already wrapped in setState where needed)
    _subtotal = subtotalInSen;
    _tax = taxInSen;
    _total = totalInSen;
  }
  // *** END OF MODIFICATION ***

  // Increment quantity
  void _incrementQuantity() {
    if (_serviceData?['priceType'] == 'Hourly') {
      setState(() {
        _quantity++;
        _calculatePriceDetails(); // Recalculate price
      });
    }
  }

  // Decrement quantity
  void _decrementQuantity() {
    if (_serviceData?['priceType'] == 'Hourly' && _quantity > 1) {
      setState(() {
        _quantity--;
        _calculatePriceDetails(); // Recalculate price
      });
    }
  }

  // Use stored home address
  void _useHomeAddress() {
    // ... (logic remains the same) ...
    if (_userHomeAddress != null && _userHomeAddress!.isNotEmpty) { setState(() { _addressController.text = _userHomeAddress!; }); }
    else { ScaffoldMessenger.of(context).showSnackBar( const SnackBar( content: Text('Home address not found in your profile. Please update it first.'), backgroundColor: Colors.orange,),); }
  }

  // Get current GPS location and fill address
  Future<void> _getCurrentLocationForAddress() async {
    // ... (logic remains the same) ...
     if (_isProcessingLocation) return;
     setStateIfMounted(() { _isProcessingLocation = true; });
     LocationPermission permission; bool serviceEnabled;
     serviceEnabled = await Geolocator.isLocationServiceEnabled();
     if (!serviceEnabled) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.'))); setStateIfMounted(() { _isProcessingLocation = false; }); return; }
     permission = await Geolocator.checkPermission();
     if (permission == LocationPermission.denied) { permission = await Geolocator.requestPermission(); if (permission == LocationPermission.denied) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions denied.'))); setStateIfMounted(() { _isProcessingLocation = false; }); return; } }
     if (permission == LocationPermission.deniedForever) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions permanently denied.'))); setStateIfMounted(() { _isProcessingLocation = false; }); return; }
     try { Position position = await Geolocator.getCurrentPosition(); List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude); if (placemarks.isNotEmpty && mounted) { final p = placemarks.first; final String formattedAddress = [p.street, p.subLocality, p.locality, p.postalCode, p.administrativeArea].where((s) => s != null && s.isNotEmpty).join(', '); setState(() { _addressController.text = formattedAddress; }); } }
     catch (e) { print("Error getting location for address: $e"); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not determine current address.'))); }
     finally { if (mounted) setStateIfMounted(() { _isProcessingLocation = false; }); }
  }

  // Show Date Picker
  Future<void> _pickDate() async {
    // ... (logic remains the same) ...
     final DateTime? pickedDate = await showDatePicker( context: context, initialDate: _selectedDateTime ?? DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)),);
     if (pickedDate != null) { final currentTime = _selectedDateTime ?? DateTime.now(); setState(() { _selectedDateTime = DateTime( pickedDate.year, pickedDate.month, pickedDate.day, currentTime.hour, currentTime.minute); }); }
  }

  // Show Time Picker
  Future<void> _pickTime() async {
    // ... (logic remains the same) ...
     final TimeOfDay? pickedTime = await showTimePicker( context: context, initialTime: TimeOfDay.fromDateTime(_selectedDateTime ?? DateTime.now()),);
     if (pickedTime != null) { final currentDate = _selectedDateTime ?? DateTime.now(); setState(() { _selectedDateTime = DateTime( currentDate.year, currentDate.month, currentDate.day, pickedTime.hour, pickedTime.minute); }); }
  }

  // Show Confirmation Dialog
  void _showConfirmationDialog() {
    // ... (validation logic remains the same) ...
    if (_addressController.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a service address.'), backgroundColor: Colors.orange)); return; }
    if (_selectedDateTime == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a date and time.'), backgroundColor: Colors.orange)); return; }

    bool dialogTermsAccepted = _termsAccepted; // Initialize with current state

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // *** Format total price from sen for display ***
            final String displayTotal = (_total / 100.0).toStringAsFixed(2);
            return AlertDialog(
              title: const Text("Confirm Booking"),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    const Text("Would you like to proceed to confirm this booking?"),
                    const SizedBox(height: 16),
                    Text('Service: ${_serviceData?['name'] ?? 'N/A'}'),
                    Text('Date & Time: ${_selectedDateTime != null ? DateFormat('EEE, MMM d, yyyy - hh:mm a').format(_selectedDateTime!) : 'Not Selected'}'),
                    const SizedBox(height: 8),
                    // *** Display formatted total price ***
                    Text('Total Price: RM $displayTotal', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row( children: [ Checkbox( value: dialogTermsAccepted, onChanged: (bool? value) { setDialogState(() { dialogTermsAccepted = value ?? false; }); },), const Expanded(child: Text("By confirming, you agree to our terms of service.", style: TextStyle(fontSize: 12))),],),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton( child: const Text("Cancel"), onPressed: () => Navigator.of(context).pop(),),
                TextButton( onPressed: dialogTermsAccepted ? () { Navigator.of(context).pop(); _confirmBooking(); } : null, child: const Text("Confirm"),),
              ],
            );
          },
        );
      },
    );
  }

  // *** MODIFIED: Final booking logic with integer prices ***
  Future<void> _confirmBooking() async {
     if (_isBooking) return;
     final currentUser = _auth.currentUser;
     final currentServiceData = _serviceData;
     final selectedTime = _selectedDateTime;
     final address = _addressController.text.trim();
     final handymanId = widget.handymanId ?? currentServiceData?['handymanId'];

     if (currentUser == null || currentServiceData == null || selectedTime == null || address.isEmpty || handymanId == null) {
        ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Missing required information.'), backgroundColor: Colors.red),);
        return;
     }

     setStateIfMounted(() { _isBooking = true; });

     try {
        final newBookingRef = _dbRef.child('bookings').push();
        final bookingId = newBookingRef.key;
        if (bookingId == null) throw Exception("Failed to generate booking ID.");

        // Prepare booking data map with integer prices (sen)
        final Map<String, dynamic> bookingData = {
           'bookingId': bookingId,
           'serviceId': widget.serviceId,
           'serviceName': currentServiceData['name'] ?? 'N/A',
           'handymanId': handymanId,
           'homeownerId': currentUser.uid,
           'scheduledDateTime': selectedTime.toIso8601String(),
           'address': address,
           'description': _descriptionController.text.trim(),
           'quantity': _quantity,
           // Keep original price double for reference if needed, or remove
           'price': currentServiceData['price'] ?? 0.0,
           'priceType': currentServiceData['priceType'] ?? 'Fixed',
           // *** Save prices as integers (sen) ***
           'subtotal': _subtotal, // Already int (sen)
           'tax': _tax,          // Already int (sen)
           'total': _total,        // Already int (sen)
           // *** End of change ***
           'couponCode': _couponController.text.trim().isEmpty ? null : _couponController.text.trim(),
           'status': "Pending",
           'bookingDateTime': ServerValue.timestamp, // Use server timestamp
        };

        // Save data to Firebase
        await newBookingRef.set(bookingData);

        print("--- Booking Saved to Firebase (ID: $bookingId) ---");

        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Booking request submitted successfully!'), backgroundColor: Colors.green),);
           Navigator.pop(context);
        }

     } catch (e) {
        print("Error saving booking: $e");
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Failed to submit booking: ${e.toString()}'), backgroundColor: Colors.red),);
        }
     } finally {
        if (mounted) setStateIfMounted(() { _isBooking = false; });
     }
  }
  // *** END OF MODIFICATION ***

  // Helper to safely call setState only if the widget is still mounted
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) { setState(fn); }
  }

  @override
  Widget build(BuildContext context) {
    // ... (build method remains the same) ...
    return Scaffold( appBar: AppBar( title: const Text('Book Service'), elevation: 1,), body: _isLoading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red))) : _buildBookingForm(), bottomNavigationBar: SafeArea( child: Padding( padding: const EdgeInsets.all(16.0), child: ElevatedButton( style: ElevatedButton.styleFrom( backgroundColor: Theme.of(context).primaryColor, // Use theme's primary blue
              foregroundColor: Colors.white, // Set text color to white
              disabledBackgroundColor: Colors.grey[400],padding: const EdgeInsets.symmetric(vertical: 14), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),), onPressed: _isBooking ? null : _showConfirmationDialog, child: _isBooking ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0)) : const Text('Confirm Booking'),),),),);
  }

  // Main Form Widget
  Widget _buildBookingForm() {
    // ... (form structure remains the same) ...
     return Form( key: _formKey, child: ListView( padding: const EdgeInsets.all(16.0), children: [ _buildQuantitySection(), const SizedBox(height: 24), _buildSectionTitle('Service Address'), _buildAddressSection(), const SizedBox(height: 24), _buildSectionTitle('Booking Notes (Optional)'), _buildDescriptionSection(), const SizedBox(height: 24), _buildSectionTitle('Select Date & Time'), _buildDateTimePickerSection(), const SizedBox(height: 24), _buildSectionTitle('Coupon Code'), _buildCouponSection(), const SizedBox(height: 24), _buildSectionTitle('Price Details'), _buildPriceDetailsSection(), const SizedBox(height: 24),],),);
  }

  // --- Section Builder Widgets ---

  Widget _buildQuantitySection() { /* ... remains same ... */
    final priceType = _serviceData?['priceType'] ?? 'Fixed'; final isHourly = priceType == 'Hourly'; final serviceName = _serviceData?['name'] ?? 'Service'; final imageUrl = _serviceData?['imageUrl'] as String?; return Card( elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), child: Padding( padding: const EdgeInsets.all(12.0), child: Row( crossAxisAlignment: CrossAxisAlignment.center, children: [ Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text(serviceName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text( isHourly ? 'per hour' : 'Fixed Price', style: Theme.of(context).textTheme.bodySmall ), const SizedBox(height: 8), _buildCounter(enabled: isHourly),],),), const SizedBox(width: 16), ClipRRect( borderRadius: BorderRadius.circular(8.0), child: Container( width: 70, height: 70, color: Colors.grey[200], child: (imageUrl != null && imageUrl.isNotEmpty) ? Image.network(imageUrl, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2.0)), errorBuilder: (context, error, stack) => const Icon(Icons.error_outline, color: Colors.grey),) : const Icon(Icons.construction, size: 30, color: Colors.grey),),),],),),);
  }

  Widget _buildCounter({required bool enabled}) { /* ... remains same ... */
    return Row( mainAxisSize: MainAxisSize.min, children: [ IconButton( icon: const Icon(Icons.remove_circle_outline), iconSize: 28, color: enabled && _quantity > 1 ? Theme.of(context).colorScheme.primary : Colors.grey, onPressed: enabled && _quantity > 1 ? _decrementQuantity : null, padding: EdgeInsets.zero, constraints: const BoxConstraints(),), Padding( padding: const EdgeInsets.symmetric(horizontal: 12.0), child: Text('$_quantity', style: Theme.of(context).textTheme.titleMedium),), IconButton( icon: const Icon(Icons.add_circle_outline), iconSize: 28, color: enabled ? Theme.of(context).colorScheme.primary : Colors.grey, onPressed: enabled ? _incrementQuantity : null, padding: EdgeInsets.zero, constraints: const BoxConstraints(),),],);
  }

  Widget _buildAddressSection() { /* ... remains same ... */
    return Column( children: [ TextFormField( controller: _addressController, maxLines: 3, minLines: 1, keyboardType: TextInputType.streetAddress, decoration: const InputDecoration( hintText: 'Enter service address (e.g., Street, City, Postcode, State)', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),), validator: (value) { if (value == null || value.trim().isEmpty) { return 'Please enter the service address'; } return null; }, autovalidateMode: AutovalidateMode.onUserInteraction,), const SizedBox(height: 8), Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ TextButton.icon( icon: const Icon(Icons.home_outlined, size: 18), label: const Text('Use Home Address'), onPressed: _isProcessingLocation ? null : _useHomeAddress,), TextButton.icon( icon: _isProcessingLocation ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.0)) : const Icon(Icons.my_location, size: 18), label: const Text('Use Current Location'), onPressed: _isProcessingLocation ? null : _getCurrentLocationForAddress,),],)],);
  }

  Widget _buildDescriptionSection() { /* ... remains same ... */
    return TextFormField( controller: _descriptionController, maxLines: 4, minLines: 2, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration( hintText: 'Add any specific requirements or notes for the handyman (optional)...', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),),);
  }

  Widget _buildDateTimePickerSection() { /* ... remains same ... */
    return Card( elevation: 0, shape: RoundedRectangleBorder( side: BorderSide(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(8)), child: Padding( padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), child: Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Expanded( child: Text( _selectedDateTime == null ? 'No date & time selected *' : DateFormat('EEE, MMM d, yyyy  hh:mm a').format(_selectedDateTime!), style: TextStyle( fontSize: 16, color: _selectedDateTime == null ? Colors.grey[600] : null,),),), Row( mainAxisSize: MainAxisSize.min, children: [ IconButton( icon: const Icon(Icons.calendar_today_outlined), tooltip: 'Select Date', onPressed: _pickDate, color: Theme.of(context).primaryColor,), IconButton( icon: const Icon(Icons.access_time_outlined), tooltip: 'Select Time', onPressed: _pickTime, color: Theme.of(context).primaryColor,),],)],),),);
  }

  Widget _buildCouponSection() { /* ... remains same ... */
    return TextField( controller: _couponController, decoration: InputDecoration( hintText: 'Enter coupon code (optional)', prefixIcon: Icon(Icons.local_offer_outlined, color: Colors.grey[600]), suffixIcon: TextButton( onPressed: () { print('Apply Coupon: ${_couponController.text}'); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coupon feature coming soon!'))); }, child: const Text('Apply'),), border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0), isDense: true,),);
  }

  // *** MODIFIED: Price Details Section using integer sen values ***
  Widget _buildPriceDetailsSection() {
    return Card(
       elevation: 0,
       color: Colors.blue[50]?.withOpacity(0.5),
       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
       child: Padding(
         padding: const EdgeInsets.all(16.0),
         child: Column(
           children: [
             // Pass integer sen values to the helper
             _buildPriceRow('Subtotal', _subtotal),
             _buildPriceRow('SST (8%)', _tax),
             const Divider(height: 16, thickness: 1),
             _buildPriceRow('Total Amount', _total, isTotal: true),
           ],
         ),
       ),
    );
  }
  // *** END OF MODIFICATION ***

  // *** MODIFIED: Price Row helper accepts int (sen), displays RM ***
  Widget _buildPriceRow(String label, int amountInSen, {bool isTotal = false}) {
    // Convert sen back to RM for display
    final double amountRM = amountInSen / 100.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isTotal ? 16 : 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text(
             // Format the RM value to 2 decimal places
             'RM ${amountRM.toStringAsFixed(2)}',
             style: TextStyle(fontSize: isTotal ? 16 : 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)
          ),
        ],
      ),
    );
  }
  // *** END OF MODIFICATION ***

  // Helper for section titles
  Widget _buildSectionTitle(String title) { /* ... remains same ... */
     return Padding( padding: const EdgeInsets.only(bottom: 8.0), child: Text( title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),),);
  }

}
