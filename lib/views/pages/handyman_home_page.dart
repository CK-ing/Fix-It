import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../models/handyman_services.dart';
import 'add_handyman_service.dart';
import 'update_handyman_service.dart';

// Data model for Quick Stats (simple placeholder for UI)
class QuickStat {
  final IconData icon;
  final String label;
  final String value; // Keep as String, fetch actual data later
  final Color color;

  QuickStat(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});
}


class HandymanHomePage extends StatefulWidget {
  const HandymanHomePage({super.key});

  @override
  State<HandymanHomePage> createState() => _HandymanHomePageState();
}

class _HandymanHomePageState extends State<HandymanHomePage> {
  final TextEditingController _searchController = TextEditingController();
  // Keep track of the current search query
  String _searchQuery = '';

  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();

  // --- Placeholder Data for Quick Stats ---
  // TODO: Replace these with actual data fetching later
  final List<QuickStat> _quickStatsData = [
    QuickStat(
        icon: Icons.pending_actions,
        label: 'Pending Bookings',
        value: '-', // Placeholder
        color: Colors.orange),
    QuickStat(
        icon: Icons.assignment_late, // Changed icon from previous example
        label: 'New Job Requests',
        value: '-', // Placeholder
        color: Colors.green),
    QuickStat(
        icon: Icons.message,
        label: 'Unread Messages',
        value: '-', // Placeholder
        color: Colors.blue),
  ];
 // --- End Placeholder Data ---


  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  // Update search query and trigger rebuild
  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  // Helper function to filter services based on the current search query
  List<HandymanService> _applySearchFilter(List<HandymanService> services) {
    if (_searchQuery.isEmpty) {
      return services; // No filter applied
    }
    // Ensure null safety for service name
    return services
        .where((service) => service.name.toLowerCase().contains(_searchQuery))
        .toList();
  }


  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged); // Important to remove listener
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get current user ID safely
    final String? handymanId = _auth.currentUser?.uid;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchBar(),
            const SizedBox(height: 20),
            _buildQuickStats(), // Display quick stats
            const SizedBox(height: 24),
            Text(
              'My Services',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Use StreamBuilder for services grid if user is logged in
            if (handymanId != null)
              _buildMyServicesStream(handymanId) // Pass ID to the stream builder
            else
              const Center(child: Text("Please log in.")), // Fallback if no user ID
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to the AddHandymanServicePage
           Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddHandymanServicePage()),
          );
          print('Navigating to Add New Service Page'); // Optional: for debugging
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
          // onChanged listener is handled by _searchController.addListener
        ),
      ),
    );
  }

  // Builds the row of quick statistic cards
  Widget _buildQuickStats() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: _quickStatsData.map((stat) => _buildStatCard(stat)).toList(),
    );
  }

  // Builds a single quick statistic card
  Widget _buildStatCard(QuickStat stat) {
     return Expanded( // Ensure cards take available space
      child: Card(
        elevation: 2.0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(stat.icon, size: 30, color: stat.color),
              const SizedBox(height: 8),
              Text(
                stat.value, // Display value from QuickStat object
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: stat.color),
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
    );
  }


  // Renamed from myServicesGrid to avoid conflict, uses StreamBuilder
  Widget _buildMyServicesStream(String handymanId) {
    return StreamBuilder(
      stream: _database
          .child('services')
          .orderByChild('handymanId') // Make sure 'handymanId' is indexed in Firebase rules
          .equalTo(handymanId)
          .onValue, // Listens for real-time updates
      builder: (context, snapshot) {
        // 1. Handle Connection States
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          print("Error fetching services: ${snapshot.error}"); // Log error
          return const Center(child: Text("Error loading services."));
        }
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          // Display message when no services are listed yet
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32.0),
              child: Text(
                'You haven\'t listed any services yet.\nTap the + button to add one!',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        // 2. Process Data
        List<HandymanService> allFetchedServices = [];
        try {
          // Ensure snapshot.data!.snapshot.value is cast correctly
          final dynamic snapshotValue = snapshot.data!.snapshot.value;
          if (snapshotValue is Map) { // Check if it's a Map
             final data = Map<String, dynamic>.from(snapshotValue.cast<String, dynamic>()); // Cast keys and values

            allFetchedServices = data.entries.map((entry) {
              // Use Map<String, dynamic> for value
              final value = Map<String, dynamic>.from(entry.value as Map);
              // Pass data map first, then ID, according to model factory
              return HandymanService.fromMap(value, entry.key);
            }).toList();
             // Optional: Sort services if needed, e.g., by creation date descending
             allFetchedServices.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          } else {
             // Handle cases where the data might not be a map (e.g., empty)
             print("Snapshot value is not a Map: $snapshotValue");
          }


        } catch (e) {
           print("Error processing service data: $e"); // Log processing error
           // Provide more context in the error message if possible
           return Center(child: Text("Error processing data: ${e.toString()}"));
        }


        // 3. Apply Search Filter
        final List<HandymanService> filteredServices = _applySearchFilter(allFetchedServices);

        // Display message if no services match the filter but services exist
        if (allFetchedServices.isNotEmpty && filteredServices.isEmpty) {
           return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32.0),
              child: Text(
                'No services found matching your search.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
         // Handle case where filteredServices is empty because allFetchedServices was empty
        if (filteredServices.isEmpty && _searchQuery.isEmpty) { // Only show if not searching
           return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32.0),
              child: Text(
                'You haven\'t listed any services yet.\nTap the + button to add one!',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }


        // 4. Build Grid
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredServices.length, // Use filtered list length
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85, // Adjust as needed
          ),
          itemBuilder: (context, index) {
            final service = filteredServices[index]; // Use filtered list item

            // --- Service Card UI ---
            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias, // Ensures image respects card borders
              elevation: 3,
              child: InkWell( // Make card tappable
                 // *** MODIFIED onTap ***
                 onTap: () {
                    // Navigate to Update Service Page, passing the service ID
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UpdateHandymanServicePage(serviceId: service.id),
                      ),
                    );
                    print('Tapped service: ${service.name} (ID: ${service.id}) - Navigating to Update Page');
                 },
                 // *** END OF MODIFICATION ***
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image Section
                    Expanded(
                      flex: 3,
                      child: Container(
                          width: double.infinity,
                          color: Colors.grey[200],
                          child: (service.imageUrl != null && service.imageUrl!.isNotEmpty)
                              ? Image.network(
                                  service.imageUrl!,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const Center(child: CircularProgressIndicator());
                                  },
                                  // Handle potential image loading errors gracefully
                                  errorBuilder: (context, error, stackTrace) {
                                     print("Error loading image ${service.imageUrl}: $error");
                                     return const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 30));
                                  }
                                )
                              : const Center(child: Icon(Icons.construction, size: 40, color: Colors.grey))),
                    ),
                    // Text Section
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                           mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text(
                              service.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'RM ${service.price.toStringAsFixed(2)} (${service.priceType})',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[700]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // TODO: Add Rating display here if needed later
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
            // --- End Service Card UI ---
          },
        );
      },
    );
  }
}