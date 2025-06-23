import 'dart:async';

import 'package:fixit_app_a186687/models/handyman_services.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../../models/reviews.dart';
import 'book_service_page.dart';
import 'handyman_detail_page.dart';
import 'reviews_page.dart';

class ServiceDetailPage extends StatefulWidget {
  final String serviceId;

  const ServiceDetailPage({required this.serviceId, super.key});

  @override
  State<ServiceDetailPage> createState() => _ServiceDetailPageState();
}

class _ServiceDetailPageState extends State<ServiceDetailPage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Data state
  HandymanService? _serviceModelData;
  Map<String, dynamic>? _handymanData;
  List<MapEntry<String, dynamic>> _relatedServices = [];

  // --- NEW: State for Reviews ---
  List<ReviewViewModel> _reviews = [];
  double _averageRating = 0.0;
  bool _isLoadingReviews = true;
  RatingInfo? _handymanRatingInfo;

  // Loading and error state
  bool _isLoading = true;
  bool _isLoadingRelated = false; // <<< KEPT THIS FEATURE
  String? _error;

  // Favorite state
  bool _isFavorited = false;
  bool _isTogglingFavorite = false;
  StreamSubscription? _favoritesSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenToFavorites();
  }

  @override
  void dispose() {
    _favoritesSubscription?.cancel();
    super.dispose();
  }

  void _listenToFavorites() {
    final user = _auth.currentUser;
    if (user == null) return;
    final favRef = _dbRef.child('users/${user.uid}/favouriteServices/${widget.serviceId}');
    _favoritesSubscription = favRef.onValue.listen((event) {
      if (mounted) {
        setState(() { _isFavorited = event.snapshot.exists && event.snapshot.value == true; });
      }
    });
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; });
    try {
      final serviceSnapshot = await _dbRef.child('services').child(widget.serviceId).get();
      if (!mounted) return;
      if (!serviceSnapshot.exists) throw Exception('Service not found.');

      final serviceDataMap = Map<String, dynamic>.from(serviceSnapshot.value as Map);
      _serviceModelData = HandymanService.fromMap(serviceDataMap, widget.serviceId);

      final handymanId = _serviceModelData?.handymanId;
      final category = _serviceModelData?.category;

      // Fetch all data concurrently for better performance
      await Future.wait([
        if (handymanId != null && handymanId.isNotEmpty)
          _dbRef.child('users').child(handymanId).get().then((snap) {
            if(mounted && snap.exists) {
              _handymanData = Map<String, dynamic>.from(snap.value as Map);
            }
          }),
        _loadReviews(),
        if (category != null && category.isNotEmpty)
          _loadRelatedServices(category),
        if (handymanId != null && handymanId.isNotEmpty)
        _loadHandymanRating(handymanId),
      ]);

      if (mounted) setState(() { _isLoading = false; });
    } catch (e) {
      print("Error loading service details: $e");
      if (mounted) setState(() { _isLoading = false; _error = "Failed to load service details."; });
    }
  }

  // --- NEW: Function to load and process reviews for this service ---
  Future<void> _loadReviews() async {
    if (!mounted) return;
    setState(() => _isLoadingReviews = true);

    try {
      final reviewsQuery = _dbRef.child('reviews').orderByChild('serviceId').equalTo(widget.serviceId);
      final reviewSnapshot = await reviewsQuery.get();

      if (!mounted) return;
      if (!reviewSnapshot.exists) {
        setState(() {
          _reviews = [];
          _averageRating = 0.0;
          _isLoadingReviews = false;
        });
        return;
      }

      final reviewsData = Map<String, dynamic>.from(reviewSnapshot.value as Map);
      final List<Review> tempReviews = [];
      final Set<String> reviewerIds = {};
      
      reviewsData.forEach((key, value) {
        final review = Review.fromSnapshot(reviewSnapshot.child(key));
        tempReviews.add(review);
        reviewerIds.add(review.homeownerId);
      });
      
      if (tempReviews.isNotEmpty) {
        _averageRating = tempReviews.map((r) => r.rating).reduce((a, b) => a + b) / tempReviews.length;
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

      if (mounted) {
        setState(() {
          _reviews = viewModels;
          _isLoadingReviews = false;
        });
      }

    } catch (e) {
      print("Error loading reviews: $e");
      if (mounted) setState(() => _isLoadingReviews = false);
    }
  }

  // --- Handyman Ratings ---
  Future<void> _loadHandymanRating(String handymanId) async {
    try {
      final reviewsQuery = _dbRef.child('reviews').orderByChild('handymanId').equalTo(handymanId);
      final reviewSnapshot = await reviewsQuery.get();

      if (mounted && reviewSnapshot.exists) {
        final reviewsData = Map<String, dynamic>.from(reviewSnapshot.value as Map);
        final ratings = reviewsData.values
            .map((review) => (review as Map)['rating'] as int?)
            .where((rating) => rating != null)
            .cast<int>()
            .toList();

        if (ratings.isNotEmpty) {
          final double average = ratings.reduce((a, b) => a + b) / ratings.length;
          setState(() {
            _handymanRatingInfo = RatingInfo(averageRating: average, ratingCount: ratings.length);
          });
        }
      }
    } catch (e) {
      print("Error loading handyman's overall rating: $e");
    }
  }
  
  Future<void> _loadRelatedServices(String category) async { if (!mounted) return; setState(() { _isLoadingRelated = true; }); try { final query = _dbRef.child('services').orderByChild('category').equalTo(category); final snapshot = await query.get(); List<MapEntry<String, dynamic>> related = []; if (snapshot.exists && snapshot.value != null) { final dynamic snapshotValue = snapshot.value; if (snapshotValue is Map) { final data = Map<String, dynamic>.from(snapshotValue.cast<String, dynamic>()); related = data.entries .map((entry) { try { if (entry.value is Map) { return MapEntry(entry.key, Map<String, dynamic>.from(entry.value as Map)); } else { return null; } } catch (mapError) { return null; } }) .where((entry) => entry != null && entry.key != widget.serviceId) .cast<MapEntry<String, dynamic>>() .take(5).toList(); } } if (mounted) setState(() { _relatedServices = related; }); } catch (e) { print("Error executing related services query: $e"); if (mounted) setState(() { _relatedServices = []; }); } finally { if (mounted) setState(() { _isLoadingRelated = false; }); } }
  Future<void> _toggleFavorite() async { if (_isTogglingFavorite) return; final user = _auth.currentUser; if (user == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to manage favorites.'))); return; } setState(() { _isTogglingFavorite = true; }); final favRef = _dbRef.child('users/${user.uid}/favouriteServices/${widget.serviceId}'); final currentlyFavorited = _isFavorited; try { if (currentlyFavorited) { await favRef.remove(); } else { await favRef.set(true); } if (mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar( content: Text(currentlyFavorited ? 'Removed from favorites.' : 'Added to favorites!'), duration: const Duration(seconds: 2), backgroundColor: currentlyFavorited ? Colors.black87 : Colors.red,),); } } catch (e) { if (mounted) {ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating favorites: ${e.toString()}'))); } print("Error toggling favorite: $e"); } finally { if (mounted) setState(() { _isTogglingFavorite = false; }); } }

  @override
  Widget build(BuildContext context) {
    String appBarTitle = _isLoading ? 'Loading...' : (_serviceModelData?.name ?? 'Service Details');
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar( title: Text(appBarTitle, overflow: TextOverflow.ellipsis), elevation: 0.5, backgroundColor: Theme.of(context).colorScheme.surface, foregroundColor: Theme.of(context).colorScheme.onSurface, actions: [ if (!_isLoading && _serviceModelData != null) IconButton( icon: Icon(_isFavorited ? Icons.favorite : Icons.favorite_border, color: _isFavorited ? Colors.red : null), tooltip: _isFavorited ? 'Remove from Favorites' : 'Add to Favorites', onPressed: _isTogglingFavorite ? null : _toggleFavorite,), const SizedBox(width: 8),], ),
      body: _buildBody(),
      bottomNavigationBar: SafeArea( child: _buildBookingButtonContainer(),)
    );
  }

  Widget _buildBody() {
    if (_isLoading) { return const Center(child: CircularProgressIndicator()); }
    if (_error != null) { return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),)); }
    if (_serviceModelData == null) { return const Center(child: Text('Service data not available.')); }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildServiceImage(),
          Container(color: Theme.of(context).cardColor, padding: const EdgeInsets.all(16.0), margin: const EdgeInsets.only(bottom: 10.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildServiceDetailsSection(), const Divider(height: 24, thickness: 0.5), _buildDescriptionContent(), ],),),
          Container(color: Theme.of(context).cardColor, padding: const EdgeInsets.all(16.0), margin: const EdgeInsets.only(bottom: 10.0), child: _buildHandymanInfoContent(),),
          // *** MODIFIED: The old _buildReviewsContent is replaced by this new section builder ***
          Container(color: Theme.of(context).cardColor, padding: const EdgeInsets.symmetric(vertical: 16.0), margin: const EdgeInsets.only(bottom: 10.0), child: _buildReviewsSection(),),
          Container(
  color: Theme.of(context).cardColor,
  padding: const EdgeInsets.all(16.0),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSectionTitle('Related Services'),
      const SizedBox(height: 12),
      _buildRelatedServicesContent(),
    ],
  ),
),
        ],
      ),
    );
  }
  
  // --- NEW: Main builder for the entire Reviews section ---
  Widget _buildReviewsSection() {
    if (_isLoadingReviews) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(16.0),
        child: CircularProgressIndicator(),
      ));
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _buildSectionTitle('Reviews'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _buildOverallRatingHeader(),
        ),
        const SizedBox(height: 16),
        if (_reviews.isNotEmpty)
          _buildHorizontalReviewList()
        else
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32.0),
            child: Text("No reviews yet.", style: TextStyle(color: Colors.grey)),
          )),
        const SizedBox(height: 16),
        if (_reviews.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildShowAllButton(),
          ),
      ],
    );
  }

  // --- NEW: Helper widgets for the new Reviews UI ---

  Widget _buildOverallRatingHeader() {
    // If there are no reviews, don't show the rating header at all.
    if (_reviews.isEmpty) {
      return const SizedBox.shrink(); // Return an empty widget
    }
    return Row(
      children: [
        Icon(Icons.star_rounded, color: Colors.amber[700], size: 28),
        const SizedBox(width: 8),
        Text(
          _reviews.isEmpty ? 'New' : _averageRating.toStringAsFixed(1),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        if (_reviews.isNotEmpty)
        Text(
          '(${_reviews.length} reviews)',
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildHorizontalReviewList() {
    return SizedBox(
      height: 220, // Adjust height as needed
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _reviews.length > 5 ? 5 : _reviews.length, // Show max 5 reviews
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final reviewViewModel = _reviews[index];
          return _buildReviewCard(reviewViewModel);
        },
      ),
    );
  }

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
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.grey[200],
                backgroundImage: reviewViewModel.reviewerImageUrl != null
                  ? NetworkImage(reviewViewModel.reviewerImageUrl!)
                  : null,
                child: reviewViewModel.reviewerImageUrl == null
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
              ),
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
                      const SizedBox(width: 8),
                      Text(
                        '· ${_formatRelativeTime(review.createdAt)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      )
                    ],
                  )
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Text(
              review.comment,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(height: 1.4),
            ),
          ),
          if (review.reviewPhotoUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  // Build image widgets for up to 3 photos
                  ...List.generate(
                    review.reviewPhotoUrls.length > 3 ? 3 : review.reviewPhotoUrls.length,
                    (index) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          review.reviewPhotoUrls[index],
                          height: 60,
                          width: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (c, o, s) => Container(width: 60, height: 60, color: Colors.grey[200], child: const Icon(Icons.error)),
                        ),
                      ),
                    ),
                  ),
                  // If there are more than 3 photos, show the "+more" indicator
                  if (review.reviewPhotoUrls.length > 3)
                    Container(
                      height: 60,
                      width: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.black.withOpacity(0.5),
                      ),
                      child: Center(
                        child: Text(
                          '+${review.reviewPhotoUrls.length - 3}',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShowAllButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: BorderSide(color: Colors.grey.shade400),
        ),
        onPressed: () {
  // Navigate to your new ReviewsPage, passing the necessary data.
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ReviewsPage(
      serviceId: widget.serviceId,
      reviews: _reviews,
      averageRating: _averageRating,
      serviceName: _serviceModelData?.name ?? 'Service Reviews',
    )),
  );
},
        child: Text(
          'Show all ${_reviews.length} reviews',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays < 1) {
      return 'Today';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks week${weeks > 1 ? 's' : ''} ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else {
      return DateFormat('dd/MM/yyyy').format(dateTime);
    }
  }


  // --- Unchanged Widgets from previous version ---
  Widget _buildServiceImage() { final imageUrl = _serviceModelData?.imageUrl; return Container( height: 250, width: double.infinity, color: Colors.grey[300], child: (imageUrl != null && imageUrl.isNotEmpty) ? Image.network( imageUrl, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 50)),) : const Center(child: Icon(Icons.construction, color: Colors.grey, size: 50)), ); }
  Widget _buildServiceDetailsSection() { return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text( _serviceModelData?.name ?? 'Service Name', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), ), const SizedBox(height: 12), _buildServiceInfoChips(), ], ); }
  Widget _buildServiceInfoChips() { if (_serviceModelData == null) return const SizedBox.shrink(); final price = _serviceModelData!.price; final priceType = _serviceModelData!.priceType; final category = _serviceModelData!.category; final serviceState = _serviceModelData!.state; final serviceDistrict = _serviceModelData!.district; List<Widget> chips = []; chips.add(Chip( avatar: Icon(Icons.attach_money, size: 16, color: Colors.green[800]), label: Text('RM ${price.toStringAsFixed(2)} ${priceType.isNotEmpty ? "($priceType)" : ""}'), backgroundColor: Colors.green.withOpacity(0.1), labelStyle: TextStyle(color: Colors.green[900], fontSize: 13), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), visualDensity: VisualDensity.compact, side: BorderSide.none, )); if (category.isNotEmpty) { chips.add(Chip( avatar: Icon(Icons.category_outlined, size: 16, color: Theme.of(context).colorScheme.primary), label: Text(category), backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3), labelStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontSize: 13), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), visualDensity: VisualDensity.compact, side: BorderSide.none, )); } String locationText = serviceState; if (serviceDistrict != null && serviceDistrict.isNotEmpty) { locationText = '$serviceDistrict, $serviceState'; } if (locationText.isNotEmpty) { chips.add(Chip( avatar: Icon(Icons.location_on_outlined, size: 16, color: Theme.of(context).colorScheme.tertiary), label: Text(locationText), backgroundColor: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.3), labelStyle: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer, fontSize: 13), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), visualDensity: VisualDensity.compact, side: BorderSide.none, )); } return Wrap( spacing: 8.0, runSpacing: 6.0, children: chips, ); }
  Widget _buildDescriptionContent() { final description = _serviceModelData?.description ?? 'No description available.'; return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Description'), const SizedBox(height: 8), Text(description, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant),),], ); }
  Widget _buildHandymanInfoContent() { if (_handymanData == null) { return Row(children: [ Icon(Icons.person_off_outlined, color: Colors.grey[600]), const SizedBox(width: 8), Text('Handyman details unavailable', style: TextStyle(color: Colors.grey[600])),],); } final handymanName = _handymanData?['name'] ?? 'Handyman Name'; final handymanImageUrl = _handymanData?['profileImageUrl'] as String?; final String handymanRatingDisplay = 'N/A'; return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Provided by'), const SizedBox(height: 8), ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: CircleAvatar(radius: 24, backgroundColor: Colors.grey[200], backgroundImage: (handymanImageUrl != null && handymanImageUrl.isNotEmpty) ? NetworkImage(handymanImageUrl) : null, child: (handymanImageUrl == null || handymanImageUrl.isEmpty) ? const Icon(Icons.person, color: Colors.grey, size: 24) : null,), title: Text(handymanName, style: Theme.of(context).textTheme.titleMedium), subtitle: _handymanRatingInfo != null && _handymanRatingInfo!.ratingCount > 0
    ? Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, color: Colors.amber[600], size: 16),
          const SizedBox(width: 4),
          Text(
            'Rating: ${_handymanRatingInfo!.averageRating.toStringAsFixed(1)} (${_handymanRatingInfo!.ratingCount})',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
          ),
        ],
      )
    : Text(
        'No ratings yet',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
      ), trailing: const Icon(Icons.chevron_right, size: 20), onTap: () { final handymanId = _serviceModelData?.handymanId; if (handymanId != null) { Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HandymanDetailPage(handymanId: handymanId)),
    );}},),],); }
  Widget _buildRelatedServicesContent() { if (_isLoadingRelated) { return const Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Center(child: CircularProgressIndicator())); } if (_relatedServices.isEmpty) { return const Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Center(child: Text('No related services found.'))); } return ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _relatedServices.length, itemBuilder: (context, index) { final entry = _relatedServices[index]; final relatedServiceId = entry.key; final relatedServiceData = entry.value; final imageUrl = relatedServiceData['imageUrl'] as String?; final name = relatedServiceData['name'] ?? 'Service'; final price = (relatedServiceData['price'] as num?)?.toDouble() ?? 0.0; final priceType = relatedServiceData['priceType'] ?? ''; return ListTile(contentPadding: const EdgeInsets.symmetric(vertical: 6.0), dense: true, leading: ClipRRect(borderRadius: BorderRadius.circular(8.0), child: Container(width: 60, height: 60, color: Colors.grey[200], child: (imageUrl != null && imageUrl.isNotEmpty) ? Image.network(imageUrl, fit: BoxFit.cover) : const Icon(Icons.construction, size: 24, color: Colors.grey),),), title: Text(name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis,), subtitle: Text('RM ${price.toStringAsFixed(2)} ${priceType.isNotEmpty ? "($priceType)" : ""}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[800]), maxLines: 1, overflow: TextOverflow.ellipsis,), trailing: const Icon(Icons.chevron_right, size: 20), onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => ServiceDetailPage(serviceId: relatedServiceId),),);},);},); }
  Widget _buildSectionTitle(String title) { return Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),),); }
  Widget _buildBookingButtonContainer() { if (_isLoading || _serviceModelData == null) { return const SizedBox.shrink(); } return Container( padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0), decoration: BoxDecoration( color: Theme.of(context).colorScheme.surface, boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, -2),)],), child: ElevatedButton.icon( icon: const Icon(Icons.calendar_month_outlined), label: const Text('Check Availability & Book'), style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 14), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary,), onPressed: () { final String? currentHandymanId = _serviceModelData?.handymanId; if (currentHandymanId != null && currentHandymanId.isNotEmpty) { Navigator.push( context, MaterialPageRoute( builder: (context) => BookServicePage( serviceId: widget.serviceId, handymanId: currentHandymanId,),),); } else { ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Cannot proceed: Handyman details are missing for this service.')),); print('Error: Handyman ID is null or empty for service ${widget.serviceId}'); } } ) ); }


}
