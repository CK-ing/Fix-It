import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../models/handyman_services.dart';
import '../../models/bookings_services.dart';
import 'add_handyman_service.dart';
import 'update_handyman_service.dart';
import '../../data/notifiers.dart';

// Helper class to hold calculated rating information.
class RatingInfo {
  final double averageRating;
  final int ratingCount;

  RatingInfo({this.averageRating = 0.0, this.ratingCount = 0});
}

class QuickStat {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final int? navigateToTabIndex;
  final int? navigateToPageNotifierIndex;

  QuickStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.navigateToTabIndex,
    this.navigateToPageNotifierIndex,
  });
}

class HandymanHomePage extends StatefulWidget {
  const HandymanHomePage({super.key});

  @override
  State<HandymanHomePage> createState() => _HandymanHomePageState();
}

class _HandymanHomePageState extends State<HandymanHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();
  User? _currentUser;

  // State for Real-time Stats
  int _pendingBookingsCount = 0;
  int _newJobRequestsCount = 0;
  int _unreadMessagesCount = 0;
  
  // *** NEW: State to hold ratings data ***
  Map<String, RatingInfo> _ratingsMap = {};

  // Stream Subscriptions
  StreamSubscription? _pendingBookingsSubscription;
  StreamSubscription? _servicesAndRatingsSubscription;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    _searchController.addListener(_onSearchChanged);
    if (_currentUser != null) {
      _listenToQuickStats();
      // Listen to services and ratings together
      _listenToServicesAndRatings();
    }
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // *** NEW: Combined listener for services and their ratings ***
  void _listenToServicesAndRatings() {
    if (_currentUser == null) return;
    
    _servicesAndRatingsSubscription?.cancel();
    _servicesAndRatingsSubscription = _database.child('reviews').onValue.listen((event) {
      if (!mounted) return;
      // When reviews change, we recalculate the ratings.
      // This will trigger a rebuild of the services list which uses _ratingsMap.
      _calculateRatings(event.snapshot);
    });
  }
  
  void _calculateRatings(DataSnapshot reviewSnapshot) {
      Map<String, RatingInfo> ratings = {};
      if (reviewSnapshot.exists && reviewSnapshot.value != null) {
        final data = Map<String, dynamic>.from(reviewSnapshot.value as Map);
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
      }
      setStateIfMounted(() {
        _ratingsMap = ratings;
      });
  }


  void _listenToQuickStats() {
    if (_currentUser == null) return;
    final handymanId = _currentUser!.uid;

    final pendingQuery = _database.child('bookings').orderByChild('handymanId').equalTo(handymanId);

    _pendingBookingsSubscription?.cancel();
    _pendingBookingsSubscription = pendingQuery.onValue.listen((event) {
      int count = 0;
      if (event.snapshot.exists && event.snapshot.value != null) {
        try {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          data.forEach((key, value) {
            if (value is Map && value['status'] == 'Pending') {
              count++;
            }
          });
        } catch (e) {
          print("Error processing pending bookings snapshot: $e");
          count = 0;
        }
      }
      setStateIfMounted(() {
        _pendingBookingsCount = count;
      });
    }, onError: (error) {
      print("Error listening to pending bookings: $error");
      setStateIfMounted(() { _pendingBookingsCount = 0; });
    });
  }

  void _onSearchChanged() {
    // This will trigger a rebuild, and the StreamBuilder will handle the filtering.
    setStateIfMounted(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pendingBookingsSubscription?.cancel();
    _servicesAndRatingsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? handymanId = _currentUser?.uid;

    final List<QuickStat> quickStatsData = [
      QuickStat(icon: Icons.pending_actions_outlined, label: 'Pending Bookings', value: _pendingBookingsCount.toString(), color: Colors.orange, navigateToPageNotifierIndex: 1),
      QuickStat(icon: Icons.assignment_late_outlined, label: 'New Job Requests', value: '0', color: Colors.green),
      QuickStat(icon: Icons.mark_chat_unread_outlined, label: 'Unread\n Messages', value: '0', color: Colors.blue, navigateToPageNotifierIndex: 2),
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
           // Manually re-trigger listeners
          if (_currentUser != null) {
            _listenToQuickStats();
            _listenToServicesAndRatings();
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchBar(),
              const SizedBox(height: 20),
              _buildQuickStats(quickStatsData),
              const SizedBox(height: 24),
              Text('My Services', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (handymanId != null)
                _buildMyServicesStream(handymanId)
              else
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddHandymanServicePage()),
          );
        },
        tooltip: 'Add New Service',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search your listed services...',
            prefixIcon: Icon(Icons.search),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStats(List<QuickStat> statsData) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: statsData.map((stat) => _buildStatCard(stat)).toList(),
    );
  }

  Widget _buildStatCard(QuickStat stat) {
    return Expanded(
      child: Card(
        elevation: 2.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (stat.navigateToPageNotifierIndex != null) {
              selectedPageNotifier.value = stat.navigateToPageNotifierIndex!;
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(stat.icon, size: 30, color: stat.color),
                const SizedBox(height: 8),
                Text(stat.value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: stat.color)),
                const SizedBox(height: 4),
                Text(stat.label, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMyServicesStream(String handymanId) {
    return StreamBuilder<DatabaseEvent>(
      stream: _database.child('services').orderByChild('handymanId').equalTo(handymanId).onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text("Error loading services."));
        }
        
        final dataSnapshot = snapshot.data?.snapshot;
        if (!snapshot.hasData || dataSnapshot == null || !dataSnapshot.exists || dataSnapshot.value == null) {
          return const Center(child: Padding( padding: EdgeInsets.symmetric(vertical: 32.0), child: Text( 'You haven\'t listed any services yet.\nTap the + button to add one!', textAlign: TextAlign.center,),),);
        }

        List<HandymanService> allFetchedServices = [];
        try {
          final dynamic snapshotValue = dataSnapshot.value;
          if (snapshotValue is Map) {
            final data = Map<String, dynamic>.from(snapshotValue);
            allFetchedServices = data.entries.map((entry) {
                if (entry.value is Map) {
                  final valueMap = Map<String, dynamic>.from(entry.value as Map);
                  return HandymanService.fromMap(valueMap, entry.key);
                }
                return null;
            }).where((service) => service != null).cast<HandymanService>().toList();
            allFetchedServices.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          }
        } catch (e) {
          return Center(child: Text("Error processing data: ${e.toString()}"));
        }
        final activeServices = allFetchedServices.where((service) => service.isActive).toList();

        final searchQuery = _searchController.text.toLowerCase();
        final filteredServices = searchQuery.isEmpty
            ? activeServices
            : activeServices.where((s) => s.name.toLowerCase().contains(searchQuery)).toList();

        if (activeServices.isNotEmpty && filteredServices.isEmpty) {
          return const Center( child: Padding( padding: EdgeInsets.symmetric(vertical: 32.0), child: Text( 'No services found matching your search.', textAlign: TextAlign.center,),),);
        }
        if (activeServices.isEmpty) {
          return const Center( child: Padding( padding: EdgeInsets.symmetric(vertical: 32.0), child: Text( 'You haven\'t listed any services yet.\nTap the + button to add one!', textAlign: TextAlign.center,),),);
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredServices.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.8,
          ),
          itemBuilder: (context, index) {
            final service = filteredServices[index];
            // *** NEW: Get rating info for this service ***
            final ratingInfo = _ratingsMap[service.id];

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              elevation: 3,
              child: InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => UpdateHandymanServicePage(serviceId: service.id)));
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
                            ? Image.network(service.imageUrl!, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 30)))
                            : const Center(child: Icon(Icons.construction, size: 40, color: Colors.grey)),
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
                            Text(service.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text('RM ${service.price.toStringAsFixed(2)} (${service.priceType})', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[700]), maxLines: 1, overflow: TextOverflow.ellipsis),
                            // --- NEW RATING DISPLAY FOR HANDYMAN ---
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
                                'No ratings yet',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
