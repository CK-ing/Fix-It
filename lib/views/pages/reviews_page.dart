import 'package:flutter/material.dart';

import '../../models/reviews.dart';

class ReviewsPage extends StatefulWidget {
  final String serviceId;
  final String serviceName;
  final double averageRating;
  final List<ReviewViewModel> reviews;

  const ReviewsPage({
    required this.serviceId,
    required this.serviceName,
    required this.averageRating,
    required this.reviews,
    super.key,
  });

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reviews for ${widget.serviceName}'),
      ),
      body: Center(
        child: Text('Showing ${widget.reviews.length} reviews.'),
      ),
    );
  }
}
