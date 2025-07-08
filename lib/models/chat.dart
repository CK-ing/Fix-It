import 'package:firebase_database/firebase_database.dart';

class Chat {
  final String id;
  final String lastMessageText;
  final String lastMessageSenderId;
  final DateTime lastUpdatedAt;
  final Map<String, bool> users;
  // --- NEW: Field to hold the unread count for each user ---
  final Map<String, int> unreadCount;

  Chat({
    required this.id,
    required this.lastMessageText,
    required this.lastMessageSenderId,
    required this.lastUpdatedAt,
    required this.users,
    required this.unreadCount,
  });

  factory Chat.fromSnapshot(DataSnapshot snapshot) {
    final data = Map<String, dynamic>.from(snapshot.value as Map);
    final lastMessageData = data['lastMessage'] != null
        ? Map<String, dynamic>.from(data['lastMessage'])
        : {};

    return Chat(
      id: snapshot.key ?? '',
      lastMessageText: lastMessageData['text'] ?? 'No messages yet.',
      lastMessageSenderId: lastMessageData['senderId'] ?? '',
      lastUpdatedAt: data['lastUpdatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['lastUpdatedAt'])
          : DateTime(2000),
      users: Map<String, bool>.from(data['users'] ?? {}),
      // Read the unreadCount map, defaulting to an empty map if it doesn't exist
      unreadCount: data['unreadCount'] != null 
          ? Map<String, int>.from(data['unreadCount']) 
          : {},
    );
  }
}
