import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// A simple model for a chat message
class AiChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool showFeedbackChips;

  AiChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.showFeedbackChips = false,
  });
}

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  User? _currentUser;

  // State
  final List<AiChatMessage> _messages = [];
  bool _isAiTyping = false;
  String? _userRole;
  String? _userName;
  bool _showInitialQuickReplies = true;

  final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? "API_KEY_NOT_FOUND"; 

  // --- MODIFIED: More comprehensive quick replies ---
  final Map<String, List<String>> _quickReplies = {
    'Homeowner': [
      'What is the status of my bookings?',
      'Do I have any outstanding payments?',
      'Do I have any quotes to review?',
      'How do I report an issue?',
    ],
    'Handyman': [
      'What are my pending jobs?',
      'What are my active bookings?',
      'How do I check my ratings?',
      'When do I get paid?',
    ],
  };

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    if (_currentUser != null) {
      final userSnapshot = await _dbRef.child('users/${_currentUser!.uid}').get();
      if (mounted && userSnapshot.exists && userSnapshot.value is Map) {
        final userData = Map<String, dynamic>.from(userSnapshot.value as Map);
        _userRole = userData['role'] as String?;
        _userName = userData['name'] as String?;
      }
    }
    if (!mounted) return;
    setState(() {
      final name = _userName ?? 'there';
      _messages.add(AiChatMessage(
        text: "Hello, $name! I'm the Fix It Assistant. How can I help you today?",
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage({String? text, bool isFeedback = false}) async {
    final messageText = text ?? _messageController.text.trim();
    if (messageText.isEmpty) return;

    setState(() {
      _messages.add(AiChatMessage(text: messageText, isUser: true, timestamp: DateTime.now()));
      _isAiTyping = true;
      _showInitialQuickReplies = false;
    });
    _scrollToBottom();
    _messageController.clear();

    if (isFeedback) {
      _handleFeedback(messageText);
      return;
    }

    try {
      final aiResponse = await _getGeminiResponse(messageText);
      setState(() {
        _isAiTyping = false;
        _messages.add(AiChatMessage(text: aiResponse, isUser: false, timestamp: DateTime.now(), showFeedbackChips: true));
      });
      _scrollToBottom();
    } catch (e) {
      print("Error getting Gemini response: $e");
      setState(() {
        _isAiTyping = false;
        _messages.add(AiChatMessage(text: "Sorry, I'm having trouble connecting right now. Please try again later.", isUser: false, timestamp: DateTime.now()));
      });
       _scrollToBottom();
    }
  }

  void _handleFeedback(String feedback) {
     setState(() {
        _isAiTyping = false;
        if (feedback == "✅ Yes, thanks!") {
           _messages.add(AiChatMessage(text: "You're welcome! Is there anything else I can help you with?", isUser: false, timestamp: DateTime.now()));
        } else {
           _messages.add(AiChatMessage(text: "I'm sorry I couldn't help. Please try rephrasing your question, or select one of the common topics below.", isUser: false, timestamp: DateTime.now()));
           _showInitialQuickReplies = true;
        }
     });
     _scrollToBottom();
  }

  // --- MODIFIED: This function is now much more powerful and context-aware ---
  Future<String> _getGeminiResponse(String userMessage) async {
    if (_currentUser == null) return "Sorry, I can't help you without knowing who you are.";

    String contextualData = "No specific real-time data was requested.";
    String roleBasedPrompt = "";
    final queryField = _userRole == 'Handyman' ? 'handymanId' : 'homeownerId';
    final lowerCaseMessage = userMessage.toLowerCase();
    
    // --- Fetch and format contextual data based on keywords and user role ---
    if (_userRole == 'Homeowner') {
      roleBasedPrompt = """
        **FAQs for Homeowners:**
        - How to book: You can find a service on the homepage or search for one. View its details, and then tap the 'Book Now' button to select a date and time.
        - How to pay: A 'Pay Now' button appears on the booking details page after the job's status is 'Ongoing'. We currently accept Cash directly to the handyman upon service completion.
        - How to see receipts: You can view and print a receipt from the detail page of any 'Completed' booking in your booking history.
        - How do I request a custom job: Go to handyman profile page via the booking details or service details page, view their profile, and tap 'Request Custom Service'. Describe your needs and budget, and the handyman will send you a quote.
        - How do I accept a quote?: When a handyman sends a quote, you'll get a notification. You can view it from your 'My Custom Requests' page (in your Profile). If you like the price, you can tap 'Accept & Schedule' to finalize the booking.
        - Cancelling a booking: Yes, you can cancel a pending booking from its detail page. Please note that cancellation policies may apply for jobs that have already been accepted by the handyman.
        - Past bookings: You can view all past bookings in the 'History' tab on your Bookings page.
        - How do I report an issue?: If you have a problem with a booking or a handyman, you can use the 'Report Issue' button found on the booking detail page or the handyman's profile page. Our support team will investigate.
        - Handyman no-show: If a handyman doesn't arrive, please try contacting them via the in-app chat first. If you get no response after a reasonable time, you can report the issue from the booking detail page so our team can assist.
        - How do I review a service: After a booking is 'Completed', a 'Rate Service' button will appear on the booking detail page. Your feedback is valuable to the community!
      """;
      if (lowerCaseMessage.contains('booking') || lowerCaseMessage.contains('status')) {
        final snapshot = await _dbRef.child('bookings').orderByChild(queryField).equalTo(_currentUser!.uid).get();
        if (snapshot.exists) {
          String bookingsInfo = "Here is the user's booking summary:\n";
          for (var child in snapshot.children) {
            final map = child.value as Map<dynamic, dynamic>;
            bookingsInfo += "- Job '${map['serviceName']}' is currently '${map['status']}'.\n";
          }
          contextualData = bookingsInfo;
        } else {
          contextualData = "The user currently has no bookings.";
        }
      } else if (lowerCaseMessage.contains('quote') || lowerCaseMessage.contains('custom')) {
          final snapshot = await _dbRef.child('custom_requests').orderByChild(queryField).equalTo(_currentUser!.uid).get();
          if (snapshot.exists) {
            String quotesInfo = "Here is the user's quote summary:\n";
            for (var child in snapshot.children) {
              final map = child.value as Map<dynamic, dynamic>;
              if (map['status'] == 'Quoted') {
                 final price = (map['quotePrice'] as num?)?.toDouble() ?? 0.0;
                 quotesInfo += "- You have a quote of RM${price.toStringAsFixed(2)} for '${map['title']}' waiting for your review.\n";
              }
            }
            contextualData = quotesInfo.isEmpty ? "The user has no active quotes to review." : quotesInfo;
          } else {
            contextualData = "The user has no custom requests.";
          }
      }
      else if (lowerCaseMessage.contains('payment') || lowerCaseMessage.contains('outstanding')) {
          final snapshot = await _dbRef.child('bookings').orderByChild(queryField).equalTo(_currentUser!.uid).get();
          if (snapshot.exists) {
            String paymentInfo = "Here is the user's outstanding payment summary:\n";
            for (var child in snapshot.children) {
              final map = child.value as Map<dynamic, dynamic>;
              if (map['status'] == 'Ongoing') {
                 paymentInfo += "- You have an outstanding payment of RM${(map['total']/100).toStringAsFixed(2)} for the job: '${map['serviceName']}'.\n";
              }
            }
            contextualData = paymentInfo == "Here is the user's outstanding payment summary:\n" ? "The user has no outstanding payments." : paymentInfo;
          } else {
            contextualData = "The user has no bookings, so no outstanding payments.";
          }
      }
    } 
    else if (_userRole == 'Handyman') {
      roleBasedPrompt = """
        **FAQs for Handymen:**
        - How do I list a new service: Go to your Home page and tap the '+' floating button to open the 'Add New Service' page. You'll need to provide a name, category, price, and at least one photo.
        - How to get paid: You will receive a notification after the homeowner has completed the payment through the app. Payouts are then processed according to the Fix It terms of service. You can track your total revenue on the 'Statistics' page.
        - How to get more bookings: The best way is to provide excellent service to get good reviews and high ratings. A complete profile with a good description and clear photos also helps. Responding quickly to custom job requests is also a great way to win new customers.
        - How do I view my reviews and ratings: You can see your overall rating on your Statistics page. To read individual comments from customers, go to your 'Profile' page and select the 'My Reviews' option.
        - What's the difference between a 'Booking' and a 'Job Request': 'Bookings' are for your standard, listed services with a fixed or hourly price. 'Job Requests' are for custom work that a homeowner has specifically requested from you. You need to provide a quote for a job request before it can become a booking.
        - How to update availability: You can update your availability status in your profile settings. You can also manage your schedule by accepting or declining jobs.
        - Custom job requests: New requests appear in the 'Pending' tab of your 'Job Requests' page. Tap on a request to see all the details and photos provided by the homeowner. From there, you can either 'Decline' the request or 'Submit Quote' with your proposed price.
        - De-listing a service: From your home page, tap on the service you want to remove. This will take you to the 'Update Service' page where you will find a 'Delete' option. This is a "soft delete," which means it will be hidden from homeowners but your past booking records for it will be preserved.
        - What happens if a customer cancels: You will receive a notification if a customer cancels a booking. The booking will then be moved to your 'History' tab for your records.
        - Can I cancel an accepted job: Yes, you can cancel from the booking detail page, but please do so only when necessary as this affects your reliability rating. The homeowner will be notified immediately.
      """;
      if (lowerCaseMessage.contains('job') || lowerCaseMessage.contains('request') || lowerCaseMessage.contains('custom')) {
         final snapshot = await _dbRef.child('custom_requests').orderByChild(queryField).equalTo(_currentUser!.uid).get();
          if (snapshot.exists) {
            String requestsInfo = "Here is the user's custom request summary:\n";
            for (var child in snapshot.children) {
              final map = child.value as Map<dynamic, dynamic>;
              if(map['status'] == 'Pending') {
                 requestsInfo += "- You have a new request for '${map['title']}' that needs a quote.\n";
              }
            }
            contextualData = requestsInfo.isEmpty ? "The user has no new pending custom requests." : requestsInfo;
          } else {
            contextualData = "The user has no custom requests.";
          }
      } else if (lowerCaseMessage.contains('booking')) {
          final snapshot = await _dbRef.child('bookings').orderByChild(queryField).equalTo(_currentUser!.uid).get();
          if (snapshot.exists) {
            String bookingInfo = "Here is the handyman's booking summary:\n";
            for (var child in snapshot.children) {
              final map = child.value as Map<dynamic, dynamic>;
              bookingInfo += "- Booking for '${map['serviceName']}' has status: ${map['status']}.\n";
            }
            contextualData = bookingInfo;
          } else {
            contextualData = "The user has no bookings.";
          }
      } else if (lowerCaseMessage.contains('service')) {
          final snapshot = await _dbRef.child('services').orderByChild(queryField).equalTo(_currentUser!.uid).get();
          if (snapshot.exists) {
            String serviceInfo = "Here are the user's active services:\n";
            for (var child in snapshot.children) {
              final map = child.value as Map<dynamic, dynamic>;
              if (map['isActive'] == true) {
                serviceInfo += "- ${map['name']}\n";
              }
            }
            contextualData = serviceInfo;
          } else {
            contextualData = "The user is not offering any services.";
          }
      }
       else if (lowerCaseMessage.contains('rating') || lowerCaseMessage.contains('review')) {
          final snapshot = await _dbRef.child('reviews').orderByChild(queryField).equalTo(_currentUser!.uid).get();
          if (snapshot.exists) {
             final reviews = (snapshot.value as Map<dynamic, dynamic>).values.toList();
             final avgRating = reviews.map((r) => r['rating'] as int).reduce((a, b) => a + b) / reviews.length;
             contextualData = "The user's current average rating is ${avgRating.toStringAsFixed(2)} based on ${reviews.length} reviews.";
          } else {
            contextualData = "The user has not received any reviews yet.";
          }
      }
    }
    
    final fullPrompt = """
    You are the Fix It Assistant, a friendly and helpful AI for a home services app in Malaysia. The user,s name is: ${_userName ?? 'Unknown'}. The user's role is: ${_userRole ?? 'Unknown'}.
    Your goal is to answer user questions clearly, concisely, and in a conversational tone based ONLY on the information provided.
    Use the provided real-time data to give personalized answers. If the data says there is no relevant information, state that clearly.
    After every response, ask if the user’s issue is resolved.
    
    $roleBasedPrompt

    **Here is the user's current data from the database:**
    $contextualData

    **Now, please answer the following user question:**
    $userMessage
    """;

    final apiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_apiKey';
    
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [{'parts': [{'text': fullPrompt}]}]
      }),
    );

    if (response.statusCode == 200) {
      final responseBody = jsonDecode(response.body);
      return responseBody['candidates'][0]['content']['parts'][0]['text'];
    } else {
      throw Exception('Failed to get response from Gemini API: ${response.body}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: AssetImage("assets/images/ai_avatar.jpg"),
            ),
            SizedBox(width: 12),
            Text('Fix It Assistant'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          if (_isAiTyping) _buildTypingIndicator(),
          if (_showInitialQuickReplies) _buildQuickReplies(),
          _buildMessageComposer(),
        ],
      ),
    );
  }
  
  Widget _buildQuickReplies() {
    final replies = _quickReplies[_userRole] ?? [];
    if (replies.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: replies.map((reply) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ActionChip(
              label: Text(reply),
              onPressed: () => _sendMessage(text: reply),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMessageBubble(AiChatMessage message) {
    final isMe = message.isUser;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Card(
        color: isMe ? Theme.of(context).primaryColor : Theme.of(context).cardColor,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message.text, style: TextStyle(color: isMe ? Colors.white : null)),
              if (message.showFeedbackChips) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ActionChip(label: const Text('✅ Yes, thanks!'), onPressed: () => _sendMessage(text: '✅ Yes, thanks!', isFeedback: true)),
                    const SizedBox(width: 8),
                    ActionChip(label: const Text('❌ No, I need more help'), onPressed: () => _sendMessage(text: '❌ No, I need more help', isFeedback: true)),
                  ],
                )
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SizedBox(width: 25, height: 25, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey)),
        ),
      ),
    );
  }

  Widget _buildMessageComposer() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ask a question...',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            IconButton(
              icon: Icon(Icons.send, color: Theme.of(context).primaryColor),
              onPressed: _isAiTyping ? null : _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}
