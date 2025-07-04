import 'dart:async';
import 'package:fixit_app_a186687/models/handyman_services.dart';
import 'package:fixit_app_a186687/views/pages/service_detail_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../models/reviews.dart';

class FavouritesPage extends StatefulWidget {
  const FavouritesPage({super.key});

  @override
  State<FavouritesPage> createState() => _FavouritesPageState();
}

class _FavouritesPageState extends State<FavouritesPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  User? _currentUser;

  // State
  bool _isLoading = true;
  String? _error;
  List<HandymanService> _favouriteServices = [];
  Map<String, RatingInfo> _ratingsMap = {};

  // Subscriptions
  StreamSubscription? _favouritesSubscription;
  StreamSubscription? _reviewsSubscription;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _listenForFavourites();
      _listenForReviews();
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _favouritesSubscription?.cancel();
    _reviewsSubscription?.cancel();
    super.dispose();
  }
  
  void _listenForFavourites() {
    if (_currentUser == null) return;

    final favsRef = _dbRef.child('users/${_currentUser!.uid}/favouriteServices');
    _favouritesSubscription = favsRef.onValue.listen((event) async {
      if (!mounted) return;

      if (!event.snapshot.exists) {
        setState(() {
          _favouriteServices = [];
          _isLoading = false;
        });
        return;
      }

      final favsData = Map<String, dynamic>.from(event.snapshot.value as Map);
      final serviceIds = favsData.keys.toList();

      if (serviceIds.isEmpty) {
        setState(() {
          _favouriteServices = [];
          _isLoading = false;
        });
        return;
      }
      
      // Fetch details for all favorited services
      try {
        final serviceFutures = serviceIds.map((id) => _dbRef.child('services/$id').get()).toList();
        final serviceSnapshots = await Future.wait(serviceFutures);

        if (!mounted) return;

        final List<HandymanService> loadedServices = [];
        for (var snapshot in serviceSnapshots) {
          if (snapshot.exists) {
            final service = HandymanService.fromMap(Map<String, dynamic>.from(snapshot.value as Map), snapshot.key!);
            // Only show active services in favorites
            if(service.isActive) {
              loadedServices.add(service);
            }
          }
        }
        
        loadedServices.sort((a,b) => a.name.compareTo(b.name));

        setState(() {
          _favouriteServices = loadedServices;
          _isLoading = false;
        });

      } catch (e) {
        print("Error fetching favorite services: $e");
        if(mounted) {
          setState(() {
            _error = "Failed to load favorites.";
            _isLoading = false;
          });
        }
      }
    });
  }
  
  void _listenForReviews() {
    _reviewsSubscription = _dbRef.child('reviews').onValue.listen((event) {
      if (!mounted || !event.snapshot.exists) return;
      
      Map<String, RatingInfo> ratings = {};
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      Map<String, List<int>> tempRatings = {};
      
      data.forEach((reviewId, reviewData) {
        final reviewMap = Map<String, dynamic>.from(reviewData as Map);
        final serviceId = reviewMap['serviceId'] as String?;
        final rating = reviewMap['rating'] as int?;
        if (serviceId != null && rating != null) {
          if (!tempRatings.containsKey(serviceId)) {
            tempRatings[serviceId] = [];
          }
          tempRatings[serviceId]!.add(rating);
        }
      });
      
      tempRatings.forEach((serviceId, ratingList) {
        final int ratingCount = ratingList.length;
        final double averageRating = ratingList.reduce((a, b) => a + b) / ratingCount;
        ratings[serviceId] = RatingInfo(averageRating: averageRating, ratingCount: ratingCount);
      });

      if (mounted) {
        setState(() {
          _ratingsMap = ratings;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Favourites'),
      ),
      body: _buildBody(),
    );
  }
  
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_currentUser == null) {
      return const Center(child: Text("Please log in to see your favourites."));
    }
    if (_favouriteServices.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_outline, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text('No Favourites Yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Tap the heart on a service to save it here.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12.0,
        mainAxisSpacing: 12.0,
        childAspectRatio: 0.8,
      ),
      itemCount: _favouriteServices.length,
      itemBuilder: (context, index) {
        final service = _favouriteServices[index];
        final ratingInfo = _ratingsMap[service.id];
        return _buildServiceCard(service, ratingInfo);
      },
    );
  }
  
  Widget _buildServiceCard(HandymanService service, RatingInfo? ratingInfo) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ServiceDetailPage(serviceId: service.id)),
          );
        },
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
                    if (ratingInfo != null && ratingInfo.ratingCount > 0)
                      Row(
                        children: [
                          Icon(Icons.star_rounded, color: Colors.amber[700], size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '${ratingInfo.averageRating.toStringAsFixed(1)} (${ratingInfo.ratingCount})',
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
    );
  }
}
