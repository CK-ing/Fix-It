import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../models/handyman_services.dart';
import 'service_detail_page.dart';

// Helper class to hold calculated rating information.
class RatingInfo {
  final double averageRating;
  final int ratingCount;

  RatingInfo({this.averageRating = 0.0, this.ratingCount = 0});
}

class HomeownerHomePage extends StatefulWidget {
  const HomeownerHomePage({super.key});

  @override
  State<HomeownerHomePage> createState() => _HomeownerHomePageState();
}

class _HomeownerHomePageState extends State<HomeownerHomePage> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  User? _currentUser;

  // State Variables
  String _userName = "User";
  bool _isLoadingData = true;

  // --- NEW: Notification State ---
  StreamSubscription? _notificationsSubscription;

  // Other state variables...
  String _searchQuery = '';
  String? _selectedCategoryFilter;
  bool _isFetchingCurrentLocation = false;
  String? _currentLocationState;
  String? _currentLocationDistrict;
  bool _filterByCurrentLocationActive = false;
  List<HandymanService> _allServices = [];
  List<HandymanService> _filteredServices = [];
  Map<String, RatingInfo> _ratingsMap = {};
  late PageController _offerPageController;
  Timer? _offerScrollTimer;
  int _currentOfferPage = 0;
  final List<String> _offerImages = [
    'assets/images/offer1.png',
    'assets/images/offer2.png',
    'assets/images/offer3.png',
  ];
  final List<Map<String, dynamic>> _categories = [
    {'name': 'All', 'icon': Icons.apps}, {'name': 'Plumbing', 'icon': Icons.plumbing_outlined}, {'name': 'Electrical', 'icon': Icons.electrical_services_outlined}, {'name': 'Cleaning', 'icon': Icons.cleaning_services_outlined}, {'name': 'Air Cond', 'icon': Icons.ac_unit_outlined}, {'name': 'Painting', 'icon': Icons.format_paint_outlined}, {'name': 'Carpentry', 'icon': Icons.carpenter_outlined}, {'name': 'More', 'icon': Icons.more_horiz},
  ];
  final List<String> _malaysianStates = [
    'Johor', 'Kedah', 'Kelantan', 'Kuala Lumpur', 'Labuan', 'Melaka', 'Negeri Sembilan', 'Pahang', 'Penang', 'Perak', 'Perlis', 'Putrajaya', 'Sabah', 'Sarawak', 'Selangor', 'Terengganu'
  ];

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    _fetchUserData();
    _loadHomepageData();
    _listenForUnreadNotifications(); // Start listening for notifications
    _searchController.addListener(_onSearchChanged);
    
    _offerPageController = PageController(initialPage: _currentOfferPage, viewportFraction: 0.9);
    _startOfferAutoScroll();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _offerPageController.dispose();
    _offerScrollTimer?.cancel();
    _notificationsSubscription?.cancel(); // Cancel notification listener
    super.dispose();
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }
  
  // --- NEW: Real-time listener for the notification indicator ---
  void _listenForUnreadNotifications() {
    if (_currentUser == null) return;
    _notificationsSubscription?.cancel(); // Cancel any old listener
    final notificationsRef = _database.child('notifications/${_currentUser!.uid}');
    
    _notificationsSubscription = notificationsRef.onValue.listen((event) {
      if (!mounted) return;
      bool hasUnread = false;
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        // Check if any notification has isRead: false
        hasUnread = data.values.any((notification) => 
          notification is Map && (notification['isRead'] == false || notification['isRead'] == null)
        );
      }
      setStateIfMounted(() {
      });
    }, onError: (error) {
      print("Error listening for notifications: $error");
    });
  }

  void _startOfferAutoScroll() { /* ... remains same ... */ _offerScrollTimer?.cancel(); _offerScrollTimer = Timer.periodic(const Duration(seconds: 3), (timer) { if (!mounted || !_offerPageController.hasClients) { return; } _currentOfferPage++; if (_currentOfferPage >= _offerImages.length) { _currentOfferPage = 0; _offerPageController.jumpToPage(_currentOfferPage); return; } _offerPageController.animateToPage( _currentOfferPage, duration: const Duration(milliseconds: 500), curve: Curves.easeOut, ); }); }
  Future<void> _loadHomepageData() async { /* ... remains same ... */ if (!mounted) return; setStateIfMounted(() { _isLoadingData = true; }); try { final results = await Future.wait([ _database.child('services').get(), _database.child('reviews').get(), ]); if (!mounted) return; final serviceSnapshot = results[0]; final reviewSnapshot = results[1]; List<HandymanService> services = []; if (serviceSnapshot.exists && serviceSnapshot.value != null) { final data = Map<String, dynamic>.from(serviceSnapshot.value as Map); services = data.entries.map((entry) { final value = Map<String, dynamic>.from(entry.value as Map); return HandymanService.fromMap(value, entry.key); }).toList(); services = services.where((service) => service.isActive).toList(); services.sort((a, b) => b.createdAt.compareTo(a.createdAt)); } Map<String, RatingInfo> ratings = {}; if (reviewSnapshot.exists && reviewSnapshot.value != null) { final data = Map<String, dynamic>.from(reviewSnapshot.value as Map); Map<String, List<int>> tempRatings = {}; data.forEach((reviewId, reviewData) { final reviewMap = Map<String, dynamic>.from(reviewData as Map); final serviceId = reviewMap['serviceId'] as String?; final rating = reviewMap['rating'] as int?; if (serviceId != null && rating != null) { if (!tempRatings.containsKey(serviceId)) { tempRatings[serviceId] = []; } tempRatings[serviceId]!.add(rating); } }); tempRatings.forEach((serviceId, ratingList) { final int ratingCount = ratingList.length; final double averageRating = ratingList.reduce((a, b) => a + b) / ratingCount; ratings[serviceId] = RatingInfo(averageRating: averageRating, ratingCount: ratingCount); }); } setStateIfMounted(() { _allServices = services; _ratingsMap = ratings; _filterServices(applySearchQuery: false); _isLoadingData = false; }); } catch (e) { print("Error loading homepage data: $e"); if (mounted) { setStateIfMounted(() { _isLoadingData = false; }); ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Error loading data: ${e.toString()}'), backgroundColor: Colors.red),); } } }
  Future<void> _fetchUserData() async { /* ... remains same ... */ final user = _auth.currentUser; if (user != null) { try { final snapshot = await _database.child('users').child(user.uid).child('name').get(); if (snapshot.exists && snapshot.value != null && mounted) { setStateIfMounted(() { _userName = snapshot.value.toString(); }); } } catch (e) { print("Error fetching user name: $e"); } } }
  void _onSearchChanged() { if (_searchQuery != _searchController.text.toLowerCase()) { _searchQuery = _searchController.text.toLowerCase(); _filterServices(); } }
  void _filterServices({bool applySearchQuery = true}) { /* ... remains same ... */ if (!mounted) return; List<HandymanService> tempServices = List.from(_allServices); if (_selectedCategoryFilter != null && _selectedCategoryFilter != 'All' && _selectedCategoryFilter != 'More') { tempServices = tempServices.where((s) => s.category == _selectedCategoryFilter).toList(); } if (_filterByCurrentLocationActive) { if (_currentLocationDistrict != null && _currentLocationDistrict!.isNotEmpty) { tempServices = tempServices.where((s) => s.district != null && s.district == _currentLocationDistrict && s.state != null && s.state == _currentLocationState ).toList(); } else if (_currentLocationState != null && _currentLocationState!.isNotEmpty) { tempServices = tempServices.where((s) => s.state == _currentLocationState).toList(); } } if (applySearchQuery && _searchQuery.isNotEmpty) { tempServices = tempServices.where((s) => s.name.toLowerCase().contains(_searchQuery)).toList(); } setState(() { _filteredServices = tempServices; }); }
  Future<void> _handleNearbyFilterTap() async { /* ... remains same ... */ if (_isFetchingCurrentLocation) return; if (_filterByCurrentLocationActive) { setState(() { _filterByCurrentLocationActive = false; _currentLocationState = null; _currentLocationDistrict = null; }); _filterServices(); print("Nearby filter deactivated."); return; } await _getCurrentLocationAndFilter(); }
  Future<void> _getCurrentLocationAndFilter() async { /* ... remains same ... */ if (!mounted) return; setState(() { _isFetchingCurrentLocation = true; }); LocationPermission permission; bool serviceEnabled; serviceEnabled = await Geolocator.isLocationServiceEnabled(); if (!serviceEnabled) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled. Please enable them.'))); setStateIfMounted(() { _isFetchingCurrentLocation = false; }); return; } permission = await Geolocator.checkPermission(); if (permission == LocationPermission.denied) { permission = await Geolocator.requestPermission(); if (permission == LocationPermission.denied) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are denied.'))); setStateIfMounted(() { _isFetchingCurrentLocation = false; }); return; } } if (permission == LocationPermission.deniedForever) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are permanently denied. Please enable them in settings.'))); setStateIfMounted(() { _isFetchingCurrentLocation = false; }); return; } try { Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium); List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude); if (placemarks.isNotEmpty && mounted) { final Placemark place = placemarks.first; final String? geocodedState = place.administrativeArea; final String? geocodedDistrict = place.subAdministrativeArea ?? place.locality; print("Geocoded State: $geocodedState, Geocoded District: $geocodedDistrict"); String snackBarMessage; bool success = false; if (geocodedDistrict != null && geocodedDistrict.isNotEmpty && geocodedState != null && _malaysianStates.contains(geocodedState)) { setState(() { _currentLocationState = geocodedState; _currentLocationDistrict = geocodedDistrict; _filterByCurrentLocationActive = true; }); snackBarMessage = 'Showing services near you in $geocodedDistrict, $geocodedState'; success = true; } else if (geocodedState != null && _malaysianStates.contains(geocodedState)) { setState(() { _currentLocationState = geocodedState; _currentLocationDistrict = null; _filterByCurrentLocationActive = true; }); snackBarMessage = 'Showing services near you in $geocodedState.'; success = true; } else { setState(() { _filterByCurrentLocationActive = false; _currentLocationState = null; _currentLocationDistrict = null; }); snackBarMessage = 'Could not determine a valid location (State/District) for nearby services.'; ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text(snackBarMessage), backgroundColor: Colors.orange), ); } if (success) { _filterServices(); ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text(snackBarMessage), duration: const Duration(seconds: 3)), ); } } else { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not determine placemark for your location.'), backgroundColor: Colors.orange),); } } } catch (e) { print("Error getting location or geocoding: $e"); if (mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Error getting location: ${e.toString()}'), backgroundColor: Colors.red),); } setStateIfMounted(() { _filterByCurrentLocationActive = false; _currentLocationState = null; _currentLocationDistrict = null; }); } finally { setStateIfMounted(() { _isFetchingCurrentLocation = false; }); } }
  void _onCategoryTapped(String categoryName) { /* ... remains same ... */ print('Category Tapped: $categoryName'); if (categoryName == 'More') { ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('More categories feature coming soon!')),); return; } setState(() { if (_selectedCategoryFilter == categoryName || categoryName == 'All') { _selectedCategoryFilter = null; } else { _selectedCategoryFilter = categoryName; } }); _filterServices(); }

  // This `build` method is from WidgetTree, which provides the AppBar.
  // We need to add our notification indicator to the AppBar's actions.
  // The logic for this will now be in `widget_tree.dart`.
  // I will show you that modification after this file.
  @override
  Widget build(BuildContext context) { 
    return RefreshIndicator( onRefresh: _loadHomepageData, child: ListView( padding: const EdgeInsets.all(16.0), children: [
        _buildWelcomeMessage(), const SizedBox(height: 16), _buildSearchBar(), const SizedBox(height: 20), _buildSectionHeader('Special Offers'), _buildOffersCarousel(), const SizedBox(height: 24), _buildSectionHeader('Categories'), _buildCategoryList(), const SizedBox(height: 24), _buildSectionHeader('All Services'), _buildAllServicesGrid(),
      ],),);
  }

  Widget _buildWelcomeMessage() { /* ... */ return Text('Welcome, $_userName!', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),); }
  Widget _buildSearchBar() { /* ... */ final bool isNearbyActive = _filterByCurrentLocationActive; final IconData locationIcon = isNearbyActive ? Icons.location_on : Icons.location_on_outlined; final Color locationIconColor = isNearbyActive ? Theme.of(context).colorScheme.error : Theme.of(context).primaryColor; String tooltipMessage = 'Tap to show services near your current location'; if (isNearbyActive) { if (_currentLocationDistrict != null && _currentLocationDistrict!.isNotEmpty) { tooltipMessage = 'Showing services in $_currentLocationDistrict, ${_currentLocationState ?? "your state"} (Tap to show all)'; } else if (_currentLocationState != null && _currentLocationState!.isNotEmpty) { tooltipMessage = 'Showing services in $_currentLocationState (Tap to show all)'; } else { tooltipMessage = 'Showing services nearby (Tap to show all)'; } } return Row( children: [ Expanded(child: Card(elevation: 2.0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25.0)), child: Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: TextField(controller: _searchController, decoration: const InputDecoration(hintText: 'Search for services (e.g., plumbing)', prefixIcon: Icon(Icons.search, size: 20), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0), isDense: true,),),),),), const SizedBox(width: 8), Card(elevation: 2.0, shape: const CircleBorder(), child: _isFetchingCurrentLocation ? Container(padding: const EdgeInsets.all(12.0), width: 48, height: 48, child: const CircularProgressIndicator(strokeWidth: 2.0),) : IconButton(icon: Icon(locationIcon, color: locationIconColor), tooltip: tooltipMessage, onPressed: _handleNearbyFilterTap, ),), ], ); }
  Widget _buildSectionHeader(String title) { /* ... */ return Padding(padding: const EdgeInsets.only(bottom: 12.0, top: 8.0), child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),),); }
  Widget _buildOffersCarousel() { /* ... */ return SizedBox( height: 150, child: PageView.builder( controller: _offerPageController, itemCount: _offerImages.length, itemBuilder: (context, index) { return Container( margin: const EdgeInsets.symmetric(horizontal: 6.0), child: Card( clipBehavior: Clip.antiAlias, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 3, child: Image.asset( _offerImages[index], fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Center( child: Icon(Icons.error_outline, color: Colors.red), ), ), ), ); }, ), ); }
  Widget _buildCategoryList() { /* ... */ return SizedBox(height: 100, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _categories.length, itemBuilder: (context, index) { final category = _categories[index]; final bool isSelected = _selectedCategoryFilter == category['name']; final Color backgroundColor = isSelected ? Theme.of(context).primaryColor.withOpacity(0.3) : Theme.of(context).primaryColorLight.withOpacity(0.5); final Color iconColor = Theme.of(context).primaryColorDark; return InkWell(onTap: () => _onCategoryTapped(category['name']), borderRadius: BorderRadius.circular(10), child: Container(width: 85, margin: const EdgeInsets.only(right: 10.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [ CircleAvatar(radius: 30, backgroundColor: backgroundColor, child: Icon(category['icon'], size: 28, color: iconColor),), const SizedBox(height: 8), Text(category['name'], style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,),],),),);},),); }
  Widget _buildAllServicesGrid() { /* ... */ if (_isLoadingData) { return const Padding( padding: EdgeInsets.symmetric(vertical: 40.0), child: Center(child: CircularProgressIndicator(strokeWidth: 2.0)),); } if (_filteredServices.isEmpty) { String message = 'No services available right now.\nCheck back later!'; if (_searchQuery.isNotEmpty) { message = 'No services found matching your search "$_searchQuery".'; } else if (_filterByCurrentLocationActive) { if (_currentLocationDistrict != null && _currentLocationDistrict!.isNotEmpty) { message = 'No services found for $_currentLocationDistrict, ${_currentLocationState ?? "your state"}.'; } else if (_currentLocationState != null && _currentLocationState!.isNotEmpty) { message = 'No services found for $_currentLocationState (District not specified).'; } else { message = 'No services found for your current area (Location too broad).'; } } else if (_selectedCategoryFilter != null && _selectedCategoryFilter != 'All') { message = 'No services found in the "$_selectedCategoryFilter" category.'; } return Center( child: Padding( padding: const EdgeInsets.symmetric(vertical: 32.0), child: Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700]))),); } return GridView.builder( shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _filteredServices.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount( crossAxisCount: 2, crossAxisSpacing: 12.0, mainAxisSpacing: 12.0, childAspectRatio: 0.8,), itemBuilder: (context, index) { final service = _filteredServices[index]; final ratingInfo = _ratingsMap[service.id]; return Card( shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), clipBehavior: Clip.antiAlias, elevation: 3, child: InkWell( onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => ServiceDetailPage(serviceId: service.id))); }, child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Expanded( flex: 3, child: Container( width: double.infinity, color: Colors.grey[200], child: (service.imageUrl != null && service.imageUrl!.isNotEmpty) ? Image.network(service.imageUrl!, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2.0)), errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.error_outline, color: Colors.grey))) : const Center(child: Icon(Icons.construction, size: 30, color: Colors.grey)),),), Expanded( flex: 2, child: Padding( padding: const EdgeInsets.all(8.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [ Text(service.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis), Text('RM ${service.price.toStringAsFixed(2)} (${service.priceType})', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[700]), maxLines: 1, overflow: TextOverflow.ellipsis), if (ratingInfo != null && ratingInfo.ratingCount > 0) Row( children: [ Icon(Icons.star_rounded, color: Colors.amber[700], size: 16), const SizedBox(width: 4), Text( '${ratingInfo.averageRating.toStringAsFixed(1)} (${ratingInfo.ratingCount})', style: Theme.of(context).textTheme.bodySmall, ),], ) else Text( 'New', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold), ),],),),), ],),),); },); }

}
