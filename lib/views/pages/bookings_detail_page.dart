import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart'; // For making phone calls
import 'package:fixit_app_a186687/views/pages/payment_page.dart';
import 'package:fixit_app_a186687/views/pages/rate_services_page.dart';
// *** ADD Import for ChatPage ***
// TODO: Create this page and adjust the import path if needed
import 'package:fixit_app_a186687/views/pages/chat_page.dart';

import '../../models/bookings_services.dart';

// TODO: Import UserProfile and HandymanService models if created
// import '../../models/user_profile.dart';
// import '../../models/handyman_service.dart';


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
  bool _isExpanded = false;
  bool _isProcessingAction = false;

  final TextEditingController _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBookingDetails();
  }

   @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  // Load all necessary details
  Future<void> _loadBookingDetails({int retries = 1}) async {
    // ... (Fetching logic remains the same) ...
    if (!mounted) return; if (_booking == null) { setState(() { _isLoading = true; _error = null; }); } for (int i = 0; i < retries; i++) { try { final bookingSnapshot = await _dbRef.child('bookings').child(widget.bookingId).get(); if (!mounted) return; if (!bookingSnapshot.exists || bookingSnapshot.value == null) throw Exception('Booking not found or access denied.'); _booking = Booking.fromSnapshot(bookingSnapshot); if (!mounted || _booking == null) return; List<Future> futures = []; if (_booking!.serviceId.isNotEmpty) { futures.add(_dbRef.child('services').child(_booking!.serviceId).get().then((snap) { if (mounted && snap.exists && snap.value != null) { _serviceDetails = Map<String, dynamic>.from(snap.value as Map); } }).catchError((e) => print("Error fetching service details: $e"))); } final otherPartyId = widget.userRole == 'Homeowner' ? _booking!.handymanId : _booking!.homeownerId; if (otherPartyId.isNotEmpty) { futures.add(_dbRef.child('users').child(otherPartyId).get().then((snap) { if (mounted && snap.exists && snap.value != null) { _otherPartyDetails = Map<String, dynamic>.from(snap.value as Map); } }).catchError((e) => print("Error fetching other party details: $e"))); } if (futures.isNotEmpty) { await Future.wait(futures); } if (mounted) setState(() { _isLoading = false; _error = null; }); return; } catch (e) { print("Error loading booking details (attempt ${i+1}): $e"); if (i == retries - 1 && mounted) { setState(() { _isLoading = false; _error = "Failed to load details."; }); } if (retries > 1) await Future.delayed(const Duration(seconds: 1)); } }
  }


  // Helper to launch phone dialer
  Future<void> _makePhoneCall(String? phoneNumber) async {
    // ... (Phone call logic remains the same) ...
    if (phoneNumber == null || phoneNumber.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number not available.'))); return; } final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber); try { if (await canLaunchUrl(launchUri)) { await launchUrl(launchUri); } else { throw 'Could not launch $launchUri'; } } catch(e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not launch phone dialer: $e'))); print('Could not launch $launchUri: $e'); }
  }

  // --- Action Handlers ---
  Future<void> _updateBookingStatus(String newStatus, [Map<String, dynamic>? additionalData]) async {
     // ... (Update status logic remains the same) ...
     if (_isProcessingAction) return; setState(() { _isProcessingAction = true; }); try { Map<String, dynamic> updates = {'status': newStatus, 'updatedAt': ServerValue.timestamp}; if (additionalData != null) { updates.addAll(additionalData); } await _dbRef.child('bookings').child(widget.bookingId).update(updates); if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking status updated to $newStatus.'), backgroundColor: Colors.green)); _loadBookingDetails(); } } catch (e) { print("Error updating booking status to $newStatus: $e"); if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update booking: $e'), backgroundColor: Colors.red)); } finally { if (mounted) setState(() { _isProcessingAction = false; }); }
  }
  Future<void> _acceptBooking() async { await _updateBookingStatus('Accepted'); }
  Future<void> _declineBooking(String reason) async { await _updateBookingStatus('Declined', {'declineReason': reason}); if (mounted) Navigator.pop(context); }
  Future<void> _cancelBookingByHomeowner(String reason) async { await _updateBookingStatus('Cancelled', {'cancellationReason': reason, 'cancelledBy': 'Homeowner'}); if (mounted) Navigator.pop(context); }
  Future<void> _cancelBookingByHandyman(String reason) async { await _updateBookingStatus('Cancelled', {'cancellationReason': reason, 'cancelledBy': 'Handyman'}); if (mounted) Navigator.pop(context); }
  Future<void> _startDriving() async { await _updateBookingStatus('En Route'); }
  Future<void> _startService() async { await _updateBookingStatus('Ongoing'); }

  // --- Dialogs ---
  // Generic Reason Dialog
  void _showReasonDialog({ required String title, required String hintText, required String submitButtonText, required Color submitButtonColor, required Function(String reason) onSubmit, required String cancelText}) {
     // ... (Dialog logic remains the same) ...
     _reasonController.clear(); final formKey = GlobalKey<FormState>(); showDialog( context: context, barrierDismissible: true, builder: (BuildContext context) { return AlertDialog( title: Text(title), titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0), content: Form( key: formKey, child: TextFormField( controller: _reasonController, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration( hintText: hintText, border: const OutlineInputBorder(),), validator: (value) => (value == null || value.trim().isEmpty) ? 'Reason cannot be empty.' : null, ),), buttonPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0), actionsAlignment: MainAxisAlignment.end, contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 12), actions: <Widget>[ TextButton( child: Text(cancelText), onPressed: () => Navigator.of(context).pop(),), ElevatedButton( style: ElevatedButton.styleFrom( backgroundColor: submitButtonColor, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),), onPressed: () { if (formKey.currentState!.validate()) { Navigator.of(context).pop(); onSubmit(_reasonController.text.trim()); } }, child: Text(submitButtonText),),],);},);
  }
  // Specific dialog callers using the generic one
  void _showDeclineDialog() { _showReasonDialog( title: 'Reason for Declining', hintText: 'Please provide a reason (required)', submitButtonText: 'Submit Decline', submitButtonColor: Colors.red, onSubmit: _declineBooking, cancelText: 'Cancel'); }
  void _showCancelDialogByHomeowner() { _showReasonDialog( title: 'Reason for Cancellation', hintText: 'Please provide a reason (required)', submitButtonText: 'Confirm Cancellation', submitButtonColor: Colors.orange, onSubmit: _cancelBookingByHomeowner, cancelText: 'Keep Booking'); }
  void _showCancelDialogByHandyman() { _showReasonDialog( title: 'Reason for Cancellation', hintText: 'Please provide a reason (required)', submitButtonText: 'Confirm Cancellation', submitButtonColor: Colors.purple, onSubmit: _cancelBookingByHandyman, cancelText: 'Keep Booking'); }
  // Simple confirmation dialog for starting service
  void _showStartServiceConfirmation() { showDialog( context: context, builder: (context) => AlertDialog( title: const Text('Start Service?'), content: const Text('Are you sure you want to mark the service as started?'), actions: [ TextButton(onPressed: () => Navigator.pop(context), child: const Text('No')), ElevatedButton(onPressed: (){ Navigator.pop(context); _startService(); }, child: const Text('Yes, Start')),],)); }


  @override
  Widget build(BuildContext context) {
    // ... (build method remains the same) ...
    String appBarTitle = 'Booking Details'; if (!_isLoading && _booking != null) { appBarTitle = _booking!.serviceName; } else if (_isLoading) { appBarTitle = 'Loading...'; }
    return Scaffold( backgroundColor: Colors.blue[50], appBar: AppBar( title: Text(appBarTitle), elevation: 1,), body: _buildContent(), bottomNavigationBar: SafeArea( child: _buildBottomActions() ?? const SizedBox.shrink(),));
  }

  Widget _buildContent() {
    // ... (content build logic remains the same) ...
    if (_isLoading) { return const Center(child: CircularProgressIndicator()); } if (_error != null) { return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_error!, style: const TextStyle(color: Colors.red)))); } if (_booking == null) { return const Center(child: Text('Booking details not found.')); }
    final otherPartyData = _otherPartyDetails; final otherPartyRoleLabel = widget.userRole == 'Homeowner' ? 'Handyman' : 'Customer';
    return SingleChildScrollView( padding: const EdgeInsets.only(bottom: 120), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildCardWrapper( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildServiceImage(), const SizedBox(height: 16), _buildBookingSummarySection(), _buildReasonSection(), const Divider(height: 24, thickness: 0.5), _buildBookingDescriptionSection(), const SizedBox(height: 16), _buildPriceDetailsSection(),],)), _buildCardWrapper(child: _buildPartyInfoContent(otherPartyData, otherPartyRoleLabel)), _buildCardWrapper(child: _buildReviewsContent()),],),);
  }

  // --- Helper Widgets ---

  Widget _buildCardWrapper({required Widget child}) { /* ... remains same ... */
     return Card( margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), elevation: 0, shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade300, width: 0.5)), color: Theme.of(context).cardColor, child: Padding( padding: const EdgeInsets.all(16.0), child: child,),);
  }

  Widget _buildServiceImage() { /* ... remains same ... */
    final imageUrl = _serviceDetails?['imageUrl'] as String?; return ClipRRect( borderRadius: BorderRadius.circular(8.0), child: Container( height: 180, width: double.infinity, color: Colors.grey[200], child: (imageUrl != null && imageUrl.isNotEmpty) ? Image.network( imageUrl, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 40)),) : const Center(child: Icon(Icons.construction, color: Colors.grey, size: 40)),),);
  }

  Widget _buildBookingSummarySection() { /* ... remains same ... */
     return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text( _booking!.serviceName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),), const SizedBox(height: 12), _buildInfoRow(Icons.calendar_today_outlined, _booking!.formattedScheduledDateTime, textStyle: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 6), Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Flexible( child: _buildInfoRow(Icons.vpn_key_outlined, _booking!.bookingId, textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)) ), Chip( label: Text(_booking!.status, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)), backgroundColor: _getStatusColor(_booking!.status), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), visualDensity: VisualDensity.compact, side: BorderSide.none,),],)],);
  }

  Widget _buildReasonSection() { /* ... remains same ... */
     String reasonLabel = ''; String? reasonText; Color reasonColor = Colors.grey.shade700; if (_booking!.status == 'Declined') { reasonLabel = 'Reason for Decline'; reasonText = _booking!.declineReason; reasonColor = Colors.red.shade800; } else if (_booking!.status == 'Cancelled' || _booking!.status == 'Cancelled_Handyman') { reasonLabel = 'Reason for Cancellation'; reasonText = _booking!.cancellationReason; reasonColor = Colors.grey.shade800; } if (reasonText == null || reasonText.isEmpty) { if (_booking!.status == 'Declined' || _booking!.status.startsWith('Cancelled')) { return Padding( padding: const EdgeInsets.only(top: 10.0, bottom: 4.0), child: _buildInfoRow(Icons.info_outline, 'No reason provided.', iconColor: reasonColor),); } return const SizedBox.shrink(); } return Padding( padding: const EdgeInsets.only(top: 10.0, bottom: 4.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text(reasonLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: reasonColor)), const SizedBox(height: 4), Text(reasonText, style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.black87)),],),);
  }

  Widget _buildBookingDescriptionSection() { /* ... remains same ... */
    final description = _booking?.description; return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Booking Notes'), const SizedBox(height: 8), Text( (description != null && description.isNotEmpty) ? description : 'No additional notes provided.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4)),],);
  }

  Widget _buildPriceDetailsSection() { /* ... remains same ... */
    return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Price Breakdown'), const SizedBox(height: 8), _buildPriceRow('Subtotal', _booking!.subtotal), _buildPriceRow('SST (8%)', _booking!.tax), const Divider(height: 16, thickness: 0.5), _buildPriceRow('Total Amount', _booking!.total, isTotal: true),],);
  }

  // *** MODIFIED: _buildPartyInfoContent to implement Chat button navigation ***
  Widget _buildPartyInfoContent(Map<String, dynamic>? partyData, String roleLabel) {
     final name = partyData?['name'] ?? '$roleLabel details unavailable';
     final imageUrl = partyData?['profileImageUrl'] as String?;
     final email = partyData?['email'] as String?;
     final address = partyData?['address'] as String?;
     final phone = partyData?['phoneNumber'] as String?;

     return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
           _buildSectionTitle('$roleLabel Details'),
           const SizedBox(height: 12),
           ListTile( contentPadding: EdgeInsets.zero, leading: CircleAvatar( radius: 28, backgroundColor: Colors.grey[200], backgroundImage: (imageUrl != null && imageUrl.isNotEmpty) ? NetworkImage(imageUrl) : null, child: (imageUrl == null || imageUrl.isEmpty) ? const Icon(Icons.person, color: Colors.grey) : null,), title: Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), subtitle: Text(email ?? 'No email available', style: Theme.of(context).textTheme.bodySmall),),
           if (address != null && address.isNotEmpty) ...[ const SizedBox(height: 8), _buildInfoRow(Icons.location_on_outlined, address),],
           const SizedBox(height: 16),
           Row( mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                 OutlinedButton.icon( icon: const Icon(Icons.call_outlined, size: 18), label: const Text('Call'), onPressed: (phone != null && phone.isNotEmpty) ? () => _makePhoneCall(phone) : null, style: OutlinedButton.styleFrom( foregroundColor: (phone != null && phone.isNotEmpty) ? Theme.of(context).primaryColor : Colors.grey, side: BorderSide(color: (phone != null && phone.isNotEmpty) ? Theme.of(context).primaryColor : Colors.grey),),),
                 OutlinedButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Chat'),
                    // *** Updated onPressed for Chat Button ***
                    onPressed: () {
                       final currentUserId = _auth.currentUser?.uid;
                       // Determine the other user's ID from the booking details
                       final otherUserId = widget.userRole == 'Homeowner' ? _booking?.handymanId : _booking?.homeownerId;
                       // Get other user's details from the fetched map
                       final otherPartyNameFromData = partyData?['name'] as String?; // Use fetched name
                       final otherPartyImageUrlFromData = partyData?['profileImageUrl'] as String?; // Use fetched image

                       if (currentUserId != null && otherUserId != null && otherUserId.isNotEmpty && otherPartyNameFromData != null) {
                          // Generate consistent chat room ID by sorting UIDs
                          List<String> ids = [currentUserId, otherUserId];
                          ids.sort();
                          String chatRoomId = ids.join('_');
                          print('Navigating to chat room: $chatRoomId');

                          // Navigate to ChatPage (ensure ChatPage is created and imported)
                          Navigator.push(
                             context,
                             MaterialPageRoute(
                                builder: (_) => ChatPage(
                                   chatRoomId: chatRoomId,
                                   otherUserId: otherUserId,
                                   otherUserName: otherPartyNameFromData, // Pass fetched name
                                   otherUserImageUrl: otherPartyImageUrlFromData, // Pass fetched image URL
                                ),
                             ),
                          );
                       } else {
                          print('Cannot initiate chat. User details missing. Current: $currentUserId, Other: $otherUserId, Name: $otherPartyNameFromData');
                          ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('Cannot initiate chat. User details missing.')),
                          );
                       }
                    },
                    // *** End of Update ***
                 ),
              ],)
        ],);
  }
  // *** END OF MODIFICATION ***

  Widget _buildReviewsContent() { /* ... remains same ... */
     return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Reviews'), const SizedBox(height: 8), const Center(child: Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Text('Reviews for this booking coming soon!', style: TextStyle(color: Colors.grey)),)),],);
  }

  Widget? _buildBottomActions() { /* ... remains same with updated navigation ... */
     if (_isLoading || _booking == null) return null; final ButtonStyle elevatedButtonStyle = ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),); final ButtonStyle outlinedButtonStyle = OutlinedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),); switch (_booking!.status) { case 'Pending': if (widget.userRole == 'Handyman') { return Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Row( children: [ Expanded( child: OutlinedButton( onPressed: _isProcessingAction ? null : _showDeclineDialog, style: outlinedButtonStyle.copyWith( foregroundColor: MaterialStateProperty.all(Colors.red), side: MaterialStateProperty.all(const BorderSide(color: Colors.red)),), child: const Text('Decline'),),), const SizedBox(width: 8), Expanded( child: ElevatedButton( onPressed: _isProcessingAction ? null : _acceptBooking, style: elevatedButtonStyle, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Accept'),),),],),); } else { return Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisSize: MainAxisSize.min, children: [ Container( padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration( color: Colors.orange.shade100, borderRadius: BorderRadius.circular(20),), child: Text('Waiting for Handyman Approval', style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),), const SizedBox(height: 12), SizedBox( width: double.infinity, child: ElevatedButton( style: elevatedButtonStyle.copyWith( backgroundColor: MaterialStateProperty.all(Colors.red[700]), foregroundColor: MaterialStateProperty.all(Colors.white)), onPressed: _isProcessingAction ? null : _showCancelDialogByHomeowner, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Cancel Booking'),),),],),); } case 'Accepted': if (widget.userRole == 'Handyman') { return Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Row( children: [ Expanded( child: OutlinedButton( onPressed: _isProcessingAction ? null : _showCancelDialogByHandyman, style: outlinedButtonStyle.copyWith( foregroundColor: MaterialStateProperty.all(Colors.purple), side: MaterialStateProperty.all(const BorderSide(color: Colors.purple)),), child: const Text('Cancel'),),), const SizedBox(width: 8), Expanded( child: ElevatedButton( onPressed: _isProcessingAction ? null : _startDriving, style: elevatedButtonStyle, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Start Driving'),),),],),); } else { return Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisSize: MainAxisSize.min, children: [ Container( padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration( color: Colors.blue.shade100, borderRadius: BorderRadius.circular(20),), child: Text('Booking Accepted! Waiting for Handyman.', style: TextStyle(color: Colors.blue.shade800, fontSize: 12)),), const SizedBox(height: 12), SizedBox( width: double.infinity, child: ElevatedButton( style: elevatedButtonStyle.copyWith( backgroundColor: MaterialStateProperty.all(Colors.red[700]), foregroundColor: MaterialStateProperty.all(Colors.white)), onPressed: _isProcessingAction ? null : _showCancelDialogByHomeowner, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Cancel Booking'),),),],),); } case 'En Route': if (widget.userRole == 'Homeowner') { return Padding( padding: const EdgeInsets.all(16.0), child: SizedBox( width: double.infinity, child: ElevatedButton( style: elevatedButtonStyle.copyWith(backgroundColor: MaterialStateProperty.all(Colors.green[700])), onPressed: _isProcessingAction ? null : _showStartServiceConfirmation, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Start Service'),),),); } else { return Container( padding: const EdgeInsets.all(16.0), width: double.infinity, child: Text('On the way! Waiting for Homeowner to start service.', textAlign: TextAlign.center, style: TextStyle(color: Colors.cyan[800], fontWeight: FontWeight.bold)),); } case 'Ongoing': if (widget.userRole == 'Homeowner') { return Padding( padding: const EdgeInsets.all(16.0), child: SizedBox( width: double.infinity, child: ElevatedButton( style: elevatedButtonStyle.copyWith(backgroundColor: MaterialStateProperty.all(Colors.teal)), onPressed: _isProcessingAction ? null : () { Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentPage(bookingId: _booking!.bookingId /* Pass necessary details */))); }, child: _isProcessingAction ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Pay Now'),),),); } else { return Container( padding: const EdgeInsets.all(16.0), width: double.infinity, child: Text('Service in progress. Waiting for payment.', textAlign: TextAlign.center, style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold)),); } case 'Completed': if (widget.userRole == 'Homeowner') { return Padding( padding: const EdgeInsets.all(16.0), child: SizedBox( width: double.infinity, child: ElevatedButton.icon( icon: const Icon(Icons.star_outline), label: const Text('Rate Service'), style: elevatedButtonStyle, onPressed: _isProcessingAction ? null : () { Navigator.push(context, MaterialPageRoute(builder: (_) => RateServicesPage(bookingId: _booking!.bookingId, serviceId: _booking!.serviceId /* Pass necessary details */))); },),),); } else { return Container( padding: const EdgeInsets.all(16.0), width: double.infinity, child: Text('Booking Completed', textAlign: TextAlign.center, style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold)),); } default: return null; }
  }


  Widget _buildInfoRow(IconData icon, String text, {TextStyle? textStyle, Color? iconColor}) { return Padding( padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row( crossAxisAlignment: CrossAxisAlignment.start, children: [ Icon(icon, size: 18, color: iconColor ?? Colors.grey[700]), const SizedBox(width: 10), Expanded( child: Text( text, style: textStyle ?? Theme.of(context).textTheme.bodyMedium,)),],),); }
  Widget _buildSectionTitle(String title) { return Text( title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),); }
  Color _getStatusColor(String status) { switch (status) { case "Pending": return Colors.orange.shade700; case "Accepted": return Colors.blue.shade700; case "En Route": return Colors.cyan.shade600; case "Ongoing": return Colors.lightBlue.shade600; case "Completed": return Colors.green.shade700; case "Declined": return Colors.red.shade700; case "Cancelled": return Colors.grey.shade700; default: return Colors.grey; } }
  Widget _buildPriceRow(String label, int amountInSen, {bool isTotal = false}) { final double amountRM = amountInSen / 100.0; return Padding( padding: const EdgeInsets.symmetric(vertical: 2.0), child: Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Text(label, style: TextStyle(fontSize: isTotal ? 15 : 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)), Text( 'RM ${amountRM.toStringAsFixed(2)}', style: TextStyle(fontSize: isTotal ? 15 : 14, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal))],),); }

}