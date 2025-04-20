import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'book_service_page.dart';

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
  Map<String, dynamic>? _serviceData;
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

  // Listen for real-time changes to the favorite status
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

  // Load main service data, handyman data, and trigger related services load
  Future<void> _loadData() async {
    // ... (load data logic remains the same) ...
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; _relatedServices = []; });
    try {
      final serviceSnapshot = await _dbRef.child('services').child(widget.serviceId).get();
      if (!mounted) return;
      if (!serviceSnapshot.exists || serviceSnapshot.value == null) throw Exception('Service not found.');

      final serviceDataMap = Map<String, dynamic>.from(serviceSnapshot.value as Map);
      _serviceData = serviceDataMap;
      final handymanId = serviceDataMap['handymanId'];
      final category = serviceDataMap['category'];

      List<Future> futures = [];
      if (handymanId != null) {
        futures.add(_dbRef.child('users').child(handymanId).get().then((snap) {
          if (mounted && snap.exists && snap.value != null) {
            _handymanData = Map<String, dynamic>.from(snap.value as Map);
          }
        }));
      }
      if (category != null) {
         _loadRelatedServices(category);
      }
      await Future.wait(futures);
      if (mounted) setState(() { _isLoading = false; });
    } catch (e) {
      print("Error loading service details: $e");
      if (mounted) setState(() { _isLoading = false; _error = "Failed to load service details."; });
    }
  }

  // Load related services based on category
  Future<void> _loadRelatedServices(String category) async {
    // ... (load related services logic remains the same - including take(5)) ...
     if (!mounted) return;
     setState(() { _isLoadingRelated = true; });
     print("Loading related services for category: $category");
     try {
        final query = _dbRef.child('services').orderByChild('category').equalTo(category);
        final snapshot = await query.get();
        List<MapEntry<String, dynamic>> related = [];
        if (snapshot.exists && snapshot.value != null) {
           final dynamic snapshotValue = snapshot.value;
           if (snapshotValue is Map) {
              try {
                 final data = Map<String, dynamic>.from(snapshotValue.cast<String, dynamic>());
                 related = data.entries
                    .map((entry) {
                       try {
                          if (entry.value is Map) { return MapEntry(entry.key, Map<String, dynamic>.from(entry.value as Map)); }
                          else { print("Skipping related service entry ${entry.key} because its value is not a Map: ${entry.value}"); return null; }
                       } catch (mapError) { print("Error processing related service entry ${entry.key}: $mapError"); return null; }
                    })
                    .where((entry) => entry != null && entry.key != widget.serviceId)
                    .cast<MapEntry<String, dynamic>>()
                    .take(5) // Limit to 5 items
                    .toList();
                 print("Processed related services (max 5): ${related.length} items found.");
              } catch (castError) { print("Error casting snapshot value to Map<String, dynamic>: $castError"); }
           } else { print("Related services data for category '$category' is not a Map."); }
        } else { print("No snapshot exists for category '$category'"); }
        if (mounted) setState(() { _relatedServices = related; });
     } catch (e) {
        print("Error executing related services query: $e");
        if (mounted) setState(() { _relatedServices = []; });
     } finally { if (mounted) setState(() { _isLoadingRelated = false; }); }
  }

  // Toggle favorite status in Firebase
  Future<void> _toggleFavorite() async {
    // ... (toggle favorite logic remains the same - including snackbar colors) ...
     if (_isTogglingFavorite) return;
     final user = _auth.currentUser;
     if (user == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to manage favorites.'))); return; }
     setState(() { _isTogglingFavorite = true; });
     final favRef = _dbRef.child('users').child(user.uid).child('favouriteServices').child(widget.serviceId);
     final currentlyFavorited = _isFavorited;
     try {
        if (currentlyFavorited) {
           await favRef.remove();
           if (mounted) { ScaffoldMessenger.of(context).showSnackBar( const SnackBar( content: Text('Removed from favorites.'), duration: Duration(seconds: 2), backgroundColor: Colors.black87,),); }
        } else {
           await favRef.set(true);
            if (mounted) { ScaffoldMessenger.of(context).showSnackBar( const SnackBar( content: Text('Added to favorites!'), duration: Duration(seconds: 2), backgroundColor: Colors.red,),); }
        }
     } catch (e) {
        print("Error toggling favorite: $e");
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Error updating favorites: ${e.toString()}'))); }
     } finally { if (mounted) setState(() { _isTogglingFavorite = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    String appBarTitle = _isLoading ? 'Loading...' : (_serviceData?['name'] ?? 'Service Details');
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(appBarTitle, overflow: TextOverflow.ellipsis),
        elevation: 1.0,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? Colors.white,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        actions: [
           if (!_isLoading)
              IconButton( icon: Icon(_isFavorited ? Icons.favorite : Icons.favorite_border, color: _isFavorited ? Colors.red : null), tooltip: _isFavorited ? 'Remove from Favorites' : 'Add to Favorites', onPressed: _isTogglingFavorite ? null : _toggleFavorite,),
           const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: SafeArea( child: _buildBookingButtonContainer(),)
    );
  }

  // Build the main body content
  Widget _buildBody() {
    if (_isLoading) { return const Center(child: CircularProgressIndicator()); }
    if (_error != null) { return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),)); }
    if (_serviceData == null) { return const Center(child: Text('Service data not available.')); }

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _buildServiceImage(),
        // Card 1: Service Details + Description
        _buildCardWrapper(
           child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                 _buildServiceDetailsSection(),
                 const Divider(height: 24, thickness: 1),
                 _buildDescriptionContent(),
              ],)
        ),
        // Card 2: Handyman Info (Title inside)
        _buildCardWrapper(child: _buildHandymanInfoContent()),
        // Card 3: Reviews Placeholder (Title inside)
        _buildCardWrapper(child: _buildReviewsContent()),
        // Card 4: Related Services (Title inside)
        _buildCardWrapper(child: _buildRelatedServicesContent()),
      ],
    );
  }

  // --- Helper Widgets ---

  // Helper to wrap content sections in a styled Card
  Widget _buildCardWrapper({required Widget child}) {
     return Card( margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), elevation: 1.5, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), color: Theme.of(context).cardColor, child: Padding( padding: const EdgeInsets.all(16.0), child: child,),);
  }

  Widget _buildServiceImage() { /* ... remains same ... */
    final imageUrl = _serviceData?['imageUrl'] as String?;
    return Container( height: 250, width: double.infinity, color: Colors.grey[200], child: (imageUrl != null && imageUrl.isNotEmpty) ? Image.network( imageUrl, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 50)),) : const Center(child: Icon(Icons.construction, color: Colors.grey, size: 50)),);
  }

  // Builds Service Title and Chips (Part 1 of Card 1)
  Widget _buildServiceDetailsSection() {
     return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text( _serviceData?['name'] ?? 'Service Name', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),), const SizedBox(height: 16), _buildServiceInfoChips(),],);
  }

  Widget _buildServiceInfoChips() { /* ... remains same ... */
    final price = (_serviceData?['price'] as num?)?.toDouble() ?? 0.0;
    final priceType = _serviceData?['priceType'] ?? '';
    final category = _serviceData?['category'] ?? '';
    return Wrap( spacing: 8.0, runSpacing: 4.0, children: [ Chip( avatar: Icon(Icons.attach_money, size: 18, color: Colors.green[800]), label: Text('RM ${price.toStringAsFixed(2)} ${priceType.isNotEmpty ? "($priceType)" : ""}'), backgroundColor: Colors.green[50], labelStyle: TextStyle(color: Colors.green[900]), visualDensity: VisualDensity.compact, side: BorderSide.none,), if (category.isNotEmpty) Chip( avatar: Icon(Icons.category_outlined, size: 18, color: Theme.of(context).colorScheme.secondary), label: Text(category), backgroundColor: Theme.of(context).colorScheme.secondaryContainer, labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer), visualDensity: VisualDensity.compact, side: BorderSide.none,),],);
  }

  // Builds Description Content (Part 2 of Card 1, Title inside)
  Widget _buildDescriptionContent() {
    final description = _serviceData?['description'] ?? 'No description available.';
    return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Description'), const SizedBox(height: 8), Text( description, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),],);
  }

  // Builds Handyman Info CONTENT (Title inside)
  Widget _buildHandymanInfoContent() {
    if (_handymanData == null) { return const ListTile( leading: CircleAvatar(child: Icon(Icons.person_off_outlined)), title: Text('Handyman details unavailable'), dense: true, ); }
    final handymanName = _handymanData?['name'] ?? 'Handyman Name';
    final handymanImageUrl = _handymanData?['profileImageUrl'] as String?;
    return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionTitle('Provided by'),
        const SizedBox(height: 12),
        ListTile(
            // *** Added consistent padding and dense property ***
            contentPadding: const EdgeInsets.symmetric(vertical: 4.0), // Adjust vertical padding
            dense: true, // Make it dense like related items potentially
            leading: CircleAvatar( radius: 28, backgroundColor: Colors.grey[200], backgroundImage: (handymanImageUrl != null && handymanImageUrl.isNotEmpty) ? NetworkImage(handymanImageUrl) : null, child: (handymanImageUrl == null || handymanImageUrl.isEmpty) ? const Icon(Icons.person, color: Colors.grey) : null,),
            title: Text(handymanName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            subtitle: const Row( mainAxisSize: MainAxisSize.min, children: [ Icon(Icons.star_border, color: Colors.amber, size: 18), SizedBox(width: 4), Text('Rating N/A', style: TextStyle(color: Colors.grey)),],),
            trailing: Icon(Icons.chevron_right, color: Theme.of(context).primaryColor),
            onTap: () { /* Navigate to Handyman Profile */ final handymanId = _serviceData?['handymanId']; if (handymanId != null) { print('Navigate to profile for handyman: $handymanId'); ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Handyman profile page coming soon!')),); } },
        ),
     ],);
  }

  // Builds Related Services CONTENT (Title inside)
  Widget _buildRelatedServicesContent() {
     return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Related Services'), const SizedBox(height: 12), _buildRelatedServicesList(),],);
  }

  // Builds the VERTICAL list of related services
  Widget _buildRelatedServicesList() {
     if (_isLoadingRelated) { return const Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Center(child: CircularProgressIndicator())); }
     if (_relatedServices.isEmpty) { return const Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Center(child: Text('No related services found.'))); }

     // Use ListView.builder for vertical list
     return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _relatedServices.length,
        itemBuilder: (context, index) {
           final entry = _relatedServices[index];
           final relatedServiceId = entry.key;
           final relatedServiceData = entry.value;
           final imageUrl = relatedServiceData['imageUrl'] as String?;
           final name = relatedServiceData['name'] ?? 'Service';
           final price = (relatedServiceData['price'] as num?)?.toDouble() ?? 0.0;
           final priceType = relatedServiceData['priceType'] ?? '';

           // Build a ListTile for each related service
           return ListTile( // Removed extra Padding wrapper
              // *** Added consistent padding and dense property ***
              contentPadding: const EdgeInsets.symmetric(vertical: 4.0), // Match handyman info padding
              dense: true, // Make it dense
              leading: ClipRRect(
                 borderRadius: BorderRadius.circular(8.0),
                 child: Container(
                    // *** Match Handyman Avatar Size (approx 56x56) ***
                    width: 56, height: 56, color: Colors.grey[200],
                    child: (imageUrl != null && imageUrl.isNotEmpty)
                       ? Image.network(imageUrl, fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
                          errorBuilder: (context, error, stack) => const Icon(Icons.error_outline, color: Colors.grey),
                         )
                       : const Icon(Icons.construction, size: 24, color: Colors.grey),
                 ),
              ),
              title: Text(
                 name,
                 // Use titleSmall like Handyman name for consistency, or keep bodyMedium
                 style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                 maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                 'RM ${price.toStringAsFixed(2)} ${priceType.isNotEmpty ? "($priceType)" : ""}',
                 // Use bodySmall like Handyman rating for consistency
                 style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[800]),
                 maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                 Navigator.pushReplacement(
                    context,
                    MaterialPageRoute( builder: (context) => ServiceDetailPage(serviceId: relatedServiceId),),
                 );
              },
           );
        },
     );
  }

  // Builds Reviews Placeholder CONTENT (Title inside)
  Widget _buildReviewsContent() {
     return Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ _buildSectionTitle('Reviews'), const SizedBox(height: 8), const Center(child: Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Text('Reviews coming soon!', style: TextStyle(color: Colors.grey)),)),],);
  }

  // Helper for section titles (remains same)
  Widget _buildSectionTitle(String title) {
     return Text( title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),);
  }

  // Build container for sticky button (remains same)
  Widget _buildBookingButtonContainer() {
     if (_isLoading || _serviceData == null) { return const SizedBox.shrink(); }
     return Container( padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0), decoration: BoxDecoration( color: Theme.of(context).scaffoldBackgroundColor, boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, -2),)],), child: ElevatedButton.icon( icon: const Icon(Icons.calendar_month_outlined), label: const Text('Check Availability & Book'), style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(vertical: 14), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),), 
     onPressed: () {
  // Get the handymanId from the fetched service data
  final String? currentHandymanId = _serviceData?['handymanId'] as String?;

  // Ensure handymanId is available before navigating
  if (currentHandymanId != null) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookServicePage(
          serviceId: widget.serviceId, // Pass the current serviceId
          handymanId: currentHandymanId, // Pass the handymanId
        ),
      ),
    );
  } else {
    // Optional: Show an error if handymanId is missing for some reason
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cannot proceed: Handyman details are missing for this service.')),
    );
    print('Error: Handyman ID is null for service ${widget.serviceId}');
  }
     })
     );}
}
