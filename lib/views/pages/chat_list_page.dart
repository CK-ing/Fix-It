import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart'; // Use RTDB
import 'package:intl/intl.dart';

// Import ChatPage
// TODO: Ensure this path is correct
import 'chat_page.dart';
// Import BookingDetailPage (Potentially needed if navigating back requires specific state)
// import 'booking_detail_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref(); // RTDB ref
  User? _currentUser;
  StreamSubscription? _chatSubscription; // Subscription for RTDB listener
  List<Map<String, dynamic>> _userChats = []; // Store processed chats

  // Store user details fetched via FutureBuilder to avoid re-fetching on every rebuild
  final Map<String, Future<DataSnapshot>> _userDetailFutures = {};

  bool _isLoading = true; // Combined loading state
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _listenToChats(); // Start listening to RTDB
    } else {
      _error = "User not logged in.";
       _isLoading = false; // Stop loading if user is null
    }
  }

  @override
  void dispose() {
    _chatSubscription?.cancel(); // Cancel RTDB listener
    super.dispose();
  }

  // *** Listen to RTDB /chats node ***
  void _listenToChats() {
    if (_currentUser == null) return;
    setStateIfMounted(() { _isLoading = true; _error = null; });

    // Listen to the entire /chats node and filter client-side
    // Ordering by lastUpdatedAt requires an index in RTDB rules
    // Add ".indexOn": ["lastUpdatedAt"] to RTDB rules for /chats path
    final query = _dbRef.child('chats').orderByChild('lastUpdatedAt');

    _chatSubscription?.cancel();
    _chatSubscription = query.onValue.listen((event) {
      if (!mounted) return;
      print("RTDB Chat list data received: ${event.snapshot.value}");

      List<Map<String, dynamic>> fetchedUserChats = [];
      _error = null; // Clear previous error

      if (event.snapshot.exists && event.snapshot.value != null) {
         try {
            final allChatsData = Map<String, dynamic>.from(event.snapshot.value as Map);
            allChatsData.forEach((chatId, chatValue) {
               // Basic check if chatValue is a Map and contains 'users'
               if (chatValue is Map) {
                  final chatMap = Map<String, dynamic>.from(chatValue);
                  final usersMap = chatMap['users'] as Map<dynamic, dynamic>?;
                  // Check if current user is a participant
                  if (usersMap != null && usersMap.containsKey(_currentUser!.uid)) {
                     chatMap['chatId'] = chatId; // Add chatId to the map
                     fetchedUserChats.add(chatMap);
                  }
               } else {
                  print("Skipping invalid chat data for key: $chatId");
               }
            });

            // Sort client-side by lastUpdatedAt (descending)
            fetchedUserChats.sort((a, b) {
                final timestampA = a['lastUpdatedAt'] as int? ?? 0;
                final timestampB = b['lastUpdatedAt'] as int? ?? 0;
                return timestampB.compareTo(timestampA); // Newest first
            });

         } catch (e) {
             print("Error processing RTDB chats snapshot: $e");
             _error = "Error processing chat data.";
             fetchedUserChats = []; // Clear chats on error
         }
      } else {
         print("No chats found in RTDB");
      }

      // Update state
      setStateIfMounted(() {
         _userChats = fetchedUserChats;
         _isLoading = false; // Stop loading after processing
      });

    }, onError: (error) {
      print("Error listening to RTDB chats: $error");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load chats.";
          _userChats = [];
        });
      }
    });
  }
  // *** END OF RTDB LISTENER ***

  // Helper function to get the other user's ID from the chat users map
  String? _getOtherUserId(Map<dynamic, dynamic>? usersMap) {
    if (usersMap == null || _currentUser == null) return null;
    for (var userId in usersMap.keys) { if (userId != _currentUser!.uid) { return userId as String?; } }
    return null;
  }

  // Helper function to format RTDB timestamp (int milliseconds)
  String _formatTimestamp(int? timestampMillis) {
     if (timestampMillis == null) return '';
     final DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis);
     final now = DateTime.now(); final today = DateTime(now.year, now.month, now.day); final yesterday = DateTime(now.year, now.month, now.day - 1); final dateToCheck = DateTime(dateTime.year, dateTime.month, dateTime.day);
     if (dateToCheck == today) { return DateFormat.jm().format(dateTime); } else if (dateToCheck == yesterday) { return 'Yesterday'; } else { return DateFormat.yMd().format(dateTime); }
  }

  // Function to get or cache user detail futures
  Future<DataSnapshot> _getUserDetailFuture(String userId) {
    // Simple cache: If future already exists, return it. Otherwise, fetch and store.
    // Note: This doesn't handle errors or refetching automatically if user data changes.
    if (_userDetailFutures.containsKey(userId)) { return _userDetailFutures[userId]!; }
    else { final future = _dbRef.child('users').child(userId).get(); _userDetailFutures[userId] = future; return future; }
  }

  // *** Show Delete Confirmation Dialog ***
  void _showDeleteConfirmationDialog(String chatRoomId, String otherUserName) {
     showDialog(
        context: context,
        builder: (BuildContext context) {
           return AlertDialog(
              title: const Text("Delete Chat?"),
              content: Text("Are you sure you want to permanently delete this chat with $otherUserName?\n\nThis action cannot be undone and will delete the chat for BOTH participants."),
              actions: <Widget>[
                 TextButton(
                    child: const Text("Cancel"),
                    onPressed: () => Navigator.of(context).pop(),
                 ),
                 TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text("Delete Permanently"),
                    onPressed: () {
                       Navigator.of(context).pop(); // Close dialog
                       _deleteChat(chatRoomId); // Perform deletion
                    },
                 ),
              ],
           );
        },
     );
  }

  // *** Delete Chat Logic ***
  Future<void> _deleteChat(String chatRoomId) async {
     print("Attempting to delete chat: $chatRoomId");
     // TODO: Consider adding a visual loading indicator during deletion
     final scaffoldMessenger = ScaffoldMessenger.of(context);
     try {
        // Create map for multi-path update (atomic delete in RTDB)
        Map<String, Object?> updates = {};
        updates['/chats/$chatRoomId'] = null; // Mark chat metadata for deletion
        updates['/chatMessages/$chatRoomId'] = null; // Mark chat messages for deletion

        // Perform atomic delete
        await _dbRef.update(updates);

        print("Chat $chatRoomId deleted successfully.");
        // Remove cached future if user details were cached
        // (This part needs refinement based on how otherUserId is obtained before calling delete)
        // String? otherUserId = _getOtherUserIdFromChatId(chatRoomId); // Need a way to get this
        // if (otherUserId != null) {
        //    _userDetailFutures.remove(otherUserId);
        // }

        scaffoldMessenger.showSnackBar(
           const SnackBar(content: Text('Chat deleted successfully.'), backgroundColor: Colors.green)
        );
        // The listener (_listenToChats) should automatically update the UI list when data is removed

     } catch (e) {
        print("Error deleting chat $chatRoomId: $e");
        // Check for permission errors specifically if possible
        scaffoldMessenger.showSnackBar(
           SnackBar(content: Text('Failed to delete chat: ${e.toString()}'), backgroundColor: Colors.red)
        );
     }
     // Ensure loading indicator stops if one was added
  }


  // Helper to safely call setState only if the widget is still mounted
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) { setState(fn); }
  }

  @override
  Widget build(BuildContext context) {
    // *** REMOVED Scaffold and AppBar - Provided by WidgetTree ***

    if (_isLoading) { return const Center(child: CircularProgressIndicator()); }
    if (_error != null) { return Center(child: Text(_error!, style: const TextStyle(color: Colors.red))); }
    if (_userChats.isEmpty) {
      // Allow refresh when empty
       return RefreshIndicator(
         onRefresh: _handleRefresh, // Use separate refresh handler if needed, or just re-listen
         child: LayoutBuilder(
           builder: (context, constraints) => SingleChildScrollView(
             physics: const AlwaysScrollableScrollPhysics(),
             child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: const Center( child: Padding( padding: EdgeInsets.symmetric(vertical: 50.0, horizontal: 20.0), child: Text( 'No chats found.\nStart a conversation from a booking or profile.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))),
             ),
           ),
         )
      );
    }

    // Display the list of chats
    return RefreshIndicator( // Add pull-to-refresh
      onRefresh: _handleRefresh, // Use separate refresh handler
      child: ListView.separated(
        itemCount: _userChats.length,
        separatorBuilder: (context, index) => Divider(height: 0.5, indent: 88, endIndent: 16, color: Colors.grey[300]),
        itemBuilder: (context, index) {
          final chatData = _userChats[index];
          final String chatRoomId = chatData['chatId'] ?? '';
          final Map<dynamic, dynamic>? usersMap = chatData['users'] as Map<dynamic, dynamic>?;
          final String? otherUserId = _getOtherUserId(usersMap);
          final Map<String, dynamic> lastMessage = Map<String, dynamic>.from(chatData['lastMessage'] as Map? ?? {});
          final String lastMessageText = lastMessage['text'] ?? '';
          final int? lastMessageTimestamp = lastMessage['lastUpdatedAt'] as int?; // Use lastUpdatedAt for sorting consistency

          if (otherUserId == null || otherUserId.isEmpty) { return const SizedBox.shrink(); }

          // Use FutureBuilder to get the other user's details from RTDB
          return FutureBuilder<DataSnapshot>(
            future: _getUserDetailFuture(otherUserId),
            builder: (context, userSnapshot) {
              String otherUserName = 'Loading...';
              String? otherUserImageUrl;
              bool userDetailsAvailable = false;

              if (userSnapshot.connectionState == ConnectionState.done) {
                 if (userSnapshot.hasData && userSnapshot.data!.exists) {
                   try { final userData = Map<String, dynamic>.from(userSnapshot.data!.value as Map); otherUserName = userData['name'] ?? 'Unknown User'; otherUserImageUrl = userData['profileImageUrl'] as String?; userDetailsAvailable = true; }
                   catch (e) { otherUserName = 'Error Parsing User'; print("Error parsing user data for $otherUserId: $e"); }
                 } else if (userSnapshot.hasError) { otherUserName = 'Error'; print("Error fetching user $otherUserId from RTDB: ${userSnapshot.error}"); }
                 else { otherUserName = 'User Not Found'; }
              } else { otherUserName = 'Loading...'; }

              // Build the list tile for the chat
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                leading: CircleAvatar( radius: 28, backgroundColor: Colors.grey[300], backgroundImage: (otherUserImageUrl != null && otherUserImageUrl.isNotEmpty) ? NetworkImage(otherUserImageUrl) : null, child: (otherUserImageUrl == null || otherUserImageUrl.isEmpty) ? const Icon(Icons.person, color: Colors.grey, size: 30) : null,),
                title: Text( otherUserName, style: const TextStyle(fontWeight: FontWeight.bold),),
                subtitle: Text( lastMessageText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[600]),),
                trailing: Text( _formatTimestamp(lastMessageTimestamp), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),),
                onTap: () {
                  if (userDetailsAvailable) {
                     print('Navigate to chat with $otherUserId ($otherUserName)');
                     Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage( chatRoomId: chatRoomId, otherUserId: otherUserId, otherUserName: otherUserName, otherUserImageUrl: otherUserImageUrl,)));
                  } else { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Cannot open chat: $otherUserName details unavailable.')),); }
                },
                // *** ADDED: Long Press for Delete ***
                onLongPress: () {
                   if (userDetailsAvailable) { // Only allow delete if we know who the other user is
                      _showDeleteConfirmationDialog(chatRoomId, otherUserName);
                   }
                },
              );
            },
          );
        },
      ),
    );
  }

  // Optional: Separate refresh handler if different logic needed than initial listen
  Future<void> _handleRefresh() async {
     print("Handling refresh...");
     // For simplicity, just re-trigger the listener setup which includes loading state
     _listenToChats();
     // Add a slight delay to allow the indicator to show
     await Future.delayed(const Duration(milliseconds: 500));
  }

}

// Placeholder for ChatPage (ensure it exists and uses RTDB)
// class ChatPage extends StatelessWidget { ... } // Assumed to exist
