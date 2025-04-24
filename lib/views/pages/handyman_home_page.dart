import 'dart:async'; // Import async library for StreamSubscription
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

// Import models and pages
import '../../models/handyman_services.dart';
import '../../models/bookings_services.dart'; // Import Booking model
import 'add_handyman_service.dart';
import 'update_handyman_service.dart';

// Import notifier for navigation
import '../../data/notifiers.dart'; // Adjust path if needed

// Data model for Quick Stats (remains the same)
class QuickStat {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final int? navigateToTabIndex; // Optional: Index to navigate to on tap
  final int? navigateToPageNotifierIndex; // Optional: Main page index

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
  String _searchQuery = '';
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();
  User? _currentUser; // Store current user

  // --- State for Real-time Stats ---
  int _pendingBookingsCount = 0;
  // Add placeholders for other counts if/when implemented
  int _newJobRequestsCount = 0; // Placeholder value
  int _unreadMessagesCount = 0; // Placeholder value

  // Stream Subscriptions for listeners
  StreamSubscription? _pendingBookingsSubscription;
  // Add subscriptions for other stats later if needed

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser; // Get current user once
    _searchController.addListener(_onSearchChanged);
    // Start listening to stats data if user is logged in
    if (_currentUser != null) {
      _listenToQuickStats();
    }
  }

  // Helper to safely call setState
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // *** NEW: Listen to data needed for quick stats ***
  void _listenToQuickStats() {
    if (_currentUser == null) return;
    final handymanId = _currentUser!.uid;

    // --- Listener for Pending Bookings ---
    final pendingQuery = _database
        .child('bookings')
        .orderByChild('handymanId')
        .equalTo(handymanId);

    _pendingBookingsSubscription?.cancel(); // Cancel previous listener if any
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
           // Handle error appropriately, maybe show 'Error' in stat card
           count = 0; // Reset count on error
        }
      }
      // Update state safely
      setStateIfMounted(() {
        _pendingBookingsCount = count;
      });
    }, onError: (error) {
       print("Error listening to pending bookings: $error");
       // Handle error appropriately
       setStateIfMounted(() { _pendingBookingsCount = 0; });
    });

    // --- TODO: Add Listeners for "New Job Requests" and "Unread Messages" ---
    // These would likely listen to different nodes (e.g., '/quoteRequests', '/chats' metadata)
    // For now, their counts remain 0 or display '-' based on the placeholder logic.
  }


  void _onSearchChanged() {
    setStateIfMounted(() { // Use safe setState
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  List<HandymanService> _applySearchFilter(List<HandymanService> services) {
    // ... (filtering logic remains the same)
    if (_searchQuery.isEmpty) {
      return services;
    }
    return services
        .where((service) => service.name.toLowerCase().contains(_searchQuery))
        .toList();
  }


  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    // Cancel listeners to prevent memory leaks
    _pendingBookingsSubscription?.cancel();
    // Cancel other subscriptions if added
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use the state's _currentUser instead of fetching repeatedly
    final String? handymanId = _currentUser?.uid;

    // *** Dynamically create QuickStats data using state variables ***
    final List<QuickStat> quickStatsData = [
      QuickStat(
          icon: Icons.pending_actions_outlined, // Use outlined icon
          label: 'Pending Bookings',
          value: _pendingBookingsCount.toString(), // Use real count
          color: Colors.orange,
          navigateToPageNotifierIndex: 1, // Navigate to Bookings Tab (index 1)
          // navigateToTabIndex: 0, // Optionally specify sub-tab index if BookingsPage supports it
      ),
      QuickStat(
          icon: Icons.assignment_late_outlined, // Use outlined icon
          label: 'New Job Requests',
          value: '-', // Placeholder - use _newJobRequestsCount when implemented
          color: Colors.green),
      QuickStat(
          icon: Icons.mark_chat_unread_outlined, // Use outlined icon
          label: 'Unread\n Messages',
          value: '-', // Placeholder - use _unreadMessagesCount when implemented
          color: Colors.blue,
          navigateToPageNotifierIndex: 2, // Navigate to Chat Tab (index 2)
      ),
    ];


    return Scaffold(
      // Note: AppBar is usually provided by WidgetTree for home pages
      body: RefreshIndicator( // Wrap with RefreshIndicator
         onRefresh: _handleRefresh, // Add refresh logic
         child: SingleChildScrollView(
           physics: const AlwaysScrollableScrollPhysics(), // Ensure scroll even when content fits
           padding: const EdgeInsets.all(16.0),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               _buildSearchBar(),
               const SizedBox(height: 20),
               _buildQuickStats(quickStatsData), // Pass dynamic data
               const SizedBox(height: 24),
               Text(
                 'My Services',
                 style: Theme.of(context)
                     .textTheme
                     .titleLarge
                     ?.copyWith(fontWeight: FontWeight.bold),
               ),
               const SizedBox(height: 12),
               if (handymanId != null)
                 _buildMyServicesStream(handymanId)
               else
                 // Show loading or login message if handymanId is initially null
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

  // *** NEW: Handle manual refresh ***
  Future<void> _handleRefresh() async {
    print("Refreshing Handyman Home...");
    // Re-trigger listeners or manually fetch data if needed
    // For simplicity, we ensure listeners are active. If they failed, re-initiate.
    // You could add a manual fetch here if listeners are unreliable or for immediate feedback.
    if (_pendingBookingsSubscription == null && _currentUser != null) {
       _listenToQuickStats(); // Re-start listener if it wasn't running
    }
    // Give time for potential network updates, adjust as needed
    await Future.delayed(const Duration(seconds: 1));
  }

  Widget _buildSearchBar() {
    // ... (remains the same)
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

  // *** Updated to accept dynamic data ***
  Widget _buildQuickStats(List<QuickStat> statsData) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.start, // Align tops
      children: statsData.map((stat) => _buildStatCard(stat)).toList(),
    );
  }

  // *** Updated to be tappable ***
  Widget _buildStatCard(QuickStat stat) {
    // Wrap the Card's content with InkWell for tap effect
    return Expanded(
      child: Card(
        elevation: 2.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        clipBehavior: Clip.antiAlias, // Ensure InkWell ripple effect respects border radius
        child: InkWell(
          // *** Add onTap handler ***
          onTap: () {
            print("Tapped on: ${stat.label}");
            if (stat.navigateToPageNotifierIndex != null) {
              // Use the global notifier to change the main page/tab
              selectedPageNotifier.value = stat.navigateToPageNotifierIndex!;
              print("Navigating to page index: ${stat.navigateToPageNotifierIndex}");

              // TODO: Implement sub-tab navigation if needed
              // This might involve:
              // 1. Modifying BookingsPage/ChatListPage to accept an initial sub-tab index argument.
              // 2. Using a separate Notifier/Provider state for the sub-tab index.
              // 3. Navigating with arguments: Navigator.pushNamed(context, '/bookings', arguments: {'initialTab': stat.navigateToTabIndex});
              if (stat.navigateToTabIndex != null) {
                 print("Requesting sub-tab index (needs implementation): ${stat.navigateToTabIndex}");
                 // Example: Update another notifier if using that approach
                 // bookingSubTabNotifier.value = stat.navigateToTabIndex!;
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(stat.icon, size: 30, color: stat.color),
                const SizedBox(height: 8),
                Text(
                  stat.value, // Display dynamic value
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: stat.color), // Adjusted style slightly
                ),
                const SizedBox(height: 4),
                Text(
                  stat.label,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  // Widget _buildMyServicesStream remains the same as before
  Widget _buildMyServicesStream(String handymanId) {
    return StreamBuilder<DatabaseEvent>( // Specify DatabaseEvent type
      stream: _database
          .child('services')
          .orderByChild('handymanId')
          .equalTo(handymanId)
          .onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          print("Error fetching services: ${snapshot.error}");
          return const Center(child: Text("Error loading services."));
        }
        // Use snapshot.data?.snapshot to access the actual data snapshot
        final dataSnapshot = snapshot.data?.snapshot;
        if (!snapshot.hasData || dataSnapshot == null || !dataSnapshot.exists || dataSnapshot.value == null) {
          return const Center( /* ... No services message ... */
            child: Padding( padding: EdgeInsets.symmetric(vertical: 32.0), child: Text( 'You haven\'t listed any services yet.\nTap the + button to add one!', textAlign: TextAlign.center,),),
          );
        }

        List<HandymanService> allFetchedServices = [];
        try {
          final dynamic snapshotValue = dataSnapshot.value;
          if (snapshotValue is Map) {
            final data = Map<String, dynamic>.from(snapshotValue); // No need to cast keys/values here if RTDB structure is correct
            allFetchedServices = data.entries.map((entry) {
              try {
                 // Ensure entry.value is a Map before proceeding
                 if (entry.value is Map) {
                   final valueMap = Map<String, dynamic>.from(entry.value as Map);
                   return HandymanService.fromMap(valueMap, entry.key);
                 } else {
                    print("Skipping service entry ${entry.key}: value is not a Map.");
                    return null; // Return null for invalid entries
                 }
              } catch(e) {
                 print("Error parsing service ${entry.key}: $e");
                 return null; // Return null if parsing fails
              }
            }).where((service) => service != null).cast<HandymanService>().toList(); // Filter out nulls

            allFetchedServices.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          } else {
            print("Services snapshot value is not a Map: $snapshotValue");
          }
        } catch (e) {
          print("Error processing service data: $e");
          return Center(child: Text("Error processing data: ${e.toString()}"));
        }

        final List<HandymanService> filteredServices = _applySearchFilter(allFetchedServices);

        if (allFetchedServices.isNotEmpty && filteredServices.isEmpty) {
          return const Center( /* ... No search results message ... */
            child: Padding( padding: EdgeInsets.symmetric(vertical: 32.0), child: Text( 'No services found matching your search.', textAlign: TextAlign.center,),),
          );
        }
        if (filteredServices.isEmpty && _searchQuery.isEmpty) {
           return const Center( /* ... No services message ... */
            child: Padding( padding: EdgeInsets.symmetric(vertical: 32.0), child: Text( 'You haven\'t listed any services yet.\nTap the + button to add one!', textAlign: TextAlign.center,),),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredServices.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemBuilder: (context, index) {
            final service = filteredServices[index];
            return Card( /* ... Service Card UI remains the same ... */
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              elevation: 3,
              child: InkWell(
                onTap: () {
                  Navigator.push( context, MaterialPageRoute( builder: (context) => UpdateHandymanServicePage(serviceId: service.id),),);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded( /* ... Image Section ... */
                      flex: 3,
                      child: Container( width: double.infinity, color: Colors.grey[200], child: (service.imageUrl != null && service.imageUrl!.isNotEmpty) ? Image.network( service.imageUrl!, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 30)),) : const Center(child: Icon(Icons.construction, size: 40, color: Colors.grey))),
                    ),
                    Expanded( /* ... Text Section ... */
                      flex: 2,
                      child: Padding( padding: const EdgeInsets.all(8.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceAround, children: [ Text( service.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis,), Text( 'RM ${service.price.toStringAsFixed(2)} (${service.priceType})', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[700]), maxLines: 1, overflow: TextOverflow.ellipsis,),],),),
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