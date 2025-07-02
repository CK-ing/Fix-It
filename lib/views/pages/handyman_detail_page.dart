import 'dart:async';
import 'package:fixit_app_a186687/models/handyman_services.dart';
import 'package:fixit_app_a186687/views/pages/chat_page.dart';
import 'package:fixit_app_a186687/views/pages/report_issue_page.dart';
import 'package:fixit_app_a186687/views/pages/reviews_page.dart';
import 'package:fixit_app_a186687/views/pages/service_detail_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/reviews.dart';

class HandymanDetailPage extends StatefulWidget {
  final String handymanId;

  const HandymanDetailPage({
    required this.handymanId,
    super.key,
  });

  @override
  State<HandymanDetailPage> createState() => _HandymanDetailPageState();
}

class _HandymanDetailPageState extends State<HandymanDetailPage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // State
  bool _isLoading = true;
  String? _error;

  // Data Holders
  Map<String, dynamic>? _handymanData;
  List<HandymanService> _handymanServices = [];
  List<ReviewViewModel> _reviews = [];
  RatingInfo? _handymanRatingInfo;

  @override
  void initState() {
    super.initState();
    _loadAllHandymanData();
  }

  Future<void> _loadAllHandymanData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _dbRef.child('users').child(widget.handymanId).get(),
        _dbRef.child('services').orderByChild('handymanId').equalTo(widget.handymanId).get(),
        _dbRef.child('reviews').orderByChild('handymanId').equalTo(widget.handymanId).get(),
      ]);

      if (!mounted) return;

      final userSnapshot = results[0];
      if (userSnapshot.exists) {
        _handymanData = Map<String, dynamic>.from(userSnapshot.value as Map);
      } else {
        throw Exception("Handyman profile not found.");
      }

      final servicesSnapshot = results[1];
      if (servicesSnapshot.exists) {
        final servicesData = Map<String, dynamic>.from(servicesSnapshot.value as Map);
        _handymanServices = servicesData.entries
            .map((entry) => HandymanService.fromMap(Map<String, dynamic>.from(entry.value as Map), entry.key))
            .where((service) => service.isActive)
            .toList();
      }

      final reviewsSnapshot = results[2];
      if (reviewsSnapshot.exists) {
        await _processReviews(reviewsSnapshot);
      }

      setState(() => _isLoading = false);

    } catch (e) {
      print("Error loading handyman details: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load handyman profile.";
        });
      }
    }
  }
  
  Future<void> _processReviews(DataSnapshot reviewSnapshot) async {
      final reviewsData = Map<String, dynamic>.from(reviewSnapshot.value as Map);
      final List<Review> tempReviews = [];
      final Set<String> reviewerIds = {};
      
      reviewsData.forEach((key, value) {
        final review = Review.fromSnapshot(reviewSnapshot.child(key));
        tempReviews.add(review);
        reviewerIds.add(review.homeownerId);
      });
      
      if (tempReviews.isNotEmpty) {
        final double average = tempReviews.map((r) => r.rating).reduce((a, b) => a + b) / tempReviews.length;
        _handymanRatingInfo = RatingInfo(averageRating: average, ratingCount: tempReviews.length);
      }

      final Map<String, Map<String, dynamic>> reviewersData = {};
      final reviewerFutures = reviewerIds.map((id) => _dbRef.child('users/$id').get()).toList();
      final reviewerSnapshots = await Future.wait(reviewerFutures);

      for (final snap in reviewerSnapshots) {
        if (snap.exists) {
          reviewersData[snap.key!] = Map<String, dynamic>.from(snap.value as Map);
        }
      }

      final List<ReviewViewModel> viewModels = [];
      for (final review in tempReviews) {
        final reviewerInfo = reviewersData[review.homeownerId];
        viewModels.add(ReviewViewModel(
          review: review,
          reviewerName: reviewerInfo?['name'] ?? 'Anonymous',
          reviewerImageUrl: reviewerInfo?['profileImageUrl'],
        ));
      }
      viewModels.sort((a, b) => b.review.createdAt.compareTo(a.review.createdAt));
      _reviews = viewModels;
  }

  Future<void> _launchUrlHelper(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not launch $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final handymanName = _handymanData?['name'] ?? 'Handyman Profile';
    
    // *** MODIFIED: Replaced CustomScrollView with a standard Scaffold and SingleChildScrollView ***
    return Scaffold(
      appBar: AppBar(
        title: Text(handymanName),
        elevation: 1,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : SingleChildScrollView(
                  child: _buildContent(),
                ),
    );
  }
  
  Widget _buildContent() {
    return Padding(
      // Add padding to the whole content section
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 16),
          _buildActionButtons(),
          const Divider(height: 32, indent: 16, endIndent: 16),
          if (_reviews.isNotEmpty) ...[
            _buildReviewsSection(),
            const Divider(height: 32, indent: 16, endIndent: 16),
          ],
          if (_handymanServices.isNotEmpty) ...[
            _buildServicesSection(),
            const Divider(height: 32, indent: 16, endIndent: 16),
          ],
          _buildReportSection(),
          const SizedBox(height: 40), // Padding at the bottom
        ],
      ),
    );
  }

  // --- MODIFIED: Rebuilt header card to match the new design ---
  Widget _buildHeaderCard() {
    final handymanName = _handymanData?['name'] ?? 'Handyman';
    final establishedYear = _handymanData?['establishedSince'] ?? '';
    int yearsHosting = 0;
    if (establishedYear.isNotEmpty) {
      yearsHosting = DateTime.now().year - (int.tryParse(establishedYear) ?? DateTime.now().year);
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Card(
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Column(
                children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _handymanData?['profileImageUrl'] != null
                      ? NetworkImage(_handymanData!['profileImageUrl'])
                      : null,
                    child: _handymanData?['profileImageUrl'] == null
                      ? const Icon(Icons.person, size: 35, color: Colors.grey)
                      : null,
                  ),
                  const SizedBox(height: 8),
                  Text(handymanName, style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _buildStatRow(
                      _handymanRatingInfo?.ratingCount.toString() ?? '0',
                      'Reviews',
                      Icons.reviews_outlined,
                    ),
                    const Divider(height: 24),
                    _buildStatRow(
                      _handymanRatingInfo?.averageRating.toStringAsFixed(1) ?? 'New',
                      'Rating',
                      Icons.star_rounded,
                    ),
                    const Divider(height: 24),
                    _buildStatRow(
                      '$yearsHosting+',
                      'Years',
                      Icons.calendar_today_outlined,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // --- MODIFIED: Stat row now includes an icon and different formatting for rating ---
  Widget _buildStatRow(String value, String label, [IconData? icon]) {
    final Color iconColor = label == 'Rating' ? Colors.amber.shade700 : Colors.grey.shade700;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) 
          Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildActionButtons() { final phone = _handymanData?['phoneNumber'] as String?; final email = _handymanData?['email'] as String?; return Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Row( children: [ Expanded(child: OutlinedButton.icon( onPressed: (phone != null && phone.isNotEmpty) ? () => _launchUrlHelper('tel:$phone') : null, icon: const Icon(Icons.call_outlined), label: const Text('Call'), )), const SizedBox(width: 12), Expanded(child: OutlinedButton.icon( onPressed: () { final currentUser = _auth.currentUser; if (currentUser == null) return; List<String> ids = [currentUser.uid, widget.handymanId]; ids.sort(); String chatRoomId = ids.join('_'); Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage( chatRoomId: chatRoomId, otherUserId: widget.handymanId, otherUserName: _handymanData?['name'] ?? 'Handyman', otherUserImageUrl: _handymanData?['profileImageUrl'], ))); }, icon: const Icon(Icons.chat_bubble_outline), label: const Text('Chat'), )), const SizedBox(width: 12), Expanded(child: OutlinedButton.icon( onPressed: (email != null && email.isNotEmpty) ? () => _launchUrlHelper('mailto:$email?subject=Enquiry on Service') : null, icon: const Icon(Icons.email_outlined), label: const Text('Email'), )), ], ), ); }
  
  Widget _buildReviewsSection() { return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Row( children: [ Icon(Icons.star_rounded, color: Colors.amber[700], size: 28), const SizedBox(width: 8), Text( _handymanRatingInfo?.averageRating.toStringAsFixed(1) ?? 'New', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), ), const SizedBox(width: 8), if (_reviews.isNotEmpty) Text( '(${_handymanRatingInfo?.ratingCount ?? 0} reviews)', style: const TextStyle(fontSize: 16, color: Colors.grey), ), ], ), ), const SizedBox(height: 16), SizedBox( height: 220, child: ListView.builder( scrollDirection: Axis.horizontal, itemCount: _reviews.length > 5 ? 5 : _reviews.length, padding: const EdgeInsets.symmetric(horizontal: 16), itemBuilder: (context, index) => _buildReviewCard(_reviews[index]), ), ), const SizedBox(height: 16), Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0), child: SizedBox( width: double.infinity, child: OutlinedButton( onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewsPage( serviceId: '', serviceName: "Reviews for ${_handymanData?['name']}", averageRating: _handymanRatingInfo?.averageRating ?? 0, reviews: _reviews, ))); }, child: Text('Show all ${_reviews.length} reviews'), ), ), ), ], ); }
  
  // --- MODIFIED: Added logic to show photo thumbnails and "+more" indicator ---
  Widget _buildReviewCard(ReviewViewModel reviewViewModel) {
    final review = reviewViewModel.review;
    return Container(
      width: MediaQuery.of(context).size.width * 0.8,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar( radius: 20, backgroundColor: Colors.grey[200], backgroundImage: reviewViewModel.reviewerImageUrl != null ? NetworkImage(reviewViewModel.reviewerImageUrl!) : null, child: reviewViewModel.reviewerImageUrl == null ? const Icon(Icons.person, color: Colors.grey) : null, ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reviewViewModel.reviewerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      ...List.generate(review.rating, (i) => Icon(Icons.star, color: Colors.amber[700], size: 16)),
                      ...List.generate(5 - review.rating, (i) => Icon(Icons.star, color: Colors.grey[300], size: 16)),
                    ],
                  )
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          Text( review.comment, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.4), ),
          const Spacer(),
          if (review.reviewPhotoUrls.isNotEmpty)
            Row(
              children: [
                ...List.generate(
                  review.reviewPhotoUrls.length > 3 ? 3 : review.reviewPhotoUrls.length,
                  (index) => Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        review.reviewPhotoUrls[index],
                        height: 60, width: 60, fit: BoxFit.cover,
                        errorBuilder: (c, o, s) => Container(width: 60, height: 60, color: Colors.grey[200], child: const Icon(Icons.error)),
                      ),
                    ),
                  ),
                ),
                if (review.reviewPhotoUrls.length > 3)
                  Container(
                    height: 60, width: 60,
                    decoration: BoxDecoration( borderRadius: BorderRadius.circular(8), color: Colors.black.withOpacity(0.5), ),
                    child: Center(
                      child: Text(
                        '+${review.reviewPhotoUrls.length - 3}',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
  
  Widget _buildServicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            "Services by ${_handymanData?['name']}",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _handymanServices.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final service = _handymanServices[index];
              final serviceRatingInfo = _reviews
                  .where((r) => r.review.serviceId == service.id)
                  .toList();
              
              double avgServiceRating = 0;
              if (serviceRatingInfo.isNotEmpty) {
                avgServiceRating = serviceRatingInfo.map((r) => r.review.rating).reduce((a,b) => a+b) / serviceRatingInfo.length;
              }

              return _buildServiceCard(service, avgServiceRating, serviceRatingInfo.length);
            },
          ),
        )
      ],
    );
  }

  Widget _buildServiceCard(HandymanService service, double avgRating, int ratingCount) {
    return SizedBox(
      width: 200,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceDetailPage(serviceId: service.id))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  color: Colors.grey[200],
                  child: (service.imageUrl != null && service.imageUrl!.isNotEmpty)
                    ? Image.network(service.imageUrl!, fit: BoxFit.cover, errorBuilder: (c, o, s) => const Center(child: Icon(Icons.error_outline)))
                    : const Center(child: Icon(Icons.construction, size: 30, color: Colors.grey)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(service.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('RM ${service.price.toStringAsFixed(2)} (${service.priceType})', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[700]), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (ratingCount > 0)
                        Row(
                          children: [
                            Icon(Icons.star_rounded, color: Colors.amber[700], size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${avgRating.toStringAsFixed(1)} ($ratingCount)',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        )
                      else
                        Text(
                          'New',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildReportSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.flag_outlined, color: Colors.grey),
        title: Text("Report ${_handymanData?['name'] ?? 'this handyman'}"),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ReportIssuePage(
            handymanId: widget.handymanId,
            userRole: 'Homeowner',
          )));
        },
      ),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inDays < 1) return 'Today';
    if (difference.inDays < 7) return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    if (difference.inDays < 30) return '${(difference.inDays / 7).floor()} week${(difference.inDays / 7).floor() > 1 ? 's' : ''} ago';
    if (difference.inDays < 365) return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() > 1 ? 's' : ''} ago';
    return DateFormat('dd/MM/yyyy').format(dateTime);
  }
}

extension StringExtension on String {
    String capitalize() {
      if (isEmpty) return "";
      return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
    }
}
