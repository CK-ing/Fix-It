import 'package:firebase_database/firebase_database.dart';

class CustomRequest {
  final String requestId;
  final String homeownerId;
  final String handymanId;
  final String description;
  final String budgetRange;
  final List<String> photoUrls;
  final String status;
  final DateTime createdAt;
  final double? quotePrice;
  final String? quotePriceType;

  CustomRequest({
    required this.requestId,
    required this.homeownerId,
    required this.handymanId,
    required this.description,
    required this.budgetRange,
    required this.photoUrls,
    required this.status,
    required this.createdAt,
    this.quotePrice,
    this.quotePriceType,
  });

  factory CustomRequest.fromSnapshot(DataSnapshot snapshot) {
    final data = Map<String, dynamic>.from(snapshot.value as Map);
    return CustomRequest(
      requestId: snapshot.key ?? '',
      homeownerId: data['homeownerId'] ?? '',
      handymanId: data['handymanId'] ?? '',
      description: data['description'] ?? 'No description provided.',
      budgetRange: data['budgetRange'] ?? 'N/A',
      photoUrls: data['photoUrls'] != null ? List<String>.from(data['photoUrls']) : [],
      status: data['status'] ?? 'Unknown',
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : DateTime.now(),
      quotePrice: (data['quotePrice'] as num?)?.toDouble(),
      quotePriceType: data['quotePriceType'] as String?,
    );
  }
}

// A simple view model to combine the request with homeowner details
class CustomRequestViewModel {
  final CustomRequest request;
  final String homeownerName;
  final String? homeownerImageUrl;

  CustomRequestViewModel({
    required this.request,
    required this.homeownerName,
    this.homeownerImageUrl,
  });
}
