import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/reviews.dart';

enum ReviewSortOption { mostRelevant, mostRecent, highestRated, lowestRated }

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
  late List<ReviewViewModel> _sortedReviews;
  ReviewSortOption _currentSortOption = ReviewSortOption.mostRelevant;

  @override
  void initState() {
    super.initState();
    // Initially, the list is sorted by relevance (which we'll treat as newest first)
    _sortedReviews = List.from(widget.reviews);
    _sortReviews();
  }

  void _sortReviews() {
    setState(() {
      switch (_currentSortOption) {
        case ReviewSortOption.mostRecent:
        case ReviewSortOption.mostRelevant: // Defaulting relevant to recent
          _sortedReviews.sort((a, b) => b.review.createdAt.compareTo(a.review.createdAt));
          break;
        case ReviewSortOption.highestRated:
          _sortedReviews.sort((a, b) => b.review.rating.compareTo(a.review.rating));
          break;
        case ReviewSortOption.lowestRated:
          _sortedReviews.sort((a, b) => a.review.rating.compareTo(b.review.rating));
          break;
      }
    });
  }

  String _getSortOptionText(ReviewSortOption option) {
    switch (option) {
      case ReviewSortOption.mostRecent: return 'Most Recent';
      case ReviewSortOption.highestRated: return 'Highest Rated';
      case ReviewSortOption.lowestRated: return 'Lowest Rated';
      case ReviewSortOption.mostRelevant:
      default: return 'Most Relevant';
    }
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: ReviewSortOption.values.map((option) {
              return ListTile(
                title: Text(_getSortOptionText(option)),
                onTap: () {
                  setState(() {
                    _currentSortOption = option;
                    _sortReviews();
                  });
                  Navigator.pop(context);
                },
                trailing: _currentSortOption == option ? const Icon(Icons.check, color: Colors.blue) : null,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays < 1) return 'Today';
    if (difference.inDays < 7) return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    if (difference.inDays < 30) return '${(difference.inDays / 7).floor()} week${(difference.inDays / 7).floor() > 1 ? 's' : ''} ago';
    if (difference.inDays < 365) return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() > 1 ? 's' : ''} ago';
    return DateFormat('dd/MM/yyyy').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final int recommendationCount = widget.reviews.where((r) => r.review.recommended).length;
    final double recommendationPercentage = widget.reviews.isNotEmpty ? (recommendationCount / widget.reviews.length) * 100 : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.reviews.length} Reviews'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildNewRatingHeader(recommendationPercentage),
          ),
          SliverToBoxAdapter(
            child: _buildFilterSection(),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final reviewViewModel = _sortedReviews[index];
                return _buildReviewListItem(reviewViewModel);
              },
              childCount: _sortedReviews.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewListItem(ReviewViewModel reviewViewModel) {
    final review = reviewViewModel.review;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.grey[200],
                backgroundImage: reviewViewModel.reviewerImageUrl != null
                    ? NetworkImage(reviewViewModel.reviewerImageUrl!)
                    : null,
                child: reviewViewModel.reviewerImageUrl == null
                    ? const Icon(Icons.person, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reviewViewModel.reviewerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    _formatRelativeTime(review.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ...List.generate(review.rating, (i) => Icon(Icons.star, color: Colors.amber[700], size: 18)),
              ...List.generate(5 - review.rating, (i) => Icon(Icons.star, color: Colors.grey[300], size: 18)),
              const SizedBox(width: 12),
              Icon(
                review.recommended ? Icons.thumb_up_alt_rounded : Icons.thumb_down_alt_rounded,
                color: review.recommended ? Colors.green : Colors.red,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                review.recommended ? 'Recommended' : 'Not Recommended',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (review.comment.isNotEmpty)
            Text(
              review.comment,
              style: const TextStyle(height: 1.5),
            ),
          if (review.reviewPhotoUrls.isNotEmpty)
            _buildReviewPhotos(review.reviewPhotoUrls),
        ],
      ),
    );
  }

  Widget _buildNewRatingHeader(double recommendationPercentage) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 0,
        color: Colors.grey.shade100,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left side: Average Rating and Stars
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    widget.averageRating.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '/5',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    children: List.generate(5, (index) {
                      return Icon(
                        Icons.star_rounded,
                        color: index < widget.averageRating.round() ? Colors.amber[700] : Colors.grey[300],
                        size: 20,
                      );
                    }),
                  ),
                ],
              ),
              // Right side: Recommendation Percentage
              Text(
                '${recommendationPercentage.toStringAsFixed(0)}% Recommended',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: _showSortOptions,
            icon: const Icon(Icons.swap_vert, size: 18),
            label: Text(_getSortOptionText(_currentSortOption)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey.shade400),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewPhotos(List<String> photoUrls) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: SizedBox(
        height: 100,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: photoUrls.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => _viewPhotoFullScreen(photoUrls[index]),
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    photoUrls[index],
                    height: 100,
                    width: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (c, o, s) => Container(
                      width: 100, height: 100, color: Colors.grey[200],
                      child: const Icon(Icons.error, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _viewPhotoFullScreen(String imageUrl) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: InteractiveViewer(
            panEnabled: false,
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 4,
            child: Image.network(imageUrl),
          ),
        ),
      ),
    ));
  }
}
