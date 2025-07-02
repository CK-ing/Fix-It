import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../../models/custom_request.dart';
import 'bookings_detail_page.dart';
import 'custom_request_status_page.dart';
import 'job_request_detail_page.dart';
import 'job_requests_page.dart';


// A simple class to model a notification
class NotificationItem {
  final String id;
  final String title;
  final String body;
  final String? bookingId;
  final String type; // 'booking' or 'promotion'
  final DateTime createdAt;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    this.bookingId,
    required this.type,
    required this.createdAt,
  });

  factory NotificationItem.fromMap(String id, Map<String, dynamic> data) {
    return NotificationItem(
      id: id,
      title: data['title'] ?? 'No Title',
      body: data['body'] ?? 'No content.',
      bookingId: data['bookingId'] as String?,
      type: data['type'] ?? 'general',
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : DateTime.now(),
    );
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  User? _currentUser;
  
  List<NotificationItem> _notifications = [];
  bool _isLoading = true;
  StreamSubscription? _notificationsSubscription;
  
  // *** NEW: Store the current user's role ***
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _loadInitialData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _notificationsSubscription?.cancel();
    super.dispose();
  }

  // *** NEW: Combined initial data loading ***
  Future<void> _loadInitialData() async {
    // First, get the user's role
    final userSnapshot = await _dbRef.child('users/${_currentUser!.uid}/role').get();
    if (mounted && userSnapshot.exists) {
      _currentUserRole = userSnapshot.value as String?;
    }
    // Now start listening and marking as read
    _listenForNotifications();
    _markNotificationsAsRead();
  }

  void _listenForNotifications() {
    _notificationsSubscription?.cancel();
    final query = _dbRef
        .child('notifications/${_currentUser!.uid}')
        .orderByChild('createdAt');

    _notificationsSubscription = query.onValue.listen((event) {
      if (!mounted) return;
      final List<NotificationItem> loadedNotifications = [];
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        for (var entry in data.entries) {
          loadedNotifications.add(
            NotificationItem.fromMap(entry.key, Map<String, dynamic>.from(entry.value))
          );
        }
        // Sort descending to show newest first
        loadedNotifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      setState(() {
        _notifications = loadedNotifications;
        _isLoading = false;
      });
    }, onError: (error) {
      print("Error fetching notifications: $error");
      setState(() => _isLoading = false);
    });
  }

  void _markNotificationsAsRead() {
    final notificationsRef = _dbRef.child('notifications/${_currentUser!.uid}');
    notificationsRef.get().then((snapshot) {
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final Map<String, dynamic> updates = {};
        data.forEach((key, value) {
          if (value is Map && (value['isRead'] == false || value['isRead'] == null)) {
            updates['$key/isRead'] = true;
          }
        });
        if (updates.isNotEmpty) {
          notificationsRef.update(updates);
        }
      }
    });
  }
  
  void _showClearConfirmationDialog() {
    if (_notifications.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear All Notifications?"),
        content: const Text("Are you sure you want to permanently delete all notifications? This action cannot be undone."),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.of(context).pop(),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Clear All"),
            onPressed: () {
              Navigator.of(context).pop();
              _clearAllNotifications();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllNotifications() async {
    if (_currentUser == null) return;
    try {
      await _dbRef.child('notifications/${_currentUser!.uid}').remove();
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("All notifications cleared."), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to clear notifications: ${e.toString()}"), backgroundColor: Colors.red)
        );
      }
    }
  }
  
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToFormat = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (dateToFormat == today) {
      return DateFormat.jm().format(timestamp); // e.g., 5:30 PM
    } else if (dateToFormat == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('dd MMM').format(timestamp); // e.g., 20 Jun
    }
  }
  
  // *** MODIFIED: Added icons for handyman notifications ***
  IconData _getIconForType(String type) {
    switch (type) {
      // Homeowner notifications
      case 'booking_accepted': return Icons.check_circle_outline;
      case 'booking_enroute': return Icons.directions_car_outlined;
      case 'booking_declined': return Icons.cancel_outlined;
      case 'custom_request_update': return Icons.request_quote_outlined;
      
      // Handyman notifications
      case 'custom_request': return Icons.post_add_outlined;
      case 'new_booking': return Icons.bookmark_add_outlined;
      case 'booking_cancelled': return Icons.highlight_off_outlined;
      case 'booking_started': return Icons.play_circle_outline;
      case 'payment_received': return Icons.monetization_on_outlined;
      case 'new_review': return Icons.star_outline;
      case 'custom_request_declined': return Icons.thumb_down_alt_outlined;
      
      // General
      case 'promotion': return Icons.local_offer_outlined;
      default: return Icons.notifications_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear All Notifications',
            onPressed: _isLoading || _notifications.isEmpty ? null : _showClearConfirmationDialog,
          )
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notifications.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('No Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Important updates will appear here.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    return ListView.separated(
      itemCount: _notifications.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Icon(_getIconForType(notification.type), color: Theme.of(context).primaryColor),
          ),
          title: Text(notification.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(notification.body),
          trailing: Text(
            _formatTimestamp(notification.createdAt),
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          onTap: () async {
  // --- MODIFIED: Final, robust navigation logic for all notification types ---
  final String? id = notification.bookingId; // Can be bookingId or requestId
  if (id == null || _currentUserRole == null) return;

  // For notifications that are purely informational and have no action, just return.
  if (notification.type == 'custom_request_declined') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This quote was declined by the customer.'))
    );
    return;
  }

  // Show a temporary loading indicator for checks that require a database call
  showDialog(context: context, builder: (context) => const Center(child: CircularProgressIndicator()), barrierDismissible: false);

  try {
    switch (notification.type) {
      // --- HANDYMAN ACTIONS ---
      case 'new_booking':
      case 'custom_request':
        final node = notification.type == 'new_booking' ? 'bookings' : 'custom_requests';
        final snapshot = await _dbRef.child('$node/$id/status').get();
        Navigator.pop(context); // Dismiss loading dialog
        
        if (mounted && snapshot.value == 'Pending') {
          if (node == 'bookings') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailPage(bookingId: id, userRole: _currentUserRole!)));
          } else {
            // Refetch the view model data to ensure it's current before navigating
            final requestSnapshot = await _dbRef.child('custom_requests/$id').get();
            if (!requestSnapshot.exists) throw Exception("Request not found");
            final request = CustomRequest.fromSnapshot(requestSnapshot);
            final homeownerSnapshot = await _dbRef.child('users/${request.homeownerId}').get();
            if (!homeownerSnapshot.exists) throw Exception("Homeowner not found");
            final homeownerData = Map<String, dynamic>.from(homeownerSnapshot.value as Map);
            final viewModel = CustomRequestViewModel(request: request, homeownerName: homeownerData['name'] ?? 'Customer', homeownerImageUrl: homeownerData['profileImageUrl']);
            if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => JobRequestDetailPage(requestViewModel: viewModel)));
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This request has already been actioned.')));
        }
        break;
      
      // --- HOMEOWNER ACTIONS ---
      case 'custom_request_update':
        final snapshot = await _dbRef.child('custom_requests/$id/status').get();
        Navigator.pop(context); // Dismiss loading dialog
        if (mounted && snapshot.value == 'Quoted') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => CustomRequestStatusPage(requestId: id)));
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This quote is no longer active.')));
        }
        break;

      // Default navigation for all other types (e.g., accepted, enroute, etc.)
      default:
        Navigator.pop(context); // Dismiss loading dialog
        Navigator.push(context, MaterialPageRoute(builder: (_) => BookingDetailPage(bookingId: id, userRole: _currentUserRole!)));
        break;
    }
  } catch (e) {
    print("Error during notification navigation: $e");
    if(mounted) {
      Navigator.pop(context); // Dismiss loading dialog on error
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open the item.")));
    }
  }
},
        );
      },
    );
  }
}
