import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'book_service_page.dart'; // Navigation target

// Assuming HandymanService model now includes 'district'
import '../../models/handyman_services.dart'; // Ensure this model has the district field

// TODO: Create and import a UserProfile model if desired
// import 'package:fixit_app_a186687/models/user_profile.dart';

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
  // Make _serviceData a HandymanService object for type safety and easier field access
  HandymanService? _serviceModelData; // *** MODIFIED: Use the model directly ***
  Map<String, dynamic>? _handymanData;
  List<MapEntry<String, dynamic>> _relatedServices = [];

  // Loading and error state
  bool _isLoading = true;
  bool _isLoadingRelated = false;
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
    final favRef = _dbRef.child('users').child(user.uid).child('favouriteServices').child(widget.serviceId);
    _favoritesSubscription = favRef.onValue.listen((event) {
      if (mounted) {
        setState(() { _isFavorited = event.snapshot.exists && event.snapshot.value == true; });
      }
    }, onError: (error) { print("Error listening to favorites: $error"); });
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; _relatedServices = []; _serviceModelData = null; }); // Reset service model data
    try {
      final serviceSnapshot = await _dbRef.child('services').child(widget.serviceId).get();
      if (!mounted) return;
      if (!serviceSnapshot.exists || serviceSnapshot.value == null) throw Exception('Service not found.');

      final serviceDataMap = Map<String, dynamic>.from(serviceSnapshot.value as Map);
      // *** MODIFIED: Create HandymanService instance ***
      _serviceModelData = HandymanService.fromMap(serviceDataMap, widget.serviceId);

      final handymanId = _serviceModelData?.handymanId; // Use data from model
      final category = _serviceModelData?.category;   // Use data from model

      List<Future> futures = [];
      if (handymanId != null && handymanId.isNotEmpty) {
        futures.add(_dbRef.child('users').child(handymanId).get().then((snap) {
          if (mounted && snap.exists && snap.value != null) {
            _handymanData = Map<String, dynamic>.from(snap.value as Map);
          }
        }));
      }

      if (category != null && category.isNotEmpty) {
        _loadRelatedServices(category);
      } else {
        if (mounted) setState(() { _isLoadingRelated = false; });
      }

      if (futures.isNotEmpty) await Future.wait(futures); // Ensure handyman data is loaded

      if (mounted) setState(() { _isLoading = false; });
    } catch (e) {
      print("Error loading service details: $e");
      if (mounted) setState(() { _isLoading = false; _error = "Failed to load service details."; });
    }
  }

  Future<void> _loadRelatedServices(String category) async { /* ... remains same ... */
    if (!mounted) return;
    setState(() { _isLoadingRelated = true; });
    try {
      final query = _dbRef.child('services').orderByChild('category').equalTo(category);
      final snapshot = await query.get();
      List<MapEntry<String, dynamic>> related = [];
      if (snapshot.exists && snapshot.value != null) {
        final dynamic snapshotValue = snapshot.value;
        if (snapshotValue is Map) {
          final data = Map<String, dynamic>.from(snapshotValue.cast<String, dynamic>());
          related = data.entries
              .map((entry) {
                try {
                  if (entry.value is Map) { return MapEntry(entry.key, Map<String, dynamic>.from(entry.value as Map)); }
                  else { return null; }
                } catch (mapError) { return null; }
              })
              .where((entry) => entry != null && entry.key != widget.serviceId)
              .cast<MapEntry<String, dynamic>>()
              .take(5).toList();
        }
      }
      if (mounted) setState(() { _relatedServices = related; });
    } catch (e) {
      print("Error executing related services query: $e");
      if (mounted) setState(() { _relatedServices = []; });
    } finally { if (mounted) setState(() { _isLoadingRelated = false; }); }
  }

  Future<void> _toggleFavorite() async { /* ... remains same ... */
    if (_isTogglingFavorite) return;
    final user = _auth.currentUser;
    if (user == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to manage favorites.'))); return; }
    setState(() { _isTogglingFavorite = true; });
    final favRef = _dbRef.child('users').child(user.uid).child('favouriteServices').child(widget.serviceId);
    final currentlyFavorited = _isFavorited;
    try {
      if (currentlyFavorited) { await favRef.remove(); }
      else { await favRef.set(true); }
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar( SnackBar( content: Text(currentlyFavorited ? 'Removed from favorites.' : 'Added to favorites!'), duration: const Duration(seconds: 2), backgroundColor: currentlyFavorited ? Colors.black87 : Colors.red,),);
      }
    } catch (e) { if (mounted) {ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating favorites: ${e.toString()}'))); } print("Error toggling favorite: $e"); }
    finally { if (mounted) setState(() { _isTogglingFavorite = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    // *** MODIFIED: Use _serviceModelData for title ***
    String appBarTitle = _isLoading ? 'Loading...' : (_serviceModelData?.name ?? 'Service Details');
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar( /* ... AppBar remains same ... */
        title: Text(appBarTitle, overflow: TextOverflow.ellipsis),
        elevation: 0.5, 
        backgroundColor: Theme.of(context).colorScheme.surface, 
        foregroundColor: Theme.of(context).colorScheme.onSurface, 
        actions: [ if (!_isLoading && _serviceModelData != null) IconButton( icon: Icon(_isFavorited ? Icons.favorite : Icons.favorite_border, color: _isFavorited ? Colors.red : null), tooltip: _isFavorited ? 'Remove from Favorites' : 'Add to Favorites', onPressed: _isTogglingFavorite ? null : _toggleFavorite,), const SizedBox(width: 8),],
      ),
      body: _buildBody(),
      bottomNavigationBar: SafeArea( child: _buildBookingButtonContainer(),)
    );
  }

  Widget _buildBody() {
    if (_isLoading) { return const Center(child: CircularProgressIndicator()); }
    if (_error != null) { return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),)); }
    // *** MODIFIED: Check _serviceModelData ***
    if (_serviceModelData == null) { return const Center(child: Text('Service data not available.')); }

    return SingleChildScrollView( /* ... Column structure remains same ... */
      padding: const EdgeInsets.only(bottom: 100),
      child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildServiceImage(),
          Container(color: Theme.of(context).cardColor, padding: const EdgeInsets.all(16.0), margin: const EdgeInsets.only(bottom: 10.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildServiceDetailsSection(), const Divider(height: 24, thickness: 0.5), _buildDescriptionContent(), ],),),
          Container(color: Theme.of(context).cardColor, padding: const EdgeInsets.all(16.0), margin: const EdgeInsets.only(bottom: 10.0), child: _buildHandymanInfoContent(),),
          Container(color: Theme.of(context).cardColor, padding: const EdgeInsets.all(16.0), margin: const EdgeInsets.only(bottom: 10.0), child: _buildReviewsContent(),),
          Container(color: Theme.of(context).cardColor, padding: const EdgeInsets.all(16.0), child: _buildRelatedServicesContent(),),
        ],
      ),
    );
  }

  Widget _buildServiceImage() {
    // *** MODIFIED: Use _serviceModelData ***
    final imageUrl = _serviceModelData?.imageUrl;
    return Container( /* ... remains same ... */
      height: 250, width: double.infinity, color: Colors.grey[300], child: (imageUrl != null && imageUrl.isNotEmpty) ? Image.network( imageUrl, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 50)),) : const Center(child: Icon(Icons.construction, color: Colors.grey, size: 50)),
    );
  }

  Widget _buildServiceDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // *** MODIFIED: Use _serviceModelData ***
          _serviceModelData?.name ?? 'Service Name',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildServiceInfoChips(), // This will be modified next
      ],
    );
  }

  // *** MODIFIED: Widget _buildServiceInfoChips to include district ***
  Widget _buildServiceInfoChips() {
    if (_serviceModelData == null) return const SizedBox.shrink();

    final price = _serviceModelData!.price;
    final priceType = _serviceModelData!.priceType;
    final category = _serviceModelData!.category;
    final serviceState = _serviceModelData!.state; // State of the service
    final serviceDistrict = _serviceModelData!.district; // NEW: District of the service

    List<Widget> chips = [];

    // Price Chip
    chips.add(Chip(
      avatar: Icon(Icons.attach_money, size: 16, color: Colors.green[800]),
      label: Text('RM ${price.toStringAsFixed(2)} ${priceType.isNotEmpty ? "($priceType)" : ""}'),
      backgroundColor: Colors.green.withOpacity(0.1),
      labelStyle: TextStyle(color: Colors.green[900], fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    ));

    // Category Chip
    if (category.isNotEmpty) {
      chips.add(Chip(
        avatar: Icon(Icons.category_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
        label: Text(category),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        labelStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
      ));
    }

    // Location Chip (State and District)
    String locationText = serviceState;
    if (serviceDistrict != null && serviceDistrict.isNotEmpty) {
      locationText = '$serviceDistrict, $serviceState';
    }
    if (locationText.isNotEmpty) {
        chips.add(Chip(
        avatar: Icon(Icons.location_on_outlined, size: 16, color: Theme.of(context).colorScheme.tertiary),
        label: Text(locationText),
        backgroundColor: Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.3),
        labelStyle: TextStyle(color: Theme.of(context).colorScheme.onTertiaryContainer, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        visualDensity: VisualDensity.compact,
        side: BorderSide.none,
        ));
    }


    return Wrap(
      spacing: 8.0,
      runSpacing: 6.0,
      children: chips,
    );
  }

  Widget _buildDescriptionContent() {
    // *** MODIFIED: Use _serviceModelData ***
    final description = _serviceModelData?.description ?? 'No description available.';
    return Column( /* ... remains same ... */
      crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Description'), const SizedBox(height: 8), Text(description, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant),),],
    );
  }

  Widget _buildHandymanInfoContent() { /* ... remains same, uses _handymanData and _serviceModelData?.handymanId ... */
    if (_handymanData == null) { return Row(children: [ Icon(Icons.person_off_outlined, color: Colors.grey[600]), const SizedBox(width: 8), Text('Handyman details unavailable', style: TextStyle(color: Colors.grey[600])),],); }
    final handymanName = _handymanData?['name'] ?? 'Handyman Name'; final handymanImageUrl = _handymanData?['profileImageUrl'] as String?; final String handymanRatingDisplay = 'N/A'; // Placeholder
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Provided by'), const SizedBox(height: 8), ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: CircleAvatar(radius: 24, backgroundColor: Colors.grey[200], backgroundImage: (handymanImageUrl != null && handymanImageUrl.isNotEmpty) ? NetworkImage(handymanImageUrl) : null, child: (handymanImageUrl == null || handymanImageUrl.isEmpty) ? const Icon(Icons.person, color: Colors.grey, size: 24) : null,), title: Text(handymanName, style: Theme.of(context).textTheme.titleMedium), subtitle: Row(mainAxisSize: MainAxisSize.min, children: [ Icon(Icons.star, color: Colors.amber[600], size: 16), const SizedBox(width: 4), Text('Rating: $handymanRatingDisplay', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700])),],), trailing: const Icon(Icons.chevron_right, size: 20), onTap: () { final handymanId = _serviceModelData?.handymanId; if (handymanId != null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Handyman profile page coming soon!')),);}},),],);
  }

  Widget _buildRelatedServicesContent() { /* ... remains same ... */
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Related Services'), const SizedBox(height: 12), _buildRelatedServicesList(),],);
  }

  Widget _buildRelatedServicesList() { /* ... remains same ... */
    if (_isLoadingRelated) { return const Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Center(child: CircularProgressIndicator())); }
    if (_relatedServices.isEmpty) { return const Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Center(child: Text('No related services found.'))); }
    return ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _relatedServices.length, itemBuilder: (context, index) { final entry = _relatedServices[index]; final relatedServiceId = entry.key; final relatedServiceData = entry.value; final imageUrl = relatedServiceData['imageUrl'] as String?; final name = relatedServiceData['name'] ?? 'Service'; final price = (relatedServiceData['price'] as num?)?.toDouble() ?? 0.0; final priceType = relatedServiceData['priceType'] ?? '';
      return ListTile(contentPadding: const EdgeInsets.symmetric(vertical: 6.0), dense: true, leading: ClipRRect(borderRadius: BorderRadius.circular(8.0), child: Container(width: 60, height: 60, color: Colors.grey[200], child: (imageUrl != null && imageUrl.isNotEmpty) ? Image.network(imageUrl, fit: BoxFit.cover) : const Icon(Icons.construction, size: 24, color: Colors.grey),),), title: Text(name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis,), subtitle: Text('RM ${price.toStringAsFixed(2)} ${priceType.isNotEmpty ? "($priceType)" : ""}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[800]), maxLines: 1, overflow: TextOverflow.ellipsis,), trailing: const Icon(Icons.chevron_right, size: 20), onTap: () { Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ServiceDetailPage(serviceId: relatedServiceId),),);},);},);
  }

  Widget _buildReviewsContent() { /* ... remains same ... */
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Reviews'), const SizedBox(height: 8), const Center(child: Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Text('Reviews coming soon!', style: TextStyle(color: Colors.grey)),)),],);
  }

  Widget _buildSectionTitle(String title) { /* ... remains same ... */
    return Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant),),);
  }

  Widget _buildBookingButtonContainer() {
    // *** MODIFIED: Check _serviceModelData and use it for handymanId ***
    if (_isLoading || _serviceModelData == null) { return const SizedBox.shrink(); }
    return Container( /* ... styling ... */
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0), decoration: BoxDecoration( color: Theme.of(context).colorScheme.surface, boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, -2),)],),
      child: ElevatedButton.icon( /* ... styling ... */
        icon: const Icon(Icons.calendar_month_outlined), label: const Text('Check Availability & Book'), style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 14), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary,),
        onPressed: () {
          // *** MODIFIED: Use _serviceModelData for handymanId ***
          final String? currentHandymanId = _serviceModelData?.handymanId;
          if (currentHandymanId != null && currentHandymanId.isNotEmpty) { // Add empty check
            Navigator.push( context, MaterialPageRoute( builder: (context) => BookServicePage( serviceId: widget.serviceId, handymanId: currentHandymanId,),),);
          } else {
            ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Cannot proceed: Handyman details are missing for this service.')),);
            print('Error: Handyman ID is null or empty for service ${widget.serviceId}');
          }
        }
      )
    );
  }
}