import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/chat_message.dart';

class ChatPage extends StatefulWidget {
  final String chatRoomId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserImageUrl;

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
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final GlobalKey _unreadChipKey = GlobalKey();
  User? _currentUser;
  int? _unreadStartIndex;

  StreamSubscription? _messagesSubscription;
  List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _listenForMessages();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesSubscription?.cancel();
    super.dispose();
  }

  void _listenForMessages() {
    final messagesRef = _dbRef
        .child('chatMessages/${widget.chatRoomId}')
        .orderByChild('timestamp');
    _messagesSubscription = messagesRef.onValue.listen((event) {
      if (!mounted) return;
      final List<ChatMessage> loadedMessages = [];
      if (event.snapshot.exists) {
        for (final child in event.snapshot.children) {
          final messageData =
              Map<String, dynamic>.from(child.value as Map);
          loadedMessages.add(ChatMessage.fromMap(child.key!, messageData));
        }
        loadedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
      setState(() {
        _messages = loadedMessages;
      });
      _scrollToUnreadIfAny();
    },
      onError: (Object error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error loading messages.')),
          );
        }
      },
    );
  }

  Future<int?> _getUnreadCount() async {
    if (_currentUser == null) return null;

    final snapshot = await _dbRef
        .child('chats/${widget.chatRoomId}/unreadCount/${_currentUser!.uid}')
        .get();

    if (snapshot.exists) {
      final count = snapshot.value;
      if (count is int) return count;
    }
    return null;
  }

  void _scrollToUnreadIfAny() async {
    final unreadCount = await _getUnreadCount();
    if (!mounted) return;

    if (unreadCount != null && unreadCount > 0) {
      setState(() {
      _unreadStartIndex = _messages.length - unreadCount;
      });
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _unreadChipKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible( //use _scrollController.animateTo and offset manually for unread count>16
          context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
      // fallback: scroll to bottom
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.minScrollExtent);
      }
    }
  });
      _markMessagesAsRead();
    } else {
      // force jump to bottom if no unread
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.minScrollExtent);
        }
      });
    }
  }

  void _markMessagesAsRead() {
    if (_currentUser == null) return;
    _dbRef
        .child('chats/${widget.chatRoomId}/unreadCount/${_currentUser!.uid}')
        .set(0);
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUser == null) return;

    final messageRef =
        _dbRef.child('chatMessages/${widget.chatRoomId}').push();
    final messageId = messageRef.key;
    if (messageId == null) return;

    final messageData = {
      'messageId': messageId,
      'senderId': _currentUser!.uid,
      'receiverId': widget.otherUserId,
      'text': text,
      'timestamp': ServerValue.timestamp,
    };

    Map<String, dynamic> atomicUpdate = {
      'chatMessages/${widget.chatRoomId}/$messageId': messageData,
      'chats/${widget.chatRoomId}/lastMessage/text': text,
      'chats/${widget.chatRoomId}/lastMessage/senderId': _currentUser!.uid,
      'chats/${widget.chatRoomId}/lastMessage/timestamp': ServerValue.timestamp,
      'chats/${widget.chatRoomId}/lastUpdatedAt': ServerValue.timestamp,
      'chats/${widget.chatRoomId}/unreadCount/${widget.otherUserId}':ServerValue.increment(1),
      'chats/${widget.chatRoomId}/unreadCount/${_currentUser!.uid}': 0, // sender has no unread
      'chats/${widget.chatRoomId}/users/${_currentUser!.uid}': true,
      'chats/${widget.chatRoomId}/users/${widget.otherUserId}': true,
    };

    try {
      await _dbRef.root.update(atomicUpdate);
      _messageController.clear();
      // jump to bottom immediately after sending
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.minScrollExtent);
        }
      });
    } catch (e) {
      print("Error sending message: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message.')),
        );
      }
    }
  }

  String _formatDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToFormat =
        DateTime(date.year, date.month, date.day);

    if (dateToFormat == today) return 'Today';
    if (dateToFormat == yesterday) return 'Yesterday';
    return DateFormat('d MMMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: widget.otherUserImageUrl != null
                  ? NetworkImage(widget.otherUserImageUrl!)
                  : null,
              child: widget.otherUserImageUrl == null
                  ? const Icon(Icons.person, size: 18)
                  : null,
            ),
            const SizedBox(width: 12),
            Text(widget.otherUserName),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                        'No messages yet. Start the conversation!'))
                : ListView.builder(
                    reverse: true, // latest message appears at bottom
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[_messages.length - 1 - index];
                      final messageIndexInOriginalList = _messages.length - 1 - index;
                      final isMe = message.senderId == _currentUser!.uid;

                      bool showDateSeparator = false;
                      if (index == _messages.length - 1) {
                        showDateSeparator = true;
                      } else {
                        final previousMessage =
                            _messages[_messages.length - index - 2];
                        final previousDate = DateTime(
                            previousMessage.timestamp.year,
                            previousMessage.timestamp.month,
                            previousMessage.timestamp.day);
                        final currentDate = DateTime(
                            message.timestamp.year,
                            message.timestamp.month,
                            message.timestamp.day);
                            if (currentDate.isAfter(previousDate)) {
                            showDateSeparator = true;
                          }
                      }
                      final List<Widget> children = [];
                      if (showDateSeparator) {
                        children.add(_buildDateSeparator(message.timestamp));
                      }

                      if (_unreadStartIndex != null &&
                          messageIndexInOriginalList == _unreadStartIndex) {
                        children.add(_buildUnreadChip());
                      }

                      children.add(_buildMessageBubble(message, isMe));

                      return Column(children: children);
                    },
                  ),
          ),
          _buildMessageComposer(),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Center(
        child: Chip(
          label: Text(
            _formatDateSeparator(date),
            style: TextStyle(color: Colors.grey[600]),
          ),
          backgroundColor: Colors.grey[200],
        ),
      ),
    );
  }

  Widget _buildUnreadChip() {
  return Padding(
    key: _unreadChipKey,
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Center(
      child: Chip(
        label: Text(
          'Unread Messages',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.redAccent,
      ),
    ),
  );
}

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    return Align(
      alignment:
          isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Card(
        color: isMe
            ? Theme.of(context).primaryColor
            : Theme.of(context).cardColor,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft:
                isMe ? const Radius.circular(12) : const Radius.circular(0),
            bottomRight:
                isMe ? const Radius.circular(0) : const Radius.circular(12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: TextStyle(
                    color: isMe ? Colors.white : null),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat.jm().format(message.timestamp),
                style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? Colors.white70
                        : Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageComposer() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                textCapitalization:
                    TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            IconButton(
              icon: Icon(Icons.send,
                  color: Theme.of(context).primaryColor),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}