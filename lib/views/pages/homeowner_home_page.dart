import 'dart:async'; // For Future in RefreshIndicator
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../../models/handyman_services.dart'; // Ensure this model has 'district'
import 'service_detail_page.dart';

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
  bool _isFetchingCurrentLocation = false;

  // Location Filter State
  String? _currentLocationState;
  String? _currentLocationDistrict;
  bool _filterByCurrentLocationActive = false;

  // Data Lists
  List<HandymanService> _allServices = [];
  List<HandymanService> _filteredServices = [];

  // Dummy data for offers/promotions (can be replaced with dynamic fetching)
  final List<Map<String, String>> _offers = [
    {'image': 'https://via.placeholder.com/300x150/FFA07A/ffffff?text=Offer+1', 'title': '20% Off Plumbing'},
    {'image': 'https://via.placeholder.com/300x150/98FB98/ffffff?text=Offer+2', 'title': 'RM 50 Off AC Service'},
    {'image': 'https://via.placeholder.com/300x150/ADD8E6/ffffff?text=Offer+3', 'title': 'Free Electrical Checkup'},
  ];

  // Service categories with icons
  final List<Map<String, dynamic>> _categories = [
    {'name': 'All', 'icon': Icons.apps}, {'name': 'Plumbing', 'icon': Icons.plumbing_outlined}, {'name': 'Electrical', 'icon': Icons.electrical_services_outlined}, {'name': 'Cleaning', 'icon': Icons.cleaning_services_outlined}, {'name': 'Air Cond', 'icon': Icons.ac_unit_outlined}, {'name': 'Painting', 'icon': Icons.format_paint_outlined}, {'name': 'Carpentry', 'icon': Icons.carpenter_outlined}, {'name': 'More', 'icon': Icons.more_horiz},
  ];

  // Valid Malaysian states list for validation
  final List<String> _malaysianStates = [
    'Johor', 'Kedah', 'Kelantan', 'Kuala Lumpur', 'Labuan', 'Melaka', 'Negeri Sembilan', 'Pahang', 'Penang', 'Perak', 'Perlis', 'Putrajaya', 'Sabah', 'Sarawak', 'Selangor', 'Terengganu'
  ];


  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _fetchServices();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  Future<void> _fetchUserData() async { /* ... remains same ... */
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final snapshot = await _database.child('users').child(user.uid).child('name').get();
        if (snapshot.exists && snapshot.value != null && mounted) {
          setStateIfMounted(() { _userName = snapshot.value.toString(); });
        }
      } catch (e) { print("Error fetching user name: $e"); }
    }
  }

  Future<void> _fetchServices() async { /* ... remains same ... */
    if (!mounted) return;
    setStateIfMounted(() { _isLoadingServices = true; });
    try {
      final snapshot = await _database.child('services').get();
      List<HandymanService> services = [];
      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        services = data.entries.map((entry) {
            final value = Map<String, dynamic>.from(entry.value as Map);
            // Assuming HandymanService.fromMap is updated to handle 'district'
            return HandymanService.fromMap(value, entry.key);
        }).toList();
        services.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      if (mounted) {
        setState(() {
          _allServices = services;
          _filterServices(applySearchQuery: false);
          _isLoadingServices = false;
        });
      }
    } catch (e) {
      print("Error fetching services: $e");
      if (mounted) {
          setStateIfMounted(() { _isLoadingServices = false; });
          ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Error loading services: ${e.toString()}'), backgroundColor: Colors.red),);
      }
    }
  }

  void _onSearchChanged() {
    if (_searchQuery != _searchController.text.toLowerCase()) {
       _searchQuery = _searchController.text.toLowerCase();
       _filterServices();
    }
  }

  // *** MODIFIED: To prioritize district filtering for "Nearby" ***
  void _filterServices({bool applySearchQuery = true}) {
    if (!mounted) return;

    List<HandymanService> tempServices = List.from(_allServices);

    // 1. Apply category filter
    if (_selectedCategoryFilter != null && _selectedCategoryFilter != 'All' && _selectedCategoryFilter != 'More') {
        tempServices = tempServices.where((s) => s.category == _selectedCategoryFilter).toList();
    }

    // 2. Apply current location (state AND district) filter
    if (_filterByCurrentLocationActive) {
      // ** Prioritize district if available **
      if (_currentLocationDistrict != null && _currentLocationDistrict!.isNotEmpty) {
        tempServices = tempServices.where((s) =>
            s.district != null && s.district == _currentLocationDistrict &&
            // Optionally, ensure the state also matches if district names can be non-unique across states
            s.state != null && s.state == _currentLocationState
        ).toList();
      } else if (_currentLocationState != null && _currentLocationState!.isNotEmpty) {
        // Fallback to state if district is not determined
        tempServices = tempServices.where((s) => s.state == _currentLocationState).toList();
      }
      // If neither district nor state could be determined by GPS, no location filter is applied by this block.
    }
    // Note: Manual state/district dropdown filters (if added later) would be handled here.

    // 3. Apply search query filter
    if (applySearchQuery && _searchQuery.isNotEmpty) {
        tempServices = tempServices.where((s) => s.name.toLowerCase().contains(_searchQuery)).toList();
    }

    setState(() {
        _filteredServices = tempServices;
    });
  }

  void _handleNearbyFilterTap() async {
    if (_isFetchingCurrentLocation) return;

    if (_filterByCurrentLocationActive) {
      setState(() {
          _filterByCurrentLocationActive = false;
          _currentLocationState = null;
          _currentLocationDistrict = null;
      });
      _filterServices();
      print("Nearby filter deactivated.");
      return;
    }
    await _getCurrentLocationAndFilter();
  }

  // *** MODIFIED: Geocoding & Messaging based on district priority ***
  Future<void> _getCurrentLocationAndFilter() async {
    if (!mounted) return;
    setState(() { _isFetchingCurrentLocation = true; });

    LocationPermission permission;
    bool serviceEnabled;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled. Please enable them.')));
      setStateIfMounted(() { _isFetchingCurrentLocation = false; });
      return;
    }

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

    try {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
        List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);

        if (placemarks.isNotEmpty && mounted) {
          final Placemark place = placemarks.first;
          final String? geocodedState = place.administrativeArea; // e.g., "Perak"
          // Attempt to get district. For Malaysia, 'subAdministrativeArea' or 'locality' might contain district. Test this.
          final String? geocodedDistrict = place.subAdministrativeArea ?? place.locality;

          print("Geocoded State: $geocodedState, Geocoded District: $geocodedDistrict");

          String snackBarMessage;
          bool success = false;

          if (geocodedDistrict != null && geocodedDistrict.isNotEmpty &&
              geocodedState != null && _malaysianStates.contains(geocodedState)) {
            // Prefer district if available and state is valid
            setState(() {
              _currentLocationState = geocodedState;
              _currentLocationDistrict = geocodedDistrict;
              _filterByCurrentLocationActive = true;
            });
            snackBarMessage = 'Showing services near you in $geocodedDistrict, $geocodedState';
            success = true;
          } else if (geocodedState != null && _malaysianStates.contains(geocodedState)) {
            // Fallback to state if district is not usable but state is
            setState(() {
              _currentLocationState = geocodedState;
              _currentLocationDistrict = null; // Explicitly nullify district
              _filterByCurrentLocationActive = true;
            });
            snackBarMessage = 'Showing services near you in $geocodedState.';
            success = true;
          } else {
            // Could not determine a valid state or district
            setState(() {
              _filterByCurrentLocationActive = false;
              _currentLocationState = null;
              _currentLocationDistrict = null;
            });
            snackBarMessage = 'Could not determine a valid location (State/District) for nearby services.';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(snackBarMessage), backgroundColor: Colors.orange),
            );
          }

          if (success) {
            _filterServices();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(snackBarMessage), duration: const Duration(seconds: 3)),
            );
          }

        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not determine placemark for your location.'), backgroundColor: Colors.orange),);
          }
        }
    } catch (e) {
        print("Error getting location or geocoding: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Error getting location: ${e.toString()}'), backgroundColor: Colors.red),);
        }
        setStateIfMounted(() {
          _filterByCurrentLocationActive = false;
          _currentLocationState = null;
          _currentLocationDistrict = null;
        });
    } finally {
        setStateIfMounted(() { _isFetchingCurrentLocation = false; });
    }
  }

  void _onCategoryTapped(String categoryName) {
    print('Category Tapped: $categoryName');
    if (categoryName == 'More') { ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('More categories feature coming soon!')),); return; }
    setState(() {
      if (_selectedCategoryFilter == categoryName || categoryName == 'All') { _selectedCategoryFilter = null; }
      else { _selectedCategoryFilter = categoryName; }
    });
    _filterServices();
  }

  @override
  Widget build(BuildContext context) { 
    return RefreshIndicator( onRefresh: _fetchServices, child: ListView( padding: const EdgeInsets.all(16.0), children: [
        _buildWelcomeMessage(), const SizedBox(height: 16), _buildSearchBar(), const SizedBox(height: 20), _buildSectionHeader('Special Offers'), _buildOffersCarousel(), const SizedBox(height: 24), _buildSectionHeader('Categories'), _buildCategoryList(), const SizedBox(height: 24), _buildSectionHeader('All Services'), _buildAllServicesGrid(),
      ],),);
  }

  Widget _buildWelcomeMessage() {
    return Text('Welcome, $_userName!', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),);
  }

  Widget _buildSearchBar() {
    final bool isNearbyActive = _filterByCurrentLocationActive;
    final IconData locationIcon = isNearbyActive ? Icons.location_on : Icons.location_on_outlined;
    final Color locationIconColor = isNearbyActive ? Theme.of(context).colorScheme.error : Theme.of(context).primaryColor;

    String tooltipMessage = 'Tap to show services near your current location';
    if (isNearbyActive) {
        if (_currentLocationDistrict != null && _currentLocationDistrict!.isNotEmpty) {
            tooltipMessage = 'Showing services in $_currentLocationDistrict, ${_currentLocationState ?? "your state"} (Tap to show all)';
        } else if (_currentLocationState != null && _currentLocationState!.isNotEmpty) {
            tooltipMessage = 'Showing services in $_currentLocationState (Tap to show all)';
        } else {
            tooltipMessage = 'Showing services nearby (Tap to show all)'; // Generic if location is somehow active but no state/district
        }
    }

    return Row( /* ... Search bar UI structure remains same ... */
      children: [
        Expanded(child: Card(elevation: 2.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25.0)), child: Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: TextField(controller: _searchController, decoration: const InputDecoration(hintText: 'Search for services (e.g., plumbing)', prefixIcon: Icon(Icons.search, size: 20), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0), isDense: true,),),),),),
        const SizedBox(width: 8),
        Card(elevation: 2.0, shape: const CircleBorder(), child: _isFetchingCurrentLocation ? Container(padding: const EdgeInsets.all(12.0), width: 48, height: 48, child: const CircularProgressIndicator(strokeWidth: 2.0),) : IconButton(icon: Icon(locationIcon, color: locationIconColor), tooltip: tooltipMessage, onPressed: _handleNearbyFilterTap, ),),
      ],
    );
  }

  Widget _buildSectionHeader(String title) { /* ... remains same ... */
    return Padding(padding: const EdgeInsets.only(bottom: 12.0, top: 8.0), child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),),);
  }

  Widget _buildOffersCarousel() { /* ... remains same ... */
    return SizedBox(height: 150, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _offers.length, itemBuilder: (context, index) { final offer = _offers[index]; return Container(width: 300, margin: const EdgeInsets.only(right: 12.0), child: Card(clipBehavior: Clip.antiAlias, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 3, child: Stack(alignment: Alignment.bottomLeft, children: [ Positioned.fill(child: Image.network(offer['image']!, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.error_outline)),)), Container(decoration: BoxDecoration(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)), gradient: LinearGradient(colors: [Colors.black.withOpacity(0.6), Colors.transparent], begin: Alignment.bottomCenter, end: Alignment.topCenter, stops: const [0.0, 0.6],),),), Padding(padding: const EdgeInsets.all(12.0), child: Text(offer['title']!, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 2.0, color: Colors.black54)]), maxLines: 2, overflow: TextOverflow.ellipsis,),),],),),);},),);
  }

  Widget _buildCategoryList() { /* ... remains same ... */
    return SizedBox(height: 100, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _categories.length, itemBuilder: (context, index) { final category = _categories[index]; final bool isSelected = _selectedCategoryFilter == category['name']; final Color backgroundColor = isSelected ? Theme.of(context).primaryColor.withOpacity(0.3) : Theme.of(context).primaryColorLight.withOpacity(0.5); final Color iconColor = Theme.of(context).primaryColorDark; return InkWell(onTap: () => _onCategoryTapped(category['name']), borderRadius: BorderRadius.circular(10), child: Container(width: 85, margin: const EdgeInsets.only(right: 10.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [ CircleAvatar(radius: 30, backgroundColor: backgroundColor, child: Icon(category['icon'], size: 28, color: iconColor),), const SizedBox(height: 8), Text(category['name'], style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,),],),),);},),);
  }

  // *** MODIFIED: All Services Grid empty state message for district priority ***
  Widget _buildAllServicesGrid() {
    if (_isLoadingServices) {
      return const Padding( padding: EdgeInsets.symmetric(vertical: 40.0), child: Center(child: CircularProgressIndicator(strokeWidth: 2.0)),);
    }
    if (_filteredServices.isEmpty) {
        String message = 'No services available right now.\nCheck back later!';
        if (_searchQuery.isNotEmpty) {
            message = 'No services found matching your search "$_searchQuery".';
        } else if (_filterByCurrentLocationActive) {
            if (_currentLocationDistrict != null && _currentLocationDistrict!.isNotEmpty) {
              message = 'No services found for $_currentLocationDistrict, ${_currentLocationState ?? "your state"}.';
            } else if (_currentLocationState != null && _currentLocationState!.isNotEmpty) {
              message = 'No services found for $_currentLocationState (District not specified).';
            } else {
              message = 'No services found for your current area (Location too broad).';
            }
        } else if (_selectedCategoryFilter != null && _selectedCategoryFilter != 'All') {
            message = 'No services found in the "$_selectedCategoryFilter" category.';
        }
        return Center( child: Padding( padding: const EdgeInsets.symmetric(vertical: 32.0), child: Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700]))),);
    }

    return GridView.builder( /* ... GridView structure remains same ... */
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _filteredServices.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount( crossAxisCount: 2, crossAxisSpacing: 12.0, mainAxisSpacing: 12.0, childAspectRatio: 0.8,), itemBuilder: (context, index) {
        final service = _filteredServices[index];
        return Card( shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), clipBehavior: Clip.antiAlias, elevation: 3, child: InkWell( onTap: () { Navigator.push( context, MaterialPageRoute( builder: (context) => ServiceDetailPage(serviceId: service.id),),);}, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Expanded(flex: 3, child: Container(width: double.infinity, color: Colors.grey[200], child: (service.imageUrl != null && service.imageUrl!.isNotEmpty) ? Image.network(service.imageUrl!, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2.0)), errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.error_outline, color: Colors.grey)),) : const Center(child: Icon(Icons.construction, size: 30, color: Colors.grey)),),), Expanded(flex: 2, child: Padding(padding: const EdgeInsets.all(8.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceAround, children: [ Text(service.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), Text('RM ${service.price.toStringAsFixed(2)} (${service.priceType})', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[700]), maxLines: 1, overflow: TextOverflow.ellipsis),],),),),],),),);
      },);
  }
}