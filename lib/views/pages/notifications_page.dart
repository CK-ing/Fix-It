import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import 'bookings_detail_page.dart';


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

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _listenForNotifications();
      _markNotificationsAsRead();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _notificationsSubscription?.cancel();
    super.dispose();
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

  // Marks all unread notifications as read for the current user
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
  
  IconData _getIconForType(String type) {
    switch (type) {
      case 'booking_accepted': return Icons.check_circle_outline;
      case 'booking_enroute': return Icons.directions_car_outlined;
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
          onTap: () {
            if (notification.bookingId != null) {
              // Navigate to the specific booking detail page
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => BookingDetailPage(
                  bookingId: notification.bookingId!,
                  userRole: 'Homeowner', // Assuming only homeowners get notifications for now
                )),
              );
            }
          },
        );
      },
    );
  }
}
