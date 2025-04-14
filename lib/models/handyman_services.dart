// lib/models/handyman_service.dart

class HandymanService {
  final String id;
  final String handymanId;
  final String name;
  final String description;
  final double price;
  final String priceType;
  final String? imageUrl;
  final String category;
  final String state;
  final String availability; // e.g., 'Available', 'Unavailable'
  final DateTime createdAt;

  HandymanService({
    required this.id,
    required this.handymanId,
    required this.name,
    required this.description,
    required this.price,
    required this.priceType,
    this.imageUrl,
    required this.category,
    required this.state,
    required this.availability,
    required this.createdAt,
  });

  factory HandymanService.fromMap(Map<String, dynamic> data, String id) {
    return HandymanService(
      id: id,
      handymanId: data['handymanId'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      price: (data['price'] ?? 0).toDouble(),
      priceType: data['priceType'] ?? '',
      imageUrl: data['imageUrl'],
      category: data['category'] ?? '',
      state: data['state'] ?? '',
      availability: data['availability'] ?? 'Unavailable',
      createdAt: DateTime.tryParse(data['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'handymanId': handymanId,
      'name': name,
      'description': description,
      'price': price,
      'priceType': priceType,
      'imageUrl': imageUrl,
      'category': category,
      'state': state,
      'availability': availability,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}