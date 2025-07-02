import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart'; // For generating unique filenames for photos

class RateServicesPage extends StatefulWidget {
  final String bookingId;
  final String? serviceId; // Make serviceId optional
  final String handymanId;
  final String serviceName; // Add serviceName

  const RateServicesPage({
    required this.bookingId,
    this.serviceId,
    required this.handymanId,
    required this.serviceName, // Make it required
    super.key,
  });

  @override
  State<RateServicesPage> createState() => _RateServicesPageState();
}

class _RateServicesPageState extends State<RateServicesPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final TextEditingController _commentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final Uuid _uuid = const Uuid();

  // State Variables
  Map<String, dynamic>? _serviceData;
  bool _isLoadingService = true;
  bool _isSubmitting = false;
  String? _error;

  // Review Form State
  int _rating = 0;
  bool? _isRecommended; // null = unselected, true = thumbs up, false = thumbs down
  final List<File> _imageFiles = [];

  @override
  void initState() {
    super.initState();
    _loadServiceDetails();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
  
  void setStateIfMounted(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  // NEW CODE
  Future<void> _loadServiceDetails() async {
    // If there is no serviceId (i.e., it's a custom job), we don't need to fetch anything.
    if (widget.serviceId == null || widget.serviceId!.isEmpty) {
      setState(() {
        _isLoadingService = false;
        _serviceData = null; // Ensure serviceData is null
      });
      return;
    }

    try {
      final snapshot = await _dbRef.child('services').child(widget.serviceId!).get();
      if (mounted) {
        if (snapshot.exists) {
          setState(() {
            _serviceData = Map<String, dynamic>.from(snapshot.value as Map);
            _isLoadingService = false;
          });
        } else {
          // If service is not found (e.g., deleted), just proceed without image data
          setState(() {
            _isLoadingService = false;
            _serviceData = null;
          });
        }
      }
    } catch (e) {
      print("Error loading service details for review: $e");
      if(mounted) {
        setState(() {
          _isLoadingService = false;
          _error = "Could not load service details.";
        });
      }
    }
  }

  Future<void> _pickImages() async {
    try {
      if (_imageFiles.length >= 5) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You can upload a maximum of 5 photos.')));
        return;
      }
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        imageQuality: 70,
        maxWidth: 1024,
      );

      if (pickedFiles.isNotEmpty) {
        setState(() {
          _imageFiles.addAll(pickedFiles.map((file) => File(file.path)).take(5 - _imageFiles.length));
        });
      }
    } catch (e) {
      print("Error picking images: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error picking images.')));
      }
    }
  }
  
  void _removeImage(int index) {
    setState(() {
      _imageFiles.removeAt(index);
    });
  }

  Future<List<String>> _uploadReviewPhotos(String reviewId) async {
    if (_imageFiles.isEmpty) return [];
    
    List<Future<String>> uploadFutures = [];
    for (var imageFile in _imageFiles) {
      final String fileName = _uuid.v4();
      final Reference storageRef = _storage.ref().child('reviews_photo').child(reviewId).child('$fileName.jpg');
      
      final uploadTask = storageRef.putFile(imageFile);
      
      final future = uploadTask.then((snapshot) async {
        return await snapshot.ref.getDownloadURL();
      });
      uploadFutures.add(future);
    }
    
    return await Future.wait(uploadFutures);
  }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a star rating.'), backgroundColor: Colors.orange));
      return;
    }
    if (_isRecommended == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select if you would recommend this service.'), backgroundColor: Colors.orange));
      return;
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must be logged in to submit a review.'), backgroundColor: Colors.red));
      return;
    }

    setStateIfMounted(() { _isSubmitting = true; });

    try {
      final newReviewRef = _dbRef.child('reviews').push();
      final reviewId = newReviewRef.key;
      if (reviewId == null) throw Exception("Could not generate review ID.");
      
      final List<String> reviewPhotoUrls = await _uploadReviewPhotos(reviewId);

      final Map<String, dynamic> reviewData = {
        'reviewId': reviewId,
        'bookingId': widget.bookingId,
        'serviceId': widget.serviceId,
        'handymanId': widget.handymanId,
        'homeownerId': currentUser.uid,
        'rating': _rating,
        'recommended': _isRecommended,
        'comment': _commentController.text.trim(),
        'reviewPhotoUrls': reviewPhotoUrls,
        'createdAt': ServerValue.timestamp,
      };

      await newReviewRef.set(reviewData);

      // Create Notification for Handyman
      final homeownerSnapshot = await _dbRef.child('users/${currentUser.uid}/name').get();
      final homeownerName = homeownerSnapshot.value as String? ?? 'A customer';
      final serviceName = widget.serviceName;
      await _dbRef.child('notifications/${widget.handymanId}').push().set({
        'title': 'You have a new review!',
        'body': '$homeownerName left a $_rating-star review for "$serviceName".',
        'bookingId': widget.bookingId,
        'type': 'new_review',
        'isRead': false,
        'createdAt': ServerValue.timestamp,
      });

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you for your review!'), backgroundColor: Colors.green));
        Navigator.of(context).pop(true);
      }

    } catch(e) {
      print("Error submitting review: $e");
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit review: ${e.toString()}'), backgroundColor: Colors.red));
      }
    } finally {
      if(mounted) {
        setStateIfMounted(() { _isSubmitting = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate This Service'),
        elevation: 1,
      ),
      body: _isLoadingService
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildReviewForm(),
      bottomNavigationBar: _buildSubmitButton(),
    );
  }

  Widget _buildReviewForm() {
    final serviceImageUrl = _serviceData?['imageUrl'] as String?;
    final serviceName = widget.serviceName;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildServiceHeader(serviceImageUrl, serviceName),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Overall Rating *'),
                _buildStarRating(),
                const SizedBox(height: 24),
                _buildSectionTitle('Recommend this Service? *'),
                _buildRecommendationSelector(),
                const SizedBox(height: 24),
                _buildSectionTitle('Add Photos (Optional)'),
                _buildPhotoUploader(),
                const SizedBox(height: 24),
                _buildSectionTitle('Comments (Optional)'),
                _buildCommentField(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceHeader(String? imageUrl, String name) {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        image: imageUrl != null && imageUrl.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.3),
                  BlendMode.darken,
                ),
              )
            : null,
      ),
      child: Container(
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(16.0),
        child: Text(
          name,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                shadows: [
                  const Shadow(blurRadius: 4, color: Colors.black54)
                ]
              ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return IconButton(
          icon: Icon(
            _rating > index ? Icons.star_rounded : Icons.star_border_rounded,
            color: _rating > index ? Colors.amber[600] : Colors.grey,
            size: 44,
          ),
          onPressed: _isSubmitting ? null : () {
            setState(() {
              _rating = index + 1;
            });
          },
        );
      }),
    );
  }
  
  Widget _buildRecommendationSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildRecommendationButton(
            context: context,
            icon: Icons.thumb_up_alt_outlined,
            label: 'Yes',
            isSelected: _isRecommended == true,
            onTap: () => setState(() => _isRecommended = true),
            selectedColor: Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildRecommendationButton(
            context: context,
            icon: Icons.thumb_down_alt_outlined,
            label: 'No',
            isSelected: _isRecommended == false,
            onTap: () => setState(() => _isRecommended = false),
            selectedColor: Colors.red,
          ),
        ),
      ],
    );
  }
  
  Widget _buildRecommendationButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    final Color color = isSelected ? selectedColor : Colors.grey;
    final Color backgroundColor = isSelected ? selectedColor.withOpacity(0.1) : Colors.grey.withOpacity(0.1);

    return InkWell(
      onTap: _isSubmitting ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }


  Widget _buildPhotoUploader() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        children: [
          ..._imageFiles.asMap().entries.map((entry) {
            int index = entry.key;
            File file = entry.value;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8.0),
                    image: DecorationImage(image: FileImage(file), fit: BoxFit.cover),
                  ),
                ),
                Positioned(
                  top: -8, right: -8,
                  child: GestureDetector(
                    onTap: _isSubmitting ? null : () => _removeImage(index),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
          if (_imageFiles.length < 5)
            GestureDetector(
              onTap: _isSubmitting ? null : _pickImages,
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                ),
                child: Icon(Icons.add_a_photo_outlined, color: Colors.grey.shade600, size: 32),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommentField() {
    return TextFormField(
      controller: _commentController,
      maxLines: 5,
      enabled: !_isSubmitting,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'Share more about your experience.',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).primaryColor)
        ),
        alignLabelWithHint: true,
        fillColor: Colors.grey.withOpacity(0.05),
        filled: true,
      ),
    );
  }
  
  Widget _buildSubmitButton() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, -2))]
      ),
      child: SafeArea(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _isSubmitting ? null : _submitReview,
          child: _isSubmitting
              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Text('Submit Review'),
        ),
      ),
    );
  }
}
