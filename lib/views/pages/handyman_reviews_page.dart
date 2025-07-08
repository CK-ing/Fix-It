import 'dart:async';
import 'package:fixit_app_a186687/models/handyman_services.dart';
import 'package:fixit_app_a186687/views/pages/service_detail_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/reviews.dart';

// A local view model specific to this page's needs
class HandymanReviewViewModel {
  final Review review;
  final String serviceName;
  final String homeownerName;
  final String? homeownerImageUrl;

  HandymanReviewViewModel({
    required this.review,
    required this.serviceName,
    required this.homeownerName,
    this.homeownerImageUrl,
  });
}

enum ReviewSortOption { mostRecent, highestRated, lowestRated }

class HandymanReviewsPage extends StatefulWidget {
  const HandymanReviewsPage({super.key});

  @override
  State<HandymanReviewsPage> createState() => _HandymanReviewsPageState();
}

class _HandymanReviewsPageState extends State<HandymanReviewsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  User? _currentUser;

  // State
  bool _isLoading = true;
  String? _error;
  List<HandymanReviewViewModel> _allReviews = [];
  List<HandymanReviewViewModel> _filteredReviews = [];
  List<HandymanService> _handymanServices = [];
  
  // Filter & Sort State
  String? _selectedServiceFilter;
  ReviewSortOption _currentSortOption = ReviewSortOption.mostRecent;

  // Subscriptions
  StreamSubscription? _reviewsSubscription;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _loadAllData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _reviewsSubscription?.cancel();
    super.dispose();
  }
  
  Future<void> _loadAllData() async {
    if (_currentUser == null) return;
    final handymanId = _currentUser!.uid;

    try {
      final results = await Future.wait([
        _dbRef.child('reviews').orderByChild('handymanId').equalTo(handymanId).get(),
        _dbRef.child('bookings').orderByChild('handymanId').equalTo(handymanId).get(),
        _dbRef.child('services').orderByChild('handymanId').equalTo(handymanId).get(),
      ]);

      if (!mounted) return;

      final reviewsSnapshot = results[0];
      final bookingsSnapshot = results[1];
      final servicesSnapshot = results[2];

      if (!reviewsSnapshot.exists) {
        setState(() { _isLoading = false; });
        return;
      }

      final reviewsData = Map<String, dynamic>.from(reviewsSnapshot.value as Map);
      final bookingIdToNameMap = <String, String>{};
      if (bookingsSnapshot.exists) {
        final bookingsData = Map<String, dynamic>.from(bookingsSnapshot.value as Map);
        bookingsData.forEach((key, value) {
          bookingIdToNameMap[key] = value['serviceName'] as String;
        });
      }
      
      final serviceIdToNameMap = <String, String>{};
      if (servicesSnapshot.exists) {
         final servicesData = Map<String, dynamic>.from(servicesSnapshot.value as Map);
         servicesData.forEach((key, value) {
            final service = HandymanService.fromMap(Map<String, dynamic>.from(value as Map), key);
            if(service.isActive) {
              _handymanServices.add(service);
              serviceIdToNameMap[key] = service.name;
            }
         });
         _handymanServices.sort((a,b) => a.name.compareTo(b.name));
      }

      final homeownerIds = reviewsData.values.map((r) => r['homeownerId'] as String).toSet();
      final homeownerFutures = homeownerIds.map((id) => _dbRef.child('users/$id').get()).toList();
      final homeownerSnapshots = await Future.wait(homeownerFutures);
      final homeownerDetailsMap = {
        for (var snap in homeownerSnapshots) 
          if(snap.exists) snap.key: Map<String, dynamic>.from(snap.value as Map)
      };

      final List<HandymanReviewViewModel> viewModels = [];
      for (var entry in reviewsData.entries) {
        final review = Review.fromSnapshot(reviewsSnapshot.child(entry.key));
        final homeownerDetails = homeownerDetailsMap[review.homeownerId];
        
        String serviceName = "Custom Job";
        if (review.serviceId.isNotEmpty && serviceIdToNameMap.containsKey(review.serviceId)) {
          serviceName = serviceIdToNameMap[review.serviceId]!;
        } else if (bookingIdToNameMap.containsKey(review.bookingId)) {
          serviceName = bookingIdToNameMap[review.bookingId]!;
        }

        viewModels.add(HandymanReviewViewModel(
          review: review,
          serviceName: serviceName,
          homeownerName: homeownerDetails?['name'] ?? 'Anonymous',
          homeownerImageUrl: homeownerDetails?['profileImageUrl'],
        ));
      }
      
      setState(() {
        _allReviews = viewModels;
        _applyFiltersAndSort();
        _isLoading = false;
      });

    } catch (e) {
      print("Error loading reviews page data: $e");
      if (mounted) setState(() { _isLoading = false; _error = "Failed to load reviews."; });
    }
  }

  void _applyFiltersAndSort() {
    List<HandymanReviewViewModel> tempReviews = List.from(_allReviews);

    if (_selectedServiceFilter != null) {
      tempReviews = tempReviews.where((vm) => vm.review.serviceId == _selectedServiceFilter).toList();
    }

    switch (_currentSortOption) {
      case ReviewSortOption.mostRecent:
        tempReviews.sort((a, b) => b.review.createdAt.compareTo(a.review.createdAt));
        break;
      case ReviewSortOption.highestRated:
        tempReviews.sort((a, b) => b.review.rating.compareTo(a.review.rating));
        break;
      case ReviewSortOption.lowestRated:
        tempReviews.sort((a, b) => a.review.rating.compareTo(b.review.rating));
        break;
    }

    setState(() {
      _filteredReviews = tempReviews;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reviews'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _buildBody(),
      ),
    );
  }
  
  Widget _buildBody() {
    if (_allReviews.isEmpty && !_isLoading) {
      return const Center(child: Text("You haven't received any reviews yet."));
    }
    
    return Column(
      children: [
        _buildHeader(),
        _buildFilterBar(),
        const Divider(height: 1),
        Expanded(
          child: _filteredReviews.isEmpty
              ? const Center(child: Text("No reviews match your filter."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _filteredReviews.length,
                  itemBuilder: (context, index) {
                    return _buildReviewCard(_filteredReviews[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final double avgRating = _allReviews.isNotEmpty ? _allReviews.map((r) => r.review.rating).reduce((a, b) => a + b) / _allReviews.length : 0.0;
    final int recommendedCount = _allReviews.where((r) => r.review.recommended).length;
    final double recommendationRate = _allReviews.isNotEmpty ? (recommendedCount / _allReviews.length) * 100 : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildHeaderStat(avgRating.toStringAsFixed(1), 'Overall Rating', Icons.star_rounded),
          _buildHeaderStat('${_allReviews.length}', 'Total Reviews', Icons.reviews_outlined),
          _buildHeaderStat('${recommendationRate.toStringAsFixed(0)}%', 'Recommended', Icons.thumb_up_alt_outlined),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Theme.of(context).primaryColor, size: 28),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedServiceFilter,
              isExpanded: true,
              hint: const Text('All Services'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.filter_list),
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('All Services')),
                ..._handymanServices.map((service) {
                  return DropdownMenuItem<String>(value: service.id, child: Text(service.name, overflow: TextOverflow.ellipsis));
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedServiceFilter = value;
                  _applyFiltersAndSort();
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<ReviewSortOption>(
            onSelected: (option) {
              setState(() {
                _currentSortOption = option;
                _applyFiltersAndSort();
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: ReviewSortOption.mostRecent, child: Text('Sort by: Most Recent')),
              const PopupMenuItem(value: ReviewSortOption.highestRated, child: Text('Sort by: Highest Rating')),
              const PopupMenuItem(value: ReviewSortOption.lowestRated, child: Text('Sort by: Lowest Rating')),
            ],
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(HandymanReviewViewModel viewModel) {
    final review = viewModel.review;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(viewModel.serviceName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 24,
                backgroundImage: viewModel.homeownerImageUrl != null ? NetworkImage(viewModel.homeownerImageUrl!) : null,
              ),
              title: Text(viewModel.homeownerName),
              subtitle: Text(DateFormat.yMMMd().format(review.createdAt), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Star ratings
                ...List.generate(review.rating, (i) => Icon(Icons.star, color: Colors.amber[700], size: 18)),
                ...List.generate(5 - review.rating, (i) => Icon(Icons.star_border, color: Colors.amber[700], size: 18)),
                
                const SizedBox(width: 12),
                
                // Thumbs up/down icon and text
                Icon(
                  review.recommended ? Icons.thumb_up_alt_rounded : Icons.thumb_down_alt_rounded,
                  color: review.recommended ? Colors.green : Colors.red,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  review.recommended ? 'Recommended' : 'Not Recommended',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
            if (review.comment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Text(review.comment, style: const TextStyle(height: 1.4)),
              ),
            // --- NEW: Photo gallery is now added here ---
            if (review.reviewPhotoUrls.isNotEmpty)
              _buildReviewPhotos(review.reviewPhotoUrls),
          ],
        ),
      ),
    );
  }
  
  // --- NEW: Helper widget to build the photo gallery ---
  Widget _buildReviewPhotos(List<String> photoUrls) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: SizedBox(
        height: 80,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: photoUrls.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => _viewPhotoFullScreen(photoUrls[index]),
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    photoUrls[index],
                    height: 80,
                    width: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (c, o, s) => Container(
                      width: 80, height: 80, color: Colors.grey[200],
                      child: const Icon(Icons.error, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- NEW: Helper function to show photos full-screen ---
  void _viewPhotoFullScreen(String imageUrl) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: InteractiveViewer(
            panEnabled: false,
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 4,
            child: Image.network(imageUrl),
          ),
        ),
      ),
    ));
  }
}
