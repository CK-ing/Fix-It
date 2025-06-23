// lib/models/review.dart

import 'package:firebase_database/firebase_database.dart';

class RatingInfo {
  final double averageRating;
  final int ratingCount;

  RatingInfo({this.averageRating = 0.0, this.ratingCount = 0});
}

// Represents the raw data structure of a review in Firebase.
class Review {
  final String reviewId;
  final String bookingId;
  final String serviceId;
  final String handymanId;
  final String homeownerId;
  final int rating;
  final bool recommended;
  final String comment;
  final List<String> reviewPhotoUrls;
  final DateTime createdAt;

  Review({
    required this.reviewId,
    required this.bookingId,
    required this.serviceId,
    required this.handymanId,
    required this.homeownerId,
    required this.rating,
    required this.recommended,
    required this.comment,
    required this.reviewPhotoUrls,
    required this.createdAt,
  });

  factory Review.fromSnapshot(DataSnapshot snapshot) {
    final data = Map<String, dynamic>.from(snapshot.value as Map);
    
    // Handle photo URLs which might be a List<dynamic> from Firebase
    List<String> photos = [];
    if (data['reviewPhotoUrls'] != null) {
      photos = List<String>.from(data['reviewPhotoUrls']);
    }

    return Review(
      reviewId: snapshot.key ?? '',
      bookingId: data['bookingId'] ?? '',
      serviceId: data['serviceId'] ?? '',
      handymanId: data['handymanId'] ?? '',
      homeownerId: data['homeownerId'] ?? '',
      rating: (data['rating'] as num?)?.toInt() ?? 0,
      recommended: data['recommended'] as bool? ?? false,
      comment: data['comment'] ?? '',
      reviewPhotoUrls: photos,
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : DateTime.now(),
    );
  }
}


// A "View Model" that combines a Review with the reviewer's details for display.
class ReviewViewModel {
  final Review review;
  final String reviewerName;
  final String? reviewerImageUrl;

  ReviewViewModel({
    required this.review,
    required this.reviewerName,
    this.reviewerImageUrl,
  });
}
