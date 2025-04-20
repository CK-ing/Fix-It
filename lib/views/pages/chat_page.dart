import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// *** Import RTDB ***
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart'; // For formatting timestamps

class ChatPage extends StatefulWidget {
  final String chatRoomId; // Combined & sorted UIDs (e.g., uid1_uid2)
  final String otherUserId;
  final String otherUserName;
  final String? otherUserImageUrl; // Optional image URL

  const ChatPage({
    required this.chatRoomId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserImageUrl,
    super.key,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // *** Use RTDB Reference ***
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  User? _currentUser;
  bool _isSending = false;
  bool _initialScrollDone = false;
  StreamSubscription? _messageSubscription; // To manage the RTDB listener

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    // We will set up the stream listener within the StreamBuilder equivalent for RTDB
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: true));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel(); // Cancel RTDB listener
    super.dispose();
  }

  // --- Send Message Logic (Using RTDB) ---
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUser == null || _isSending) {
      return;
    }

    setState(() { _isSending = true; });
    final messageTextToSend = text;
    _messageController.clear();

    // *** Use RTDB ServerValue.timestamp ***
    final messageTimestamp = ServerValue.timestamp;

    // Reference the specific chat's messages node
    final messagesRef = _dbRef.child('chatMessages').child(widget.chatRoomId);
    // Generate a unique key for the new message using push()
    final newMessageRef = messagesRef.push();
    final messageId = newMessageRef.key; // Get the unique key

    if (messageId == null) {
       print("Error: Could not generate message ID");
       setState(() { _isSending = false; });
       // Restore text?
       _messageController.text = messageTextToSend;
       return;
    }

    // Prepare message data
    final messageData = {
      'messageId': messageId,
      'senderId': _currentUser!.uid,
      'receiverId': widget.otherUserId,
      'text': messageTextToSend,
      'timestamp': messageTimestamp, // Use RTDB timestamp placeholder
    };

    // Prepare last message data for chat room document
    final lastMessageData = {
      'text': messageTextToSend,
      'senderId': _currentUser!.uid,
      'timestamp': messageTimestamp,
    };

    // Reference the parent chat metadata node
    final chatRef = _dbRef.child('chats').child(widget.chatRoomId);

    try {
      // 1. Set the new message data using the generated key
      await newMessageRef.set(messageData);

      // 2. Update the parent chat document's metadata
      // Ensure 'users' map exists - ideally set when chat is first initiated
      // Using update is generally safer than set for metadata
      await chatRef.update({
        'lastMessage': lastMessageData,
        'lastUpdatedAt': messageTimestamp,
        'users/${_currentUser!.uid}': true, // Ensure users map exists/is updated
        'users/${widget.otherUserId}': true,
      });

      print("Message sent successfully to RTDB!");
      _scrollToBottom();

    } catch (e) {
      print("Error sending message to RTDB: $e");
      // Restore text field content if sending failed
      if (mounted) {
          _messageController.text = messageTextToSend;
          ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Error sending message: ${e.toString()}'), backgroundColor: Colors.red)
          );
      }
    } finally {
       if (mounted) {
          setState(() { _isSending = false; });
       }
    }
  }

  // --- Scroll Logic ---
  void _scrollToBottom({bool jump = false}) { /* ... remains same ... */ if (_scrollController.hasClients) { Future.delayed(const Duration(milliseconds: 100), () { if (mounted && _scrollController.hasClients) { if (jump) { _scrollController.jumpTo(_scrollController.position.minScrollExtent); } else { _scrollController.animateTo( _scrollController.position.minScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut,); } } }); } }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar( /* ... AppBar remains same ... */ title: Row( children: [ CircleAvatar( radius: 18, backgroundColor: Colors.grey[300], backgroundImage: (widget.otherUserImageUrl != null && widget.otherUserImageUrl!.isNotEmpty) ? NetworkImage(widget.otherUserImageUrl!) : null, child: (widget.otherUserImageUrl == null || widget.otherUserImageUrl!.isEmpty) ? const Icon(Icons.person, size: 20, color: Colors.grey) : null,), const SizedBox(width: 10), Text(widget.otherUserName),],), elevation: 1.0,),
      body: Column(
        children: [
          Expanded( child: _buildMessagesList(),),
          _buildMessageInput(), // Wrapped in SafeArea
        ],
      ),
    );
  }

  // --- Widget Builders ---

  // *** MODIFIED: Builds the list of messages using RTDB Stream ***
  Widget _buildMessagesList() {
    if (_currentUser == null) return const Center(child: Text("Not logged in."));

    // Query RTDB messages node, order by timestamp
    // Note: RTDB ordering requires data to be structured correctly or indexing rules
    // For simplicity here, we fetch all and sort client-side.
    // For performance on large chats, consider server-side filtering/pagination or structuring data differently.
    Query messagesQuery = _dbRef
        .child('chatMessages')
        .child(widget.chatRoomId)
        .orderByChild('timestamp'); // Order by timestamp

    return StreamBuilder<DatabaseEvent>(
      stream: messagesQuery.onValue, // Listen to value changes
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !_initialScrollDone) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading messages: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          // Check if snapshot.data or snapshot.data.snapshot is null
           if (snapshot.connectionState == ConnectionState.active && !_initialScrollDone) {
              // If connected but no data, means empty chat
              _initialScrollDone = true; // Mark initial scroll check done
              return const Center(child: Text('Say hello!'));
           } else if (!_initialScrollDone) {
              // Still waiting or error before first data
              return const Center(child: CircularProgressIndicator());
           } else {
              // Already loaded once, now it's empty
               return const Center(child: Text('Say hello!'));
           }
        }

        // Data received, process it
        final messagesData = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
        // Convert map to a list of messages, adding the key as messageId
        final messagesList = messagesData.entries.map((entry) {
            final messageContent = Map<String, dynamic>.from(entry.value as Map);
            messageContent['messageId'] = entry.key; // Add the key/ID to the map
            return messageContent;
        }).toList();

        // Sort messages by timestamp (client-side as RTDB order might not be guaranteed perfectly here)
        messagesList.sort((a, b) {
            final timestampA = a['timestamp'] as int? ?? 0;
            final timestampB = b['timestamp'] as int? ?? 0;
            return timestampA.compareTo(timestampB); // Ascending for normal view
        });

        // Scroll to bottom after first load
        if (!_initialScrollDone) {
           WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(jump: true));
           _initialScrollDone = true;
        }

        return ListView.builder(
          controller: _scrollController,
          reverse: true, // Display messages from bottom to top
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          itemCount: messagesList.length,
          itemBuilder: (context, index) {
            // Access messages in reverse order because ListView is reversed
            final messageData = messagesList[messagesList.length - 1 - index];
            return _buildMessageBubble(messageData);
          },
        );
      },
    );
  }
  // *** END OF MODIFICATION ***

  // *** MODIFIED: Builds a single message bubble (Handles int timestamp) ***
  Widget _buildMessageBubble(Map<String, dynamic> messageData) {
    if (_currentUser == null) return const SizedBox.shrink();

    final bool isMe = messageData['senderId'] == _currentUser!.uid;
    final String messageText = messageData['text'] ?? '';
    // *** Timestamp from RTDB is likely an integer (milliseconds) ***
    final int? timestampMillis = messageData['timestamp'] as int?;
    final String formattedTime = timestampMillis != null
        ? DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(timestampMillis))
        : '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
        decoration: BoxDecoration(
          color: isMe ? Theme.of(context).primaryColor : Colors.grey[300],
          borderRadius: BorderRadius.only( topLeft: const Radius.circular(15.0), topRight: const Radius.circular(15.0), bottomLeft: isMe ? const Radius.circular(15.0) : const Radius.circular(0), bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(15.0),),
        ),
        child: Column(
           crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
           mainAxisSize: MainAxisSize.min,
           children: [
              Text( messageText, style: TextStyle(color: isMe ? Colors.white : Colors.black87),),
              if (formattedTime.isNotEmpty) ...[ const SizedBox(height: 3), Text( formattedTime, style: TextStyle( fontSize: 10, color: isMe ? Colors.white70 : Colors.black54,),),],
           ],
        ),
      ),
    );
  }
  // *** END OF MODIFICATION ***

  // Builds the message input wrapped in SafeArea
  Widget _buildMessageInput() {
    // ... (Input UI remains the same, uses _sendMessage which is now RTDB) ...
    return SafeArea( bottom: true, top: false, child: Container( padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0), decoration: BoxDecoration( color: Theme.of(context).cardColor, boxShadow: [ BoxShadow( offset: const Offset(0, -1), blurRadius: 4, color: Colors.black.withOpacity(0.05),)],), child: Row( children: [ Expanded( child: TextField( controller: _messageController, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration( hintText: 'Type a message...', border: InputBorder.none, filled: true, fillColor: Colors.black12, contentPadding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 15.0), isDense: true, enabledBorder: OutlineInputBorder( borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(25.0))), focusedBorder: OutlineInputBorder( borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(25.0))),), onSubmitted: (_) => _messageController.text.trim().isNotEmpty ? _sendMessage() : null, onChanged: (text) => setState(() {}),),), const SizedBox(width: 8), _isSending ? const Padding( padding: EdgeInsets.all(12.0), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))) : IconButton( icon: const Icon(Icons.send), color: Theme.of(context).primaryColor, onPressed: _messageController.text.trim().isEmpty ? null : _sendMessage,),],),),);
  }
}