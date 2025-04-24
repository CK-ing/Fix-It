import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'book_service_page.dart'; // Navigation target

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

 // Data state (remains the same)
 Map<String, dynamic>? _serviceData;
 Map<String, dynamic>? _handymanData;
 List<MapEntry<String, dynamic>> _relatedServices = [];

 // Loading and error state (remains the same)
 bool _isLoading = true;
 bool _isLoadingRelated = false;
 String? _error;

 // Favorite state (remains the same)
 bool _isFavorited = false;
 bool _isTogglingFavorite = false;
 StreamSubscription? _favoritesSubscription;

 // --- Lifecycle methods (initState, dispose) remain the same ---
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

 // --- Data Fetching & Favorite Logic (_listenToFavorites, _loadData, _loadRelatedServices, _toggleFavorite) remain the same ---
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
     // Trigger related services load immediately if category exists
     if (category != null) {
       _loadRelatedServices(category);
     } else {
       // If no category, stop related loading immediately
        if (mounted) setState(() { _isLoadingRelated = false; });
     }

     // Wait only for essential data (handyman) before showing main content
     await Future.wait(futures);
     if (mounted) setState(() { _isLoading = false; });
   } catch (e) {
     print("Error loading service details: $e");
     if (mounted) setState(() { _isLoading = false; _error = "Failed to load service details."; });
   }
 }

 Future<void> _loadRelatedServices(String category) async {
   if (!mounted) return;
   // Don't reset main loading, just related loading
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
               .map((entry) { /* ... (Map entry logic remains same) ... */
                 try {
                   if (entry.value is Map) { return MapEntry(entry.key, Map<String, dynamic>.from(entry.value as Map)); }
                   else { return null; }
                 } catch (mapError) { return null; }
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

 Future<void> _toggleFavorite() async {
   if (_isTogglingFavorite) return;
   final user = _auth.currentUser;
   if (user == null) { /* Show login message */ return; }
   setState(() { _isTogglingFavorite = true; });
   final favRef = _dbRef.child('users').child(user.uid).child('favouriteServices').child(widget.serviceId);
   final currentlyFavorited = _isFavorited;
   try {
     if (currentlyFavorited) { /* Remove favorite */ await favRef.remove(); }
     else { /* Add favorite */ await favRef.set(true); }
     // Show appropriate SnackBar
     if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar( SnackBar( content: Text(currentlyFavorited ? 'Removed from favorites.' : 'Added to favorites!'), duration: Duration(seconds: 2), backgroundColor: currentlyFavorited ? Colors.black87 : Colors.red,),);
     }
   } catch (e) { /* Handle error */ }
   finally { if (mounted) setState(() { _isTogglingFavorite = false; }); }
 }


 @override
 Widget build(BuildContext context) {
   String appBarTitle = _isLoading ? 'Loading...' : (_serviceData?['name'] ?? 'Service Details');
   return Scaffold(
     backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest, // Use a subtle background
     appBar: AppBar(
       title: Text(appBarTitle, overflow: TextOverflow.ellipsis),
       elevation: 0.5, // Subtle elevation
       backgroundColor: Theme.of(context).colorScheme.surface, // Appbar background
       foregroundColor: Theme.of(context).colorScheme.onSurface, // Appbar text/icons
       actions: [
         if (!_isLoading)
           IconButton(
             icon: Icon(_isFavorited ? Icons.favorite : Icons.favorite_border,
                 color: _isFavorited ? Colors.red : null),
             tooltip: _isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
             onPressed: _isTogglingFavorite ? null : _toggleFavorite,
           ),
         const SizedBox(width: 8),
       ],
     ),
     // *** Use SingleChildScrollView instead of ListView ***
     body: _buildBody(),
     bottomNavigationBar: SafeArea( child: _buildBookingButtonContainer(),)
   );
 }

 // Build the main body content
 Widget _buildBody() {
   if (_isLoading) { return const Center(child: CircularProgressIndicator()); }
   if (_error != null) { return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),)); }
   if (_serviceData == null) { return const Center(child: Text('Service data not available.')); }

   // Use SingleChildScrollView for flexibility with content height
   return SingleChildScrollView(
     // Padding added to bottom to ensure content isn't hidden by booking button
     padding: const EdgeInsets.only(bottom: 100),
     child: Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         _buildServiceImage(), // Image takes full width

         // --- Section 1: Main Details & Description ---
         Container(
           // Use card color from theme for contrast with scaffold background
           color: Theme.of(context).cardColor,
           padding: const EdgeInsets.all(16.0),
           margin: const EdgeInsets.only(bottom: 10.0), // Space below this section
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
               _buildServiceDetailsSection(), // Name and Chips
               const Divider(height: 24, thickness: 0.5), // Thinner divider
               _buildDescriptionContent(), // Description Title + Text
             ],
           ),
         ),

         // --- Section 2: Handyman Info ---
         Container(
           color: Theme.of(context).cardColor,
           padding: const EdgeInsets.all(16.0),
           margin: const EdgeInsets.only(bottom: 10.0),
           child: _buildHandymanInfoContent(), // Provided By Title + ListTile
         ),

         // --- Section 3: Reviews ---
         Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.all(16.0),
            margin: const EdgeInsets.only(bottom: 10.0),
            child: _buildReviewsContent(), // Reviews Title + Placeholder
         ),

         // --- Section 4: Related Services ---
          Container(
             color: Theme.of(context).cardColor,
             padding: const EdgeInsets.all(16.0),
             child: _buildRelatedServicesContent(), // Related Title + List
          ),

       ],
     ),
   );
 }

 // --- Helper Widgets ---

 // Removed _buildCardWrapper as we now use Containers with background color

 Widget _buildServiceImage() {
   final imageUrl = _serviceData?['imageUrl'] as String?;
   // Keep image prominent
   return Container(
     height: 250, // Or adjust as needed
     width: double.infinity,
     color: Colors.grey[300], // Placeholder color
     child: (imageUrl != null && imageUrl.isNotEmpty)
         ? Image.network(
             imageUrl,
             fit: BoxFit.cover,
             loadingBuilder: (context, child, progress) =>
                 progress == null ? child : const Center(child: CircularProgressIndicator()),
             errorBuilder: (context, error, stack) =>
                 const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 50)),
           )
         : const Center(child: Icon(Icons.construction, color: Colors.grey, size: 50)),
   );
 }

 // Builds Service Title and Chips (Styling updated)
 Widget _buildServiceDetailsSection() {
   return Column(
     crossAxisAlignment: CrossAxisAlignment.start,
     children: [
       Text(
         _serviceData?['name'] ?? 'Service Name',
         style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), // Adjusted style
       ),
       const SizedBox(height: 12), // Reduced spacing
       _buildServiceInfoChips(),
     ],
   );
 }

 Widget _buildServiceInfoChips() {
   final price = (_serviceData?['price'] as num?)?.toDouble() ?? 0.0;
   final priceType = _serviceData?['priceType'] ?? '';
   final category = _serviceData?['category'] ?? '';
   // Use slightly different chip styling for better integration
   return Wrap(
     spacing: 8.0,
     runSpacing: 6.0,
     children: [
       Chip(
         avatar: Icon(Icons.attach_money, size: 16, color: Colors.green[800]),
         label: Text('RM ${price.toStringAsFixed(2)} ${priceType.isNotEmpty ? "($priceType)" : ""}'),
         backgroundColor: Colors.green.withOpacity(0.1), // Subtle background
         labelStyle: TextStyle(color: Colors.green[900], fontSize: 13),
         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
         visualDensity: VisualDensity.compact,
         side: BorderSide.none,
       ),
       if (category.isNotEmpty)
         Chip(
           avatar: Icon(Icons.category_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
           label: Text(category),
           backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3), // Subtle background
           labelStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontSize: 13),
           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
           visualDensity: VisualDensity.compact,
           side: BorderSide.none,
         ),
     ],
   );
 }

 // Builds Description Content (Styling updated)
 Widget _buildDescriptionContent() {
   final description = _serviceData?['description'] ?? 'No description available.';
   return Column(
     crossAxisAlignment: CrossAxisAlignment.start,
     children: [
       _buildSectionTitle('Description'),
       const SizedBox(height: 8),
       Text(
         description,
         style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5, color: Theme.of(context).colorScheme.onSurfaceVariant), // Slightly lighter text
       ),
     ],
   );
 }

 // Builds Handyman Info CONTENT (Styling updated)
 Widget _buildHandymanInfoContent() {
   if (_handymanData == null) {
     // Show a simpler placeholder if data is missing
     return Row(
       children: [
          Icon(Icons.person_off_outlined, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text('Handyman details unavailable', style: TextStyle(color: Colors.grey[600])),
       ],
     );
   }
   final handymanName = _handymanData?['name'] ?? 'Handyman Name';
   final handymanImageUrl = _handymanData?['profileImageUrl'] as String?;
   // TODO: Fetch and calculate actual rating later
   final String handymanRatingDisplay = 'N/A'; // Placeholder

   return Column(
     crossAxisAlignment: CrossAxisAlignment.start,
     children: [
       _buildSectionTitle('Provided by'),
       const SizedBox(height: 8), // Reduced space
       ListTile(
         contentPadding: EdgeInsets.zero, // Use zero padding, control spacing outside
         dense: true,
         leading: CircleAvatar(
           radius: 24, // Slightly smaller avatar
           backgroundColor: Colors.grey[200],
           backgroundImage: (handymanImageUrl != null && handymanImageUrl.isNotEmpty)
               ? NetworkImage(handymanImageUrl) : null,
           child: (handymanImageUrl == null || handymanImageUrl.isEmpty)
               ? const Icon(Icons.person, color: Colors.grey, size: 24) : null,
         ),
         title: Text(
            handymanName,
            style: Theme.of(context).textTheme.titleMedium // Use titleMedium
         ),
         subtitle: Row(
           mainAxisSize: MainAxisSize.min,
           children: [
             Icon(Icons.star, color: Colors.amber[600], size: 16), // Filled star
             const SizedBox(width: 4),
             Text(
                'Rating: $handymanRatingDisplay', // Display actual rating here
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700])
             ),
           ],
         ),
         trailing: const Icon(Icons.chevron_right, size: 20), // Smaller chevron
         onTap: () {
           /* Navigate to Handyman Profile */
           final handymanId = _serviceData?['handymanId'];
           if (handymanId != null) {
             print('Navigate to profile for handyman: $handymanId');
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Handyman profile page coming soon!')),
             );
           }
         },
       ),
     ],
   );
 }

 // Builds Related Services CONTENT (remains same structure)
 Widget _buildRelatedServicesContent() {
   return Column(
     crossAxisAlignment: CrossAxisAlignment.start,
     children: [
       _buildSectionTitle('Related Services'),
       const SizedBox(height: 12),
       _buildRelatedServicesList(),
     ],
   );
 }

 // Builds the VERTICAL list of related services (ListTile styling updated)
 Widget _buildRelatedServicesList() {
   if (_isLoadingRelated) { /* Loading indicator */ return const Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Center(child: CircularProgressIndicator())); }
   if (_relatedServices.isEmpty) { /* Empty message */ return const Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Center(child: Text('No related services found.'))); }

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
       return ListTile(
         contentPadding: const EdgeInsets.symmetric(vertical: 6.0), // Adjusted padding
         dense: true,
         leading: ClipRRect( // Use ClipRRect for rounded corners on image
           borderRadius: BorderRadius.circular(8.0),
           child: Container(
             width: 60, height: 60, // Slightly larger image
             color: Colors.grey[200],
             child: (imageUrl != null && imageUrl.isNotEmpty)
                 ? Image.network(imageUrl, fit: BoxFit.cover, /* Add loading/error builders */)
                 : const Icon(Icons.construction, size: 24, color: Colors.grey),
           ),
         ),
         title: Text( name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis,), // Adjusted style
         subtitle: Text( 'RM ${price.toStringAsFixed(2)} ${priceType.isNotEmpty ? "($priceType)" : ""}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green[800]), maxLines: 1, overflow: TextOverflow.ellipsis,),
         trailing: const Icon(Icons.chevron_right, size: 20),
         onTap: () {
           // Navigate using pushReplacement (or push)
            Navigator.pushReplacement( // Consider using push if back navigation is desired
               context,
               MaterialPageRoute( builder: (context) => ServiceDetailPage(serviceId: relatedServiceId),),
            );
         },
       );
     },
   );
 }

 // Builds Reviews Placeholder CONTENT (remains same structure)
 Widget _buildReviewsContent() {
   return Column(
     crossAxisAlignment: CrossAxisAlignment.start,
     children: [
       _buildSectionTitle('Reviews'),
       const SizedBox(height: 8),
       const Center(child: Padding( padding: EdgeInsets.symmetric(vertical: 20.0), child: Text('Reviews coming soon!', style: TextStyle(color: Colors.grey)),)),
     ],
   );
 }

 // Helper for section titles (Styling updated)
 Widget _buildSectionTitle(String title) {
   return Padding(
     padding: const EdgeInsets.only(bottom: 8.0), // Ensure spacing below title
     child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant), // Slightly less prominent title color
     ),
   );
 }

 // Build container for sticky button (remains same)
 Widget _buildBookingButtonContainer() {
   if (_isLoading || _serviceData == null) { return const SizedBox.shrink(); }
   // Add some padding and elevation to the container
   return Container(
     padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 12.0),
     decoration: BoxDecoration(
       color: Theme.of(context).colorScheme.surface, // Use surface color
       boxShadow: [
         BoxShadow( color: Colors.black.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, -2),)
       ],
       // Optional: Add border radius if desired
       // borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
     ),
     child: ElevatedButton.icon(
       icon: const Icon(Icons.calendar_month_outlined),
       label: const Text('Check Availability & Book'),
       style: ElevatedButton.styleFrom(
         padding: const EdgeInsets.symmetric(vertical: 14),
         textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
         // Use theme primary color for button
         backgroundColor: Theme.of(context).colorScheme.primary,
         foregroundColor: Theme.of(context).colorScheme.onPrimary,
       ),
       onPressed: () {
         // Navigation logic remains the same
         final String? currentHandymanId = _serviceData?['handymanId'] as String?;
         if (currentHandymanId != null) {
           Navigator.push( context, MaterialPageRoute( builder: (context) => BookServicePage( serviceId: widget.serviceId, handymanId: currentHandymanId,),),);
         } else {
           ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Cannot proceed: Handyman details are missing.')),);
         }
       }
     )
   );
 }

} // End of _ServiceDetailPageState