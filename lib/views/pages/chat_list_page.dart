import 'dart:async';
import 'package:fixit_app_a186687/models/chat.dart';
import 'package:fixit_app_a186687/views/pages/chat_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// A local view model to combine chat data with the other user's details
class ChatListItemViewModel {
  final Chat chat;
  final String otherUserName;
  final String? otherUserImageUrl;

  ChatListItemViewModel({
    required this.chat,
    required this.otherUserName,
    this.otherUserImageUrl,
  });
}

enum ChatFilter { all, unread }

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  User? _currentUser;

  StreamSubscription? _chatsSubscription;
  List<ChatListItemViewModel> _allChats = [];
  List<ChatListItemViewModel> _filteredChats = [];
  bool _isLoading = true;
  ChatFilter _currentFilter = ChatFilter.all;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _listenForChats();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    super.dispose();
  }

  void _listenForChats() {
    final query = _dbRef.child('chats').orderByChild('users/${_currentUser!.uid}').equalTo(true);

    _chatsSubscription = query.onValue.listen((event) async {
      if (!mounted) return;
      if (!event.snapshot.exists) {
        setState(() {
          _allChats = [];
          _applyFilter();
          _isLoading = false;
        });
        return;
      }

      final chatsData = Map<String, dynamic>.from(event.snapshot.value as Map);
      final List<Chat> tempChats = [];
      final Set<String> otherUserIds = {};

      chatsData.forEach((key, value) {
        final chat = Chat.fromSnapshot(event.snapshot.child(key));
        tempChats.add(chat);
        // Find the other user's ID in the chat
        final otherId = chat.users.keys.firstWhere((id) => id != _currentUser!.uid, orElse: () => '');
        if (otherId.isNotEmpty) {
          otherUserIds.add(otherId);
        }
      });

      // Fetch details for all the other users
      final Map<String, Map<String, dynamic>> usersData = {};
      if (otherUserIds.isNotEmpty) {
        final userFutures = otherUserIds.map((id) => _dbRef.child('users/$id').get()).toList();
        final userSnapshots = await Future.wait(userFutures);
        if (!mounted) return; //check again here
        for (final snap in userSnapshots) {
          if (snap.exists) {
            usersData[snap.key!] = Map<String, dynamic>.from(snap.value as Map);
          }
        }
      }

      // Combine chat data with user data
      final List<ChatListItemViewModel> viewModels = [];
      for (final chat in tempChats) {
        final otherId = chat.users.keys.firstWhere((id) => id != _currentUser!.uid, orElse: () => '');
        if (otherId.isNotEmpty) {
          final userInfo = usersData[otherId];
          viewModels.add(ChatListItemViewModel(
            chat: chat,
            otherUserName: userInfo?['name'] ?? 'Unknown User',
            otherUserImageUrl: userInfo?['profileImageUrl'],
          ));
        }
      }
      
      viewModels.sort((a, b) => b.chat.lastUpdatedAt.compareTo(a.chat.lastUpdatedAt));
      if (!mounted) return; // final check
      setState(() {
        _allChats = viewModels;
        _applyFilter();
        _isLoading = false;
      });
    },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error loading chats: $error"),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }
  
  void _applyFilter() {
    if (_currentFilter == ChatFilter.unread) {
      _filteredChats = _allChats.where((vm) {
        final unreadCount = vm.chat.unreadCount[_currentUser!.uid] ?? 0;
        return unreadCount > 0;
      }).toList();
    } else {
      _filteredChats = List.from(_allChats);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilterChips(),
                Expanded(child: _buildChatList()),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: Navigate to AI Chatbot page
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AI Assistant coming soon!'))
          );
        },
        child: const Icon(Icons.support_agent_outlined),
        tooltip: 'AI Assistant',
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          FilterChip(
            label: const Text('All'),
            selected: _currentFilter == ChatFilter.all,
            onSelected: (selected) {
              setState(() {
                _currentFilter = ChatFilter.all;
                _applyFilter();
              });
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Unread'),
            selected: _currentFilter == ChatFilter.unread,
            onSelected: (selected) {
              setState(() {
                _currentFilter = ChatFilter.unread;
                _applyFilter();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    if (_filteredChats.isEmpty) {
      return Center(
        child: Text(_currentFilter == ChatFilter.unread 
          ? 'No unread messages.' 
          : 'You have no conversations yet.'),
      );
    }
    return ListView.builder(
      itemCount: _filteredChats.length,
      itemBuilder: (context, index) {
        final chatViewModel = _filteredChats[index];
        return _buildChatListItem(chatViewModel);
      },
    );
  }

  Widget _buildChatListItem(ChatListItemViewModel viewModel) {
    final chat = viewModel.chat;
    final unreadCount = chat.unreadCount[_currentUser!.uid] ?? 0;
    final bool hasUnread = unreadCount > 0;

    return ListTile(
      leading: CircleAvatar(
        radius: 28,
        backgroundImage: viewModel.otherUserImageUrl != null
            ? NetworkImage(viewModel.otherUserImageUrl!)
            : null,
        child: viewModel.otherUserImageUrl == null ? const Icon(Icons.person) : null,
      ),
      title: Text(
        viewModel.otherUserName,
        style: TextStyle(fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal),
      ),
      subtitle: Text(
        chat.lastMessageText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: hasUnread ? Theme.of(context).primaryColor : Colors.grey),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            DateFormat.jm().format(chat.lastUpdatedAt),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            CircleAvatar(
              radius: 10,
              backgroundColor: Theme.of(context).primaryColor,
              child: Text(
                unreadCount.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            )
          ]
        ],
      ),
      onTap: () {
        final otherUserId = chat.users.keys.firstWhere((id) => id != _currentUser!.uid);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ChatPage(
            chatRoomId: chat.id,
            otherUserId: otherUserId,
            otherUserName: viewModel.otherUserName,
            otherUserImageUrl: viewModel.otherUserImageUrl,
          )),
        );
      },
    );
  }
}
