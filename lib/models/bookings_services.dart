import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart'; // For date parsing and formatting

class Booking {
  final String bookingId;
  final String serviceId;
  final String serviceName;
  final String handymanId;
  final String homeownerId;
  final DateTime scheduledDateTime;
  final String address;
  final String? description;
  final int quantity;
  final double? price;
  final String? priceType;
  final int subtotal; // sen
  final int tax;      // sen
  final int total;    // sen
  final String? couponCode;
  final String status;
  final DateTime bookingDateTime;
  // *** ADDED Fields ***
  final String? cancellationReason; // For homeowner cancellation
  final String? declineReason;      // For handyman decline
  final String? customRequestId;

  Booking({
    required this.bookingId,
    required this.serviceId,
    required this.serviceName,
    required this.handymanId,
    required this.homeownerId,
    required this.scheduledDateTime,
    required this.address,
    this.description,
    required this.quantity,
    this.price,
    this.priceType,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.couponCode,
    required this.status,
    required this.bookingDateTime,
    // *** ADDED Fields ***
    this.cancellationReason,
    this.declineReason,
    this.customRequestId,
  });

  // Factory constructor remains largely the same, just adds parsing for new fields
  factory Booking.fromSnapshot(DataSnapshot snapshot) {
    final data = Map<String, dynamic>.from(snapshot.value as Map);
    final bookingId = snapshot.key ?? '';

    DateTime _parseDateTime(dynamic value) {
      if (value is int) { return DateTime.fromMillisecondsSinceEpoch(value); }
      else if (value is String) { return DateTime.tryParse(value) ?? DateTime.now(); }
      return DateTime.now();
    }

    return Booking(
      bookingId: bookingId,
      serviceId: data['serviceId'] ?? '',
      serviceName: data['serviceName'] ?? 'N/A',
      handymanId: data['handymanId'] ?? '',
      homeownerId: data['homeownerId'] ?? '',
      scheduledDateTime: _parseDateTime(data['scheduledDateTime']),
      address: data['address'] ?? '',
      description: data['description'],
      quantity: (data['quantity'] as num?)?.toInt() ?? 1,
      price: (data['price'] as num?)?.toDouble(),
      priceType: data['priceType'],
      subtotal: (data['subtotal'] as num?)?.toInt() ?? 0,
      tax: (data['tax'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? 0,
      couponCode: data['couponCode'],
      status: data['status'] ?? 'Unknown',
      bookingDateTime: _parseDateTime(data['bookingDateTime']),
      // *** Parse new fields (will be null if not present) ***
      cancellationReason: data['cancellationReason'],
      declineReason: data['declineReason'],
      customRequestId: data['customRequestId'],
    );
  }

  String get formattedScheduledDateTime {
     return DateFormat('EEE, MMM d, yyyy - hh:mm a').format(scheduledDateTime);
  }

  String get formattedTotal {
      return (total / 100.0).toStringAsFixed(2);
  }

  toMap() {}
}