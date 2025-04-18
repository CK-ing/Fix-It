import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart'; // Import Geolocator
import 'package:geocoding/geocoding.dart';

import '../../models/handyman_services.dart'; // Import Geocoding

class HomeownerHomePage extends StatefulWidget {
  const HomeownerHomePage({super.key});

  @override
  State<HomeownerHomePage> createState() => _HomeownerHomePageState();
}

class _HomeownerHomePageState extends State<HomeownerHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // State Variables
  String _userName = "User";
  String _searchQuery = '';
  String? _selectedCategoryFilter;
  bool _isLoadingServices = true;
  bool _isFetchingCurrentLocation = false; // Loading indicator for GPS/Geocoding

  // Location Filter State
  String? _currentLocationState; // State determined from GPS
  bool _filterByCurrentLocationActive = false; // Flag to filter by current location state

  // Data Lists
  List<HandymanService> _allServices = [];
  List<HandymanService> _filteredServices = [];

  // Dummy data for offers/promotions
  final List<Map<String, String>> _offers = [
    {'image': 'https://via.placeholder.com/300x150/FFA07A/ffffff?text=Offer+1', 'title': '20% Off Plumbing'},
    {'image': 'https://via.placeholder.com/300x150/98FB98/ffffff?text=Offer+2', 'title': 'RM 50 Off AC Service'},
    {'image': 'https://via.placeholder.com/300x150/ADD8E6/ffffff?text=Offer+3', 'title': 'Free Electrical Checkup'},
  ];

  // Service categories with icons (Added 'All')
  final List<Map<String, dynamic>> _categories = [
    {'name': 'All', 'icon': Icons.apps},
    {'name': 'Plumbing', 'icon': Icons.plumbing_outlined},
    {'name': 'Electrical', 'icon': Icons.electrical_services_outlined},
    {'name': 'Cleaning', 'icon': Icons.cleaning_services_outlined},
    {'name': 'Air Cond', 'icon': Icons.ac_unit_outlined},
    {'name': 'Painting', 'icon': Icons.format_paint_outlined},
    {'name': 'Carpentry', 'icon': Icons.carpenter_outlined},
    {'name': 'More', 'icon': Icons.more_horiz},
  ];

  // Valid Malaysian states list for validation
  final List<String> _malaysianStates = [
    'Johor', 'Kedah', 'Kelantan', 'Kuala Lumpur', 'Labuan', 'Melaka',
    'Negeri Sembilan', 'Pahang', 'Penang', 'Perak', 'Perlis', 'Putrajaya',
    'Sabah', 'Sarawak', 'Selangor', 'Terengganu'
  ];


  @override
  void initState() {
    super.initState();
    _fetchUserData(); // Fetch user name only now
    _fetchServices(); // Fetch services
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // Fetch user data (name only)
  Future<void> _fetchUserData() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final snapshot = await _database.child('users').child(user.uid).child('name').get();
        if (snapshot.exists && snapshot.value != null && mounted) {
          setStateIfMounted(() {
            _userName = snapshot.value.toString();
          });
        }
      } catch (e) {
        print("Error fetching user name: $e");
      }
    }
  }

   // Fetch all services
  Future<void> _fetchServices() async {
    if (!mounted) return;
    setStateIfMounted(() { _isLoadingServices = true; });
    try {
      final snapshot = await _database.child('services').get();
      List<HandymanService> services = [];
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        services = data.entries.map((entry) {
           final value = Map<String, dynamic>.from(entry.value as Map);
           return HandymanService.fromMap(value, entry.key);
        }).toList();
        services.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }

      if (mounted) {
        setState(() {
          _allServices = services;
          // Apply existing filters (like category) but not search initially
          _filterServices(applySearchQuery: false);
          _isLoadingServices = false;
        });
      }
    } catch (e) {
      print("Error fetching services: $e");
      if (mounted) {
         setStateIfMounted(() { _isLoadingServices = false; });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading services: ${e.toString()}'), backgroundColor: Colors.red),
          );
      }
    }
  }

  // Update search query
  void _onSearchChanged() {
    if (_searchQuery != _searchController.text.toLowerCase()) {
       _searchQuery = _searchController.text.toLowerCase();
       _filterServices(); // Apply all filters including search
    }
  }

  // Filter services based on ALL active filters
  void _filterServices({bool applySearchQuery = true}) {
    if (!mounted) return;

    List<HandymanService> tempServices = List.from(_allServices);

    // 1. Apply category filter
    if (_selectedCategoryFilter != null && _selectedCategoryFilter != 'All' && _selectedCategoryFilter != 'More') {
        tempServices = tempServices.where((s) => s.category == _selectedCategoryFilter).toList();
    }

    // 2. Apply current location (state) filter
    // Use the new flag and state variable
    if (_filterByCurrentLocationActive && _currentLocationState != null && _currentLocationState!.isNotEmpty) {
        tempServices = tempServices.where((s) => s.state == _currentLocationState).toList();
    }

    // 3. Apply search query filter
    if (applySearchQuery && _searchQuery.isNotEmpty) {
        tempServices = tempServices.where((s) => s.name.toLowerCase().contains(_searchQuery)).toList();
    }

    setState(() {
        _filteredServices = tempServices;
    });
  }

  // --- NEW: Handle Nearby Filter Button Tap ---
  void _handleNearbyFilterTap() async {
     if (_isFetchingCurrentLocation) return; // Prevent multiple taps while processing

     // If the filter is currently active, tapping again should turn it off
     if (_filterByCurrentLocationActive) {
        setState(() {
           _filterByCurrentLocationActive = false;
           _currentLocationState = null; // Clear the state
        });
        _filterServices(); // Re-apply filters (which will now exclude state filter)
        print("Nearby filter deactivated.");
        return;
     }

     // If the filter is not active, try to activate it by getting location
     await _getCurrentLocationAndFilter();
  }


  // --- NEW: Get Current Location, Geocode, and Filter ---
  Future<void> _getCurrentLocationAndFilter() async {
    if (!mounted) return;
    setState(() { _isFetchingCurrentLocation = true; });

    LocationPermission permission;
    bool serviceEnabled;

    // 1. Check if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled. Please enable them.')));
      setStateIfMounted(() { _isFetchingCurrentLocation = false; });
      return;
    }

    // 2. Check and request permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
         if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are denied.')));
         setStateIfMounted(() { _isFetchingCurrentLocation = false; });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
       if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are permanently denied. Please enable them in settings.')));
       setStateIfMounted(() { _isFetchingCurrentLocation = false; });
      return;
    }

    // 3. Get Current Position
    try {
       Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium // Medium accuracy is usually sufficient for state level
       );

       // 4. Geocode Coordinates to Placemark
       List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude
       );

       if (placemarks.isNotEmpty && mounted) {
          final Placemark place = placemarks.first;
          final String? geocodedState = place.administrativeArea; // State is usually here

          print("Geocoded State: $geocodedState");

          // 5. Validate and Set State Filter
          if (geocodedState != null && _malaysianStates.contains(geocodedState)) {
             setState(() {
                _currentLocationState = geocodedState;
                _filterByCurrentLocationActive = true; // Activate the filter
             });
             _filterServices(); // Apply the filter immediately
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('Showing services near you in $_currentLocationState'), duration: const Duration(seconds: 2)),
             );
          } else {
             // Could not determine a valid state
             setState(() {
                _filterByCurrentLocationActive = false; // Ensure filter is off
                _currentLocationState = null;
             });
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Could not determine a valid state for your current location.'), backgroundColor: Colors.orange),
             );
          }
       } else {
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Could not determine placemark for your location.'), backgroundColor: Colors.orange),
             );
          }
       }

    } catch (e) {
       print("Error getting location or geocoding: $e");
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error getting location: ${e.toString()}'), backgroundColor: Colors.red),
          );
       }
       // Ensure filter is off on error
       setStateIfMounted(() {
          _filterByCurrentLocationActive = false;
          _currentLocationState = null;
       });
    } finally {
      // Ensure loading indicator stops
       setStateIfMounted(() { _isFetchingCurrentLocation = false; });
    }
  }


   // Handle category tap
  void _onCategoryTapped(String categoryName) {
     print('Category Tapped: $categoryName');
     if (categoryName == 'More') {
        // TODO: Implement logic for 'More' categories
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('More categories feature coming soon!')),
         );
         return;
     }
     setState(() {
       if (_selectedCategoryFilter == categoryName || categoryName == 'All') {
         _selectedCategoryFilter = null; // Clear filter
       } else {
         _selectedCategoryFilter = categoryName; // Set filter
       }
     });
     _filterServices(); // Apply filters
  }

   // Handle service tap
  void _onServiceTapped(String serviceId, String serviceName) {
     print('Service Tapped: $serviceName (ID: $serviceId)');
      ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text('Viewing details for $serviceName coming soon!')),
     );
     // TODO: Navigator.push(context, MaterialPageRoute(builder: (context) => ServiceDetailPage(serviceId: serviceId)));
  }

  // Helper to safely call setState only if the widget is still mounted
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }


  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async { await _fetchServices(); }, // Refresh services list
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildWelcomeMessage(),
          const SizedBox(height: 16),
          _buildSearchBar(), // Updated to handle new filter state
          const SizedBox(height: 20),
          _buildSectionHeader('Special Offers'),
          _buildOffersCarousel(),
          const SizedBox(height: 24),
          _buildSectionHeader('Categories'),
          _buildCategoryList(),
          const SizedBox(height: 24),
          _buildSectionHeader('All Services'),
          _buildAllServicesGrid(), // Uses _filteredServices
        ],
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildWelcomeMessage() {
    return Text(
      'Welcome, $_userName!',
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildSearchBar() {
    // Determine icon/color based on the NEW filter state
    final bool isNearbyActive = _filterByCurrentLocationActive; // Use the new flag
    final IconData locationIcon = isNearbyActive ? Icons.location_on : Icons.location_on_outlined;
    // Use a distinct color when active, e.g., theme's error color or accent color
    final Color locationIconColor = isNearbyActive ? Theme.of(context).colorScheme.error : Theme.of(context).primaryColor;

    return Row(
      children: [
        Expanded(
          child: Card(
            elevation: 2.0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25.0)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search for services (e.g., plumbing)',
                  prefixIcon: Icon(Icons.search, size: 20),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0),
                  isDense: true,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Location Button with loading state
        Card(
           elevation: 2.0,
           shape: const CircleBorder(),
           child: _isFetchingCurrentLocation // Check the NEW loading flag
              ? Container(
                  padding: const EdgeInsets.all(12.0),
                  width: 48, height: 48,
                  child: const CircularProgressIndicator(strokeWidth: 2.0),
                )
              : IconButton(
                  icon: Icon(locationIcon, color: locationIconColor),
                  tooltip: isNearbyActive
                           ? 'Showing services in $_currentLocationState (Tap to show all)' // Use current state
                           : 'Tap to show services near your current location',
                  onPressed: _handleNearbyFilterTap, // Call the new handler
              ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
     return Padding(
       padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
       child: Text(
         title,
         style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
       ),
     );
  }


  Widget _buildOffersCarousel() {
    // ... (no changes needed in this helper) ...
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _offers.length,
        itemBuilder: (context, index) {
          final offer = _offers[index];
          return Container(
            width: 300,
            margin: const EdgeInsets.only(right: 12.0),
            child: Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 3,
              child: Stack(
                 alignment: Alignment.bottomLeft,
                 children: [
                    Positioned.fill(
                       child: Image.network(
                          offer['image']!, fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
                          errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.error_outline)),
                       ),
                    ),
                    Container(
                       decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                          gradient: LinearGradient(
                             colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                             begin: Alignment.bottomCenter, end: Alignment.topCenter, stops: const [0.0, 0.6],
                          ),
                       ),
                    ),
                    Padding(
                       padding: const EdgeInsets.all(12.0),
                       child: Text( offer['title']!,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 2.0, color: Colors.black54)]),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                       ),
                    ),
                 ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryList() {
    // ... (no changes needed in this helper, highlighting logic remains) ...
     return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final bool isSelected = _selectedCategoryFilter == category['name'];
          final Color backgroundColor = isSelected
              ? Theme.of(context).primaryColor.withOpacity(0.3)
              : Theme.of(context).primaryColorLight.withOpacity(0.5);
          final Color iconColor = Theme.of(context).primaryColorDark;


          return InkWell(
             onTap: () => _onCategoryTapped(category['name']),
             borderRadius: BorderRadius.circular(10),
             child: Container(
                width: 85,
                margin: const EdgeInsets.only(right: 10.0),
                child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                      CircleAvatar(
                         radius: 30,
                         backgroundColor: backgroundColor,
                         child: Icon(category['icon'], size: 28, color: iconColor),
                      ),
                      const SizedBox(height: 8),
                      Text(
                         category['name'],
                         style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                         ),
                         textAlign: TextAlign.center,
                         maxLines: 1,
                         overflow: TextOverflow.ellipsis,
                      ),
                   ],
                ),
             ),
          );
        },
      ),
    );
  }

  Widget _buildAllServicesGrid() {
    // ... (no changes needed in this helper, uses _filteredServices) ...
     if (_isLoadingServices) {
      return const Padding(
         padding: EdgeInsets.symmetric(vertical: 40.0),
         child: Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
      );
    }
    if (_filteredServices.isEmpty) {
       String message = 'No services available right now.\nCheck back later!';
       if (_searchQuery.isNotEmpty) { message = 'No services found matching your search.'; }
       // Updated message for current location filter
       else if (_filterByCurrentLocationActive && _currentLocationState != null) { message = 'No services found for your current state "$_currentLocationState".'; }
       else if (_selectedCategoryFilter != null && _selectedCategoryFilter != 'All') { message = 'No services found in the "$_selectedCategoryFilter" category.'; }

       return Center(
         child: Padding(
           padding: const EdgeInsets.symmetric(vertical: 32.0),
           child: Text(message, textAlign: TextAlign.center),
         ),
       );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredServices.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, crossAxisSpacing: 12.0, mainAxisSpacing: 12.0, childAspectRatio: 0.8,
      ),
      itemBuilder: (context, index) {
        final service = _filteredServices[index];
        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          elevation: 3,
          child: InkWell(
            onTap: () => _onServiceTapped(service.id, service.name),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    width: double.infinity, color: Colors.grey[200],
                    child: (service.imageUrl != null && service.imageUrl!.isNotEmpty)
                        ? Image.network( service.imageUrl!, fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
                            errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.error_outline, color: Colors.grey)),
                          )
                        : const Center(child: Icon(Icons.construction, size: 30, color: Colors.grey)),
                  ),
                ),
                Expanded(
                   flex: 2,
                   child: Padding(
                     padding: const EdgeInsets.all(8.0),
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       mainAxisAlignment: MainAxisAlignment.spaceAround,
                       children: [
                         Text( service.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                         Text( 'RM ${service.price.toStringAsFixed(2)} (${service.priceType})', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[700]), maxLines: 1, overflow: TextOverflow.ellipsis),
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
  }
}