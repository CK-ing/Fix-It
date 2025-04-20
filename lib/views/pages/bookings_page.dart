import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

// Import BookingDetailPage
import '../../models/bookings_services.dart';
import 'bookings_detail_page.dart';

class BookingsPage extends StatefulWidget {
  final String userRole; // Receive user role ('Homeowner' or 'Handyman')

  const BookingsPage({required this.userRole, super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  StreamSubscription? _bookingSubscription;

  // State variables
  List<Booking> _allBookings = [];
  List<Booking> _pendingBookings = [];
  List<Booking> _ongoingBookings = [];
  List<Booking> _historyBookings = [];
  Map<String, Map<String, dynamic>> _serviceDetailsMap = {};
  Map<String, Map<String, dynamic>> _userDetailsMap = {};
  bool _isLoading = true;
  bool _isLoadingRelatedData = false;
  String? _error;
  DateTimeRange? _selectedDateRange;

  // *** MODIFIED: Define status categories ***
  final List<String> _pendingStatuses = ["Pending"];
  final List<String> _ongoingStatuses = ["Accepted", "En Route", "Ongoing"];
  // History includes all terminal states - using single "Cancelled"
  final List<String> _historyStatuses = ["Completed", "Declined", "Cancelled"];
  // *** END OF MODIFICATION ***


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() { if (mounted && _tabController.indexIsChanging) { setState(() {}); } });
    _listenToBookings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _bookingSubscription?.cancel();
    super.dispose();
  }

  // --- Data Fetching and Filtering Logic ---
  void _listenToBookings() { /* ... Same as previous ... */
    final user = _auth.currentUser; if (user == null) { setStateIfMounted(() { _isLoading = false; _error = "Please log in."; }); return; }
    if (!_isLoadingRelatedData) { setStateIfMounted(() { _isLoading = true; _error = null; }); }
    final String queryField = widget.userRole == 'Handyman' ? 'handymanId' : 'homeownerId';
    final query = _dbRef.child('bookings').orderByChild(queryField).equalTo(user.uid);
    _bookingSubscription?.cancel();
    _bookingSubscription = query.onValue.listen((event) async { if (!mounted) return; print("Booking data received: ${event.snapshot.value}"); List<Booking> fetchedBookings = []; _error = null; if (event.snapshot.exists && event.snapshot.value != null) { try { final dynamic snapshotValue = event.snapshot.value; if (snapshotValue is Map) { final data = Map<String, dynamic>.from(snapshotValue.cast<String, dynamic>()); fetchedBookings = data.entries.map((entry) { try { return Booking.fromSnapshot(event.snapshot.child(entry.key)); } catch (e) { print("Error parsing booking ${entry.key}: $e"); return null; } }).where((booking) => booking != null).cast<Booking>().toList(); fetchedBookings.sort((a, b) => b.scheduledDateTime.compareTo(a.scheduledDateTime)); } else { print("Bookings data is not a Map: $snapshotValue");} } catch (e) { print("Error processing bookings snapshot: $e"); _error = "Error processing booking data."; } } else { print("No bookings found for user ${user.uid} as ${widget.userRole}"); } _allBookings = fetchedBookings; await _fetchRelatedData(); _filterAndCategorizeBookings(); if (mounted) { setStateIfMounted(() { _isLoading = false; }); } }, onError: (error) { print("Error listening to bookings: $error"); if (mounted) { setState(() { _isLoading = false; _error = "Failed to load bookings."; _allBookings = []; _filterAndCategorizeBookings(); }); } });
  }
  Future<void> _fetchRelatedData() async { /* ... Same as previous ... */
     if (!mounted || _allBookings.isEmpty) { if (mounted) setStateIfMounted(() { _isLoadingRelatedData = false; _serviceDetailsMap = {}; _userDetailsMap = {}; }); return; }
     setStateIfMounted(() { _isLoadingRelatedData = true; }); Set<String> serviceIds = _allBookings.map((b) => b.serviceId).where((id) => id.isNotEmpty).toSet(); Set<String> userIds = {}; final currentUserId = _auth.currentUser!.uid; for (var booking in _allBookings) { final otherPartyId = widget.userRole == 'Homeowner' ? booking.handymanId : booking.homeownerId; if (otherPartyId.isNotEmpty) { userIds.add(otherPartyId); } } userIds.remove(currentUserId); List<Future> futures = []; Map<String, Map<String, dynamic>> tempServiceDetails = {}; Map<String, Map<String, dynamic>> tempUserDetails = {};
     if (serviceIds.isNotEmpty){ futures.add( Future.wait(serviceIds.map((id) async { try { final snapshot = await _dbRef.child('services').child(id).get(); if (snapshot.exists && snapshot.value != null) { tempServiceDetails[id] = Map<String, dynamic>.from(snapshot.value as Map); } } catch (e) { print("Error fetching service $id: $e"); } })) ); }
     if (userIds.isNotEmpty){ futures.add( Future.wait(userIds.map((id) async { try { final snapshot = await _dbRef.child('users').child(id).get(); if (snapshot.exists && snapshot.value != null) { tempUserDetails[id] = Map<String, dynamic>.from(snapshot.value as Map); } } catch (e) { print("Error fetching user $id: $e"); } })) ); }
     try { if (futures.isNotEmpty) { await Future.wait(futures); } if (mounted) { setState(() { _serviceDetailsMap = tempServiceDetails; _userDetailsMap = tempUserDetails; }); } } catch (e) { print("Error waiting for related data fetches: $e"); } finally { if (mounted) setStateIfMounted(() { _isLoadingRelatedData = false; }); }
  }
  // *** Uses updated status lists ***
  void _filterAndCategorizeBookings() {
    if (!mounted) return; List<Booking> filteredByDate = _allBookings; if (_selectedDateRange != null) { filteredByDate = _allBookings.where((booking) { final bookingDate = booking.scheduledDateTime; final startDate = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day); final endDate = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59); return bookingDate.isAfter(startDate.subtract(const Duration(microseconds: 1))) && bookingDate.isBefore(endDate.add(const Duration(microseconds: 1))); }).toList(); }
    _pendingBookings = filteredByDate.where((b) => _pendingStatuses.contains(b.status)).toList(); _ongoingBookings = filteredByDate.where((b) => _ongoingStatuses.contains(b.status)).toList(); _historyBookings = filteredByDate.where((b) => _historyStatuses.contains(b.status)).toList(); setStateIfMounted(() {});
  }
  Future<void> _showDateRangeFilter() async { /* ... Same as previous ... */
     final DateTimeRange? picked = await showDateRangePicker( context: context, firstDate: DateTime(DateTime.now().year - 2), lastDate: DateTime.now().add(const Duration(days: 365 * 2)), initialDateRange: _selectedDateRange, helpText: 'Filter Bookings by Date',); if (picked != null && picked != _selectedDateRange) { setStateIfMounted(() { _selectedDateRange = picked; }); _filterAndCategorizeBookings(); }
  }
  void _clearDateRangeFilter() { /* ... Same as previous ... */
     setStateIfMounted(() { _selectedDateRange = null; }); _filterAndCategorizeBookings();
  }
  void setStateIfMounted(VoidCallback fn) { if (mounted) { setState(fn); } }
  // --- End of Data Fetching and Filtering Logic ---

  @override
  Widget build(BuildContext context) {
    // ... (Scaffold, AppBar, TabBar logic remains the same) ...
    return Scaffold( appBar: AppBar( automaticallyImplyLeading: false, title: const Text('Bookings'), centerTitle: true, elevation: 1.0, actions: [ if (_selectedDateRange != null) IconButton( icon: const Icon(Icons.clear), tooltip: 'Clear Date Filter', onPressed: _clearDateRangeFilter,), IconButton( icon: Icon( Icons.filter_list, color: _selectedDateRange != null ? Theme.of(context).primaryColor : null,), tooltip: 'Filter by Date Range', onPressed: _showDateRangeFilter,), const SizedBox(width: 8),], bottom: TabBar( controller: _tabController, labelColor: Theme.of(context).primaryColor, unselectedLabelColor: Colors.grey[600], indicatorColor: Theme.of(context).primaryColor, tabs: [ Tooltip(message: "${_pendingBookings.length} pending", child: Tab(text: 'Pending (${_pendingBookings.length})')), Tooltip(message: "${_ongoingBookings.length} upcoming/ongoing", child: Tab(text: 'Upcoming (${_ongoingBookings.length})')), Tooltip(message: "${_historyBookings.length} past", child: Tab(text: 'History (${_historyBookings.length})')),],),), body: _isLoading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center))) : TabBarView( controller: _tabController, children: [ _buildBookingList(_pendingBookings, 'No pending bookings found${_selectedDateRange != null ? '\nin selected date range' : ''}.'), _buildBookingList(_ongoingBookings, 'No upcoming or ongoing bookings found${_selectedDateRange != null ? '\nin selected date range' : ''}.'), _buildBookingList(_historyBookings, 'No past bookings found${_selectedDateRange != null ? '\nin selected date range' : ''}.'),],),);
  }

  // Builds the ListView for a specific booking list
  Widget _buildBookingList(List<Booking> bookings, String emptyMessage) {
    // ... (Loading/Empty/Refresh logic remains the same) ...
    if (_isLoading || (_isLoadingRelatedData && bookings.isEmpty && _allBookings.isNotEmpty)) { return const Center(child: CircularProgressIndicator()); } if (bookings.isEmpty) { return RefreshIndicator( onRefresh: _handleRefresh, child: LayoutBuilder( builder: (context, constraints) => SingleChildScrollView( physics: const AlwaysScrollableScrollPhysics(), child: ConstrainedBox( constraints: BoxConstraints(minHeight: constraints.maxHeight), child: Center( child: Padding( padding: const EdgeInsets.symmetric(vertical: 50.0, horizontal: 20.0), child: Text(emptyMessage, textAlign: TextAlign.center))),),),) ); }
    return RefreshIndicator( onRefresh: _handleRefresh, child: ListView.builder( padding: const EdgeInsets.all(8.0), itemCount: bookings.length, itemBuilder: (context, index) { final booking = bookings[index]; return _buildBookingCard(booking, _serviceDetailsMap, _userDetailsMap); },),);
  }

  // Builds a single Booking Card (Navigation logic updated)
  Widget _buildBookingCard(
     Booking booking,
     Map<String, Map<String, dynamic>> serviceDetails,
     Map<String, Map<String, dynamic>> userDetails
  ) {
    // ... (Card content logic remains the same) ...
    final serviceInfo = serviceDetails[booking.serviceId]; final serviceImageUrl = serviceInfo?['imageUrl'] as String?; final String otherPartyId = widget.userRole == 'Homeowner' ? booking.handymanId : booking.homeownerId; final otherPartyInfo = userDetails[otherPartyId]; final otherPartyName = otherPartyInfo?['name'] ?? 'User Info Unavailable'; final otherPartyImageUrl = otherPartyInfo?['profileImageUrl'] as String?; final statusColor = _getStatusColor(booking.status);
    return Card( margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0), elevation: 2.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)), clipBehavior: Clip.antiAlias, child: InkWell(
        onTap: () {
          print('Tapped booking: ${booking.bookingId}');
          Navigator.push( context, MaterialPageRoute( builder: (_) => BookingDetailPage( bookingId: booking.bookingId, userRole: widget.userRole,),),);
        },
        child: Padding( padding: const EdgeInsets.all(12.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Row( crossAxisAlignment: CrossAxisAlignment.start, children: [ ClipRRect( borderRadius: BorderRadius.circular(8.0), child: Container( width: 75, height: 75, color: Colors.grey[200], child: (serviceImageUrl != null && serviceImageUrl.isNotEmpty) ? Image.network(serviceImageUrl, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2.0)), errorBuilder: (context, error, stack) => const Icon(Icons.error_outline, color: Colors.grey),) : const Icon(Icons.construction, size: 30, color: Colors.grey),),), const SizedBox(width: 12), Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text( booking.serviceName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis,), const SizedBox(height: 6), Row( children: [ CircleAvatar( radius: 10, backgroundColor: Colors.grey[300], backgroundImage: (otherPartyImageUrl != null && otherPartyImageUrl.isNotEmpty) ? NetworkImage(otherPartyImageUrl) : null, child: (otherPartyImageUrl == null || otherPartyImageUrl.isEmpty) ? Icon(widget.userRole == 'Homeowner' ? Icons.construction_outlined : Icons.person_outline, size: 12, color: Colors.grey[600]) : null,), const SizedBox(width: 6), Expanded( child: Text( otherPartyName, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis,)),],), Padding( padding: const EdgeInsets.only(top: 4.0), child: Text("ID: ${booking.bookingId}", style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),),],),), Padding( padding: const EdgeInsets.only(left: 8.0), child: Chip( label: Text(booking.status, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500)), backgroundColor: statusColor, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0), visualDensity: VisualDensity.compact, side: BorderSide.none,),),],), const Divider(height: 20), _buildInfoRow(Icons.calendar_today_outlined, booking.formattedScheduledDateTime), const SizedBox(height: 6), _buildInfoRow(Icons.location_on_outlined, booking.address), const SizedBox(height: 6), _buildInfoRow(Icons.attach_money_outlined, "RM ${booking.formattedTotal}", textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),],),),),);
  }

  // Helper for consistent info rows in the card
  Widget _buildInfoRow(IconData icon, String text, {TextStyle? textStyle, Color? iconColor}) { /* ... remains same ... */
     return Row( crossAxisAlignment: CrossAxisAlignment.start, children: [ Icon(icon, size: 16, color: iconColor ?? Colors.grey[700]), const SizedBox(width: 8), Expanded( child: Text( text, style: textStyle ?? Theme.of(context).textTheme.bodyMedium,)),],);
  }

  // *** Updated to remove specific cancelled statuses ***
  Color _getStatusColor(String status) {
    switch (status) {
      case "Pending": return Colors.orange.shade700;
      case "Accepted": return Colors.blue.shade700;
      case "En Route": return Colors.cyan.shade600;
      case "Ongoing": return Colors.lightBlue.shade600;
      case "Completed": return Colors.green.shade700;
      case "Declined": return Colors.red.shade700;
      case "Cancelled": return Colors.grey.shade700; // Unified cancelled color
      default: return Colors.grey;
    }
  }
  // *** END OF UPDATE ***

  // Added _handleRefresh method using fromSnapshot
  Future<void> _handleRefresh() async {
     // ... (logic remains the same) ...
     final user = _auth.currentUser; if (user == null) { setStateIfMounted(() { _error = "Please log in."; }); return; } print("Manual refresh triggered"); final String queryField = widget.userRole == 'Handyman' ? 'handymanId' : 'homeownerId'; final query = _dbRef.child('bookings').orderByChild(queryField).equalTo(user.uid); try { final snapshot = await query.get(); List<Booking> fetchedBookings = []; _error = null; if (snapshot.exists && snapshot.value != null) { final dynamic snapshotValue = snapshot.value; if (snapshotValue is Map) { for (final childSnapshot in snapshot.children) { try { final booking = Booking.fromSnapshot(childSnapshot); fetchedBookings.add(booking); } catch (e) { print("Error parsing refreshed booking ${childSnapshot.key}: $e"); } } fetchedBookings.sort((a, b) => b.scheduledDateTime.compareTo(a.scheduledDateTime)); } else { print("Refreshed Bookings data is not a Map: $snapshotValue"); } } else { print("No bookings found on refresh for user ${user.uid} as ${widget.userRole}"); } _allBookings = fetchedBookings; await _fetchRelatedData(); _filterAndCategorizeBookings(); } catch (error) { print("Error during manual refresh: $error"); if (mounted) { setState(() { _error = "Failed to refresh bookings."; }); } } finally { if (mounted) { setStateIfMounted(() { _isLoading = false; }); } }
  }

}
