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
  final String? district; // *** NEW: Added district field (nullable) ***
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
    this.district, // *** NEW: Added to constructor (optional) ***
    required this.availability,
    required this.createdAt,
  });

  factory HandymanService.fromMap(Map<String, dynamic> data, String id) {
    return HandymanService(
      id: id,
      handymanId: data['handymanId'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      price: (data['price'] ?? 0.0).toDouble(), // Ensure price is double, default to 0.0
      priceType: data['priceType'] ?? '',
      imageUrl: data['imageUrl'] as String?, // Explicit cast
      category: data['category'] ?? '',
      state: data['state'] ?? '',
      district: data['district'] as String?, // *** NEW: Read district from map (nullable) ***
      availability: data['availability'] ?? 'Unavailable',
      // Ensure createdAt parsing is robust
      createdAt: data['createdAt'] != null && data['createdAt'].toString().isNotEmpty
          ? DateTime.tryParse(data['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
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
      'district': district, // *** NEW: Add district to map (will be null if not set) ***
      'availability': availability,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}