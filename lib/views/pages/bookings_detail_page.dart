import 'dart:async';
import 'package:fixit_app_a186687/models/bookings_services.dart';
import 'package:fixit_app_a186687/views/pages/chat_page.dart';
import 'package:fixit_app_a186687/views/pages/payment_page.dart';
import 'package:fixit_app_a186687/views/pages/rate_services_page.dart';
import 'package:fixit_app_a186687/views/pages/receipt_page.dart';
import 'package:fixit_app_a186687/views/pages/report_issue_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class BookingDetailPage extends StatefulWidget {
  final String bookingId;
  final String userRole; // 'Homeowner' or 'Handyman'

  const BookingDetailPage({
    required this.bookingId,
    required this.userRole,
    super.key,
  });

  @override
  State<BookingDetailPage> createState() => _BookingDetailPageState();
}

class _BookingDetailPageState extends State<BookingDetailPage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // State variables
  Booking? _booking;
  Map<String, dynamic>? _serviceDetails;
  Map<String, dynamic>? _otherPartyDetails;

  bool _isLoading = true;
  String? _error;
  bool _isProcessingAction = false;

  bool _reviewExists = false;
  StreamSubscription? _reviewStreamSubscription;


  final TextEditingController _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBookingDetails();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _reviewStreamSubscription?.cancel();
    super.dispose();
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
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

  // --- MODIFIED: This function now correctly fetches the ACTOR's name for notifications ---
  Future<void> _updateBookingStatus(String newStatus, [Map<String, dynamic>? additionalData]) async {
    if (_isProcessingAction) return;
    setStateIfMounted(() { _isProcessingAction = true; });

    try {
      Map<String, dynamic> updates = {'status': newStatus, 'updatedAt': ServerValue.timestamp};
      if (additionalData != null) {
        updates.addAll(additionalData);
      }
      await _dbRef.child('bookings').child(widget.bookingId).update(updates);

      // --- Notification Logic ---
      if (_booking != null) {
        String? notificationTitle;
        String? notificationBody;
        String? notificationType;
        String? targetUserId;
        
        // ** FIX: Get the name of the person performing the action (the "actor") **
        // This is the most reliable way, as it fetches the current name from the database.
        final actorSnapshot = await _dbRef.child('users/${_auth.currentUser!.uid}/name').get();
        final actorName = actorSnapshot.value as String? ?? "Someone";

        // Determine who to notify based on who is taking the action
        if (widget.userRole == 'Handyman') {
          // Handyman acts, notify Homeowner
          targetUserId = _booking!.homeownerId;
          switch(newStatus) {
            case 'Accepted':
              notificationTitle = 'Booking Accepted!';
              notificationBody = '$actorName has confirmed your booking for "${_booking!.serviceName}".';
              notificationType = 'booking_accepted';
              break;
            case 'En Route':
              notificationTitle = 'Handyman is On The Way!';
              notificationBody = '$actorName is now en route for your booking: "${_booking!.serviceName}".';
              notificationType = 'booking_enroute';
              break;
            case 'Declined':
              notificationTitle = 'Booking Declined';
              notificationBody = 'Unfortunately, $actorName has declined your booking for "${_booking!.serviceName}".';
              notificationType = 'booking_declined';
              break;
          }
        } 
        else if (widget.userRole == 'Homeowner') {
          // Homeowner acts, notify Handyman
          targetUserId = _booking!.handymanId;
          switch(newStatus) {
            case 'Cancelled':
              notificationTitle = 'Booking Cancelled by Customer';
              notificationBody = '$actorName has cancelled the booking for "${_booking!.serviceName}".';
              notificationType = 'booking_cancelled';
              break;
            case 'Ongoing':
              notificationTitle = 'Service Has Started';
              notificationBody = '$actorName has marked the service for "${_booking!.serviceName}" as started.';
              notificationType = 'booking_started';
              break;
          }
        }

        // Send the notification if all data is available
        if (targetUserId != null && notificationTitle != null && notificationBody != null && notificationType != null) {
          await _createNotification(
            userId: targetUserId,
            title: notificationTitle,
            body: notificationBody,
            type: notificationType,
            bookingId: widget.bookingId,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking status updated to $newStatus.'), backgroundColor: Colors.green));
        _loadBookingDetails();
      }
    } catch (e) {
      print("Error updating booking status: $e");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update booking: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setStateIfMounted(() { _isProcessingAction = false; });
    }
  }

  Future<void> _loadBookingDetails() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });

    try {
      final bookingSnapshot = await _dbRef.child('bookings').child(widget.bookingId).get();
      if (!mounted || !bookingSnapshot.exists) throw Exception("Booking not found.");

      _booking = Booking.fromSnapshot(bookingSnapshot);
      if (!mounted || _booking == null) return;

      // Listen for review status if the booking is completed by a homeowner
      if (widget.userRole == 'Homeowner' && _booking!.status == 'Completed') {
        _listenForReview();
      }

      // --- MODIFIED: Fetch all related data concurrently ---
      final results = await Future.wait([
        // Fetch service details ONLY if it's a standard booking
        if (_booking!.serviceId != null)
          _dbRef.child('services').child(_booking!.serviceId!).get(),
        // Always fetch homeowner details
        _dbRef.child('users').child(_booking!.homeownerId).get(),
        // Always fetch handyman details
        _dbRef.child('users').child(_booking!.handymanId).get(),
      ]);

      if (!mounted) return;

      int resultIndex = 0;
      if (_booking!.serviceId != null) {
        final serviceSnap = results[resultIndex++];
        if (serviceSnap.exists) {
          _serviceDetails = Map<String, dynamic>.from(serviceSnap.value as Map);
        }
      }
      
      final homeownerSnap = results[resultIndex++];
      final handymanSnap = results[resultIndex++];

      setState(() {
        _otherPartyDetails = widget.userRole == 'Homeowner'
            ? (handymanSnap.exists ? Map<String, dynamic>.from(handymanSnap.value as Map) : null)
            : (homeownerSnap.exists ? Map<String, dynamic>.from(homeownerSnap.value as Map) : null);
        _isLoading = false;
      });

    } catch (e) {
      print("Error loading booking details: $e");
      if (mounted) setState(() { _isLoading = false; _error = "Failed to load details."; });
    }
  }


  void _listenForReview() { _reviewStreamSubscription?.cancel(); final query = _dbRef.child('reviews').orderByChild('bookingId').equalTo(widget.bookingId); _reviewStreamSubscription = query.onValue.listen((event) { if (mounted) { setStateIfMounted(() { _reviewExists = event.snapshot.exists; }); print("Real-time review check updated. Review exists: ${event.snapshot.exists}"); } }, onError: (error) { print("Error in review stream subscription: $error"); if (mounted) { setStateIfMounted(() { _reviewExists = false; }); } }); }
  Future<void> _makePhoneCall(String? phoneNumber) async { if (phoneNumber == null || phoneNumber.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number not available.'))); return; } final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber); try { if (await canLaunchUrl(launchUri)) { await launchUrl(launchUri); } else { throw 'Could not launch $launchUri'; } } catch(e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not launch phone dialer: $e'))); print('Could not launch $launchUri: $e'); } }
  Future<void> _acceptBooking() async { await _updateBookingStatus('Accepted'); }
  Future<void> _declineBooking(String reason) async { await _updateBookingStatus('Declined', {'declineReason': reason}); if (mounted) Navigator.pop(context); }
  Future<void> _cancelBookingByHomeowner(String reason) async { await _updateBookingStatus('Cancelled', {'cancellationReason': reason, 'cancelledBy': 'Homeowner'}); if (mounted) Navigator.pop(context); }
  Future<void> _cancelBookingByHandyman(String reason) async { await _updateBookingStatus('Cancelled', {'cancellationReason': reason, 'cancelledBy': 'Handyman'}); if (mounted) Navigator.pop(context); }
  Future<void> _startDriving() async { await _updateBookingStatus('En Route'); }
  Future<void> _startService() async { await _updateBookingStatus('Ongoing'); }
  void _showReasonDialog({ required String title, required String hintText, required String submitButtonText, required Color submitButtonColor, required Function(String reason) onSubmit, required String cancelText}) { _reasonController.clear(); final formKey = GlobalKey<FormState>(); showDialog( context: context, barrierDismissible: true, builder: (BuildContext context) { return AlertDialog( title: Text(title), titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0), content: Form( key: formKey, child: TextFormField( controller: _reasonController, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration( hintText: hintText, border: const OutlineInputBorder(),), validator: (value) => (value == null || value.trim().isEmpty) ? 'Reason cannot be empty.' : null, ),), buttonPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0), actionsAlignment: MainAxisAlignment.end, contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12), actions: <Widget>[ TextButton( child: Text(cancelText), onPressed: () => Navigator.of(context).pop(),), ElevatedButton( style: ElevatedButton.styleFrom( backgroundColor: submitButtonColor, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),), onPressed: () { if (formKey.currentState!.validate()) { Navigator.of(context).pop(); onSubmit(_reasonController.text.trim()); } }, child: Text(submitButtonText),),],);},); }
  void _showDeclineDialog() { _showReasonDialog( title: 'Reason for Declining', hintText: 'Please provide a reason (required)', submitButtonText: 'Submit Decline', submitButtonColor: Colors.red, onSubmit: _declineBooking, cancelText: 'Cancel'); }
  void _showCancelDialogByHomeowner() { _showReasonDialog( title: 'Reason for Cancellation', hintText: 'Please provide a reason (required)', submitButtonText: 'Confirm Cancellation', submitButtonColor: Colors.orange, onSubmit: _cancelBookingByHomeowner, cancelText: 'Keep Booking'); }
  void _showCancelDialogByHandyman() { _showReasonDialog( title: 'Reason for Cancellation', hintText: 'Please provide a reason (required)', submitButtonText: 'Confirm Cancellation', submitButtonColor: Colors.purple, onSubmit: _cancelBookingByHandyman, cancelText: 'Keep Booking'); }
  void _showStartServiceConfirmation() { showDialog( context: context, builder: (context) => AlertDialog( title: const Text('Start Service?'), content: const Text('Are you sure you want to mark the service as started?'), actions: [ TextButton(onPressed: () => Navigator.pop(context), child: const Text('No')), ElevatedButton(onPressed: (){ Navigator.pop(context); _startService(); }, child: const Text('Yes, Start')),],)); }
  @override
  Widget build(BuildContext context) { String appBarTitle = 'Booking Details'; if (!_isLoading && _booking != null) { appBarTitle = _booking!.serviceName; } else if (_isLoading) { appBarTitle = 'Loading...'; } return Scaffold( backgroundColor: Colors.blue[50], appBar: AppBar( title: Text(appBarTitle), elevation: 1,), body: _buildContent(), bottomNavigationBar: SafeArea( child: _buildBottomActions() ?? const SizedBox.shrink(),)); }
  Widget _buildContent() { if (_isLoading) { return const Center(child: CircularProgressIndicator()); } if (_error != null) { return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_error!, style: const TextStyle(color: Colors.red)))); } if (_booking == null) { return const Center(child: Text('Booking details not found.')); } final otherPartyData = _otherPartyDetails; final otherPartyRoleLabel = widget.userRole == 'Homeowner' ? 'Handyman' : 'Customer'; return SingleChildScrollView( padding: const EdgeInsets.only(bottom: 120), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildCardWrapper( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildServiceImage(), const SizedBox(height: 16), _buildBookingSummarySection(), _buildReasonSection(), const Divider(height: 24, thickness: 0.5), _buildBookingDescriptionSection(), const SizedBox(height: 16), _buildPriceDetailsSection(),],)), _buildCardWrapper(child: _buildPartyInfoContent(otherPartyData, otherPartyRoleLabel)), _buildCardWrapper(child: _buildReviewsContent()),],),); }
  Widget _buildCardWrapper({required Widget child}) { return Card( margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), elevation: 0, shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300, width: 0.5)), color: Theme.of(context).cardColor, child: Padding( padding: const EdgeInsets.all(16.0), child: child,),); }
  Widget _buildServiceImage() { final imageUrl = _serviceDetails?['imageUrl'] as String?; return ClipRRect( borderRadius: BorderRadius.circular(8.0), child: Container( height: 180, width: double.infinity, color: Colors.grey[200], child: (imageUrl != null && imageUrl.isNotEmpty) ? Image.network( imageUrl, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 40)),) : const Center(child: Icon(Icons.construction, color: Colors.grey, size: 40)),),); }
  Widget _buildBookingSummarySection() { return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text( _booking!.serviceName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),), const SizedBox(height: 12), _buildInfoRow(Icons.calendar_today_outlined, _booking!.formattedScheduledDateTime, textStyle: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 6), Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Flexible( child: _buildInfoRow(Icons.vpn_key_outlined, _booking!.bookingId, textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)) ), Chip( label: Text(_booking!.status, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)), backgroundColor: _getStatusColor(_booking!.status), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), visualDensity: VisualDensity.compact, side: BorderSide.none,),],)],); }
  Widget _buildReasonSection() { String reasonLabel = ''; String? reasonText; Color reasonColor = Colors.grey.shade700; if (_booking!.status == 'Declined') { reasonLabel = 'Reason for Decline'; reasonText = _booking!.declineReason; reasonColor = Colors.red.shade800; } else if (_booking!.status == 'Cancelled' || _booking!.status == 'Cancelled_Handyman') { reasonLabel = 'Reason for Cancellation'; reasonText = _booking!.cancellationReason; reasonColor = Colors.grey.shade800; } if (reasonText == null || reasonText.isEmpty) { if (_booking!.status == 'Declined' || _booking!.status.startsWith('Cancelled')) { return Padding( padding: const EdgeInsets.only(top: 10.0, bottom: 4.0), child: _buildInfoRow(Icons.info_outline, 'No reason provided.', iconColor: reasonColor),); } return const SizedBox.shrink(); } return Padding( padding: const EdgeInsets.only(top: 10.0, bottom: 4.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text(reasonLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: reasonColor)), const SizedBox(height: 4), Text(reasonText, style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black87)),],),); }
  Widget _buildBookingDescriptionSection() { final description = _booking?.description; return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Booking Notes'), const SizedBox(height: 8), Text( (description != null && description.isNotEmpty) ? description : 'No additional notes provided.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4)),],); }
  Widget _buildPriceDetailsSection() { return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Price Breakdown'), const SizedBox(height: 8), _buildPriceRow('Subtotal', _booking!.subtotal), _buildPriceRow('SST (8%)', _booking!.tax), const Divider(height: 16, thickness: 0.5), _buildPriceRow('Total Amount', _booking!.total, isTotal: true),],); }
  Widget _buildPartyInfoContent(Map<String, dynamic>? partyData, String roleLabel) { final name = partyData?['name'] ?? '$roleLabel details unavailable'; final imageUrl = partyData?['profileImageUrl'] as String?; final email = partyData?['email'] as String?; final address = partyData?['address'] as String?; final phone = partyData?['phoneNumber'] as String?; return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('$roleLabel Details'), const SizedBox(height: 12), ListTile( contentPadding: EdgeInsets.zero, leading: CircleAvatar( radius: 28, backgroundColor: Colors.grey[200], backgroundImage: (imageUrl != null && imageUrl.isNotEmpty) ? NetworkImage(imageUrl) : null, child: (imageUrl == null || imageUrl.isEmpty) ? const Icon(Icons.person, color: Colors.grey) : null,), title: Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), subtitle: Text(email ?? 'No email available', style: Theme.of(context).textTheme.bodySmall),), if (address != null && address.isNotEmpty) ...[ const SizedBox(height: 8), _buildInfoRow(Icons.location_on_outlined, address),], const SizedBox(height: 16), Row( mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [ OutlinedButton.icon( icon: const Icon(Icons.call_outlined, size: 18), label: const Text('Call'), onPressed: (phone != null && phone.isNotEmpty) ? () => _makePhoneCall(phone) : null, style: OutlinedButton.styleFrom( foregroundColor: (phone != null && phone.isNotEmpty) ? Theme.of(context).primaryColor : Colors.grey, side: BorderSide(color: (phone != null && phone.isNotEmpty) ? Theme.of(context).primaryColor : Colors.grey),),), OutlinedButton.icon( icon: const Icon(Icons.chat_bubble_outline, size: 18), label: const Text('Chat'), onPressed: () { final currentUserId = _auth.currentUser?.uid; final otherUserId = widget.userRole == 'Homeowner' ? _booking?.handymanId : _booking?.homeownerId; final otherPartyNameFromData = partyData?['name'] as String?; final otherPartyImageUrlFromData = partyData?['profileImageUrl'] as String?; if (currentUserId != null && otherUserId != null && otherUserId.isNotEmpty && otherPartyNameFromData != null) { List<String> ids = [currentUserId, otherUserId]; ids.sort(); String chatRoomId = ids.join('_'); print('Navigating to chat room: $chatRoomId'); Navigator.push( context, MaterialPageRoute( builder: (_) => ChatPage( chatRoomId: chatRoomId, otherUserId: otherUserId, otherUserName: otherPartyNameFromData, otherUserImageUrl: otherPartyImageUrlFromData, ),),); } else { print('Cannot initiate chat. User details missing. Current: $currentUserId, Other: $otherUserId, Name: $otherPartyNameFromData'); ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Cannot initiate chat. User details missing.')),); } },), ],), ],); }
  Widget _buildReviewsContent() { return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Reviews'), const SizedBox(height: 8), const Center(child: Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Text('Reviews for this booking coming soon!', style: TextStyle(color: Colors.grey)),)),],); }
  Widget _buildInfoRow(IconData icon, String text, {TextStyle? textStyle, Color? iconColor}) { return Padding( padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row( crossAxisAlignment: CrossAxisAlignment.start, children: [ Icon(icon, size: 18, color: iconColor ?? Colors.grey[700]), const SizedBox(width: 10), Expanded( child: Text( text, style: textStyle ?? Theme.of(context).textTheme.bodyMedium,)),],),); }
  Widget _buildSectionTitle(String title) { return Text( title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),); }
  Color _getStatusColor(String status) { switch (status) { case "Pending": return Colors.orange.shade700; case "Accepted": return Colors.blue.shade700; case "En Route": return Colors.cyan.shade600; case "Ongoing": return Colors.lightBlue.shade600; case "Completed": return Colors.green.shade700; case "Declined": return Colors.red.shade700; case "Cancelled": return Colors.grey.shade700; default: return Colors.grey; } }
  Widget _buildPriceRow(String label, int amountInSen, {bool isTotal = false}) { final double amountRM = amountInSen / 100.0; return Padding( padding: const EdgeInsets.symmetric(vertical: 2.0), child: Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text(label, style: TextStyle(fontSize: isTotal ? 15 : 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)), Text( 'RM ${amountRM.toStringAsFixed(2)}', style: TextStyle(fontSize: isTotal ? 15 : 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal))],),); }
  
  // This is the original, correct _buildBottomActions method
  Widget? _buildBottomActions() {
    if (_isLoading || _booking == null) return null;
    final ButtonStyle elevatedButtonStyle = ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),);
    final ButtonStyle outlinedButtonStyle = OutlinedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),);
    
    switch (_booking!.status) {
      case 'Pending':
      if (widget.userRole == 'Handyman') { return Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Row( children: [ Expanded( child: OutlinedButton( onPressed: _isProcessingAction ? null : _showDeclineDialog, style: outlinedButtonStyle.copyWith( foregroundColor: MaterialStateProperty.all(Colors.red), side: MaterialStateProperty.all(const BorderSide(color: Colors.red)),), child: const Text('Decline'),),), const SizedBox(width: 8), Expanded( child: ElevatedButton( onPressed: _isProcessingAction ? null : _acceptBooking, style: elevatedButtonStyle, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Accept'),),),],),); } else { return Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisSize: MainAxisSize.min, children: [ Container( padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration( color: Colors.orange.shade100, borderRadius: BorderRadius.circular(20),), child: Text('Waiting for Handyman Approval', style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),), const SizedBox(height: 12), SizedBox( width: double.infinity, child: ElevatedButton( style: elevatedButtonStyle.copyWith( backgroundColor: MaterialStateProperty.all(Colors.red[700]), foregroundColor: MaterialStateProperty.all(Colors.white)), onPressed: _isProcessingAction ? null : _showCancelDialogByHomeowner, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Cancel Booking'),),),],),); }
      case 'Accepted':
      if (widget.userRole == 'Handyman') { return Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Row( children: [ Expanded( child: OutlinedButton( onPressed: _isProcessingAction ? null : _showCancelDialogByHandyman, style: outlinedButtonStyle.copyWith( foregroundColor: MaterialStateProperty.all(Colors.purple), side: MaterialStateProperty.all(const BorderSide(color: Colors.purple)),), child: const Text('Cancel'),),), const SizedBox(width: 8), Expanded( child: ElevatedButton( onPressed: _isProcessingAction ? null : _startDriving, style: elevatedButtonStyle, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Start Driving'),),),],),); } else { return Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisSize: MainAxisSize.min, children: [ Container( padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration( color: Colors.blue.shade100, borderRadius: BorderRadius.circular(20),), child: Text('Booking Accepted! Waiting for Handyman.', style: TextStyle(color: Colors.blue.shade800, fontSize: 12)),), const SizedBox(height: 12), SizedBox( width: double.infinity, child: ElevatedButton( style: elevatedButtonStyle.copyWith( backgroundColor: MaterialStateProperty.all(Colors.red[700]), foregroundColor: MaterialStateProperty.all(Colors.white)), onPressed: _isProcessingAction ? null : _showCancelDialogByHomeowner, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Cancel Booking'),),),],),); }
      case 'En Route':
      if (widget.userRole == 'Homeowner') { return Padding( padding: const EdgeInsets.all(16.0), child: SizedBox( width: double.infinity, child: ElevatedButton( style: elevatedButtonStyle.copyWith(backgroundColor: MaterialStateProperty.all(Colors.green[700])), onPressed: _isProcessingAction ? null : _showStartServiceConfirmation, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Start Service'),),),); } else { return Container( padding: const EdgeInsets.all(16.0), width: double.infinity, child: Text('On the way! Waiting for Homeowner to start service.', textAlign: TextAlign.center, style: TextStyle(color: Colors.cyan[800], fontWeight: FontWeight.bold)),); }
      case 'Ongoing':
      if (widget.userRole == 'Homeowner') { return Padding( padding: const EdgeInsets.all(16.0), child: SizedBox( width: double.infinity, child: ElevatedButton( style: elevatedButtonStyle.copyWith(backgroundColor: MaterialStateProperty.all(Colors.teal)), onPressed: _isProcessingAction ? null : () { Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentPage(bookingId: _booking!.bookingId))); }, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Pay Now'),),),); } else { return Container( padding: const EdgeInsets.all(16.0), width: double.infinity, child: Text('Service in progress. Waiting for payment.', textAlign: TextAlign.center, style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold)),); }
      case 'Completed':
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.userRole == 'Homeowner' && !_reviewExists)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Rate Service'),
                    style: elevatedButtonStyle.copyWith(backgroundColor: MaterialStateProperty.all(Colors.amber[700])),
                    onPressed: _isProcessingAction ? null : () {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => RateServicesPage(
      bookingId: _booking!.bookingId,
      handymanId: _booking!.handymanId,
      // Pass the serviceName directly from the booking record.
      // This works for both standard and custom jobs.
      serviceName: _booking!.serviceName,
      // Pass the serviceId if it exists. It will be null for custom jobs.
      serviceId: _booking!.serviceId,
    )),
  ).then((value) {
    // This ensures the page refreshes if a review was submitted.
    if (value == true && mounted) {
      _loadBookingDetails();
    }
  });
},
                  ),
                ),
              if (widget.userRole == 'Homeowner' && _reviewExists)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'You have already reviewed this service.',
                    style: TextStyle(color: Colors.green[800], fontStyle: FontStyle.italic),
                  ),
                ),
              if (widget.userRole == 'Homeowner') const SizedBox(height: 12),
              
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Report Issue'),
                      style: outlinedButtonStyle,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ReportIssuePage(
                            bookingId: widget.bookingId,
                            userRole: widget.userRole,
                          )),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Print Receipt'),
                      style: outlinedButtonStyle,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ReceiptPage(
                            bookingId: widget.bookingId,
                          )),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      default:
        return null;
    }
  }
}
