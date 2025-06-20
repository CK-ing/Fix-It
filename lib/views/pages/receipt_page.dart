import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/bookings_services.dart';

class ReceiptPage extends StatefulWidget {
  final String bookingId;

  const ReceiptPage({
    required this.bookingId,
    super.key,
  });

  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

// *** MODIFIED: Added SingleTickerProviderStateMixin for animation ***
class _ReceiptPageState extends State<ReceiptPage> with SingleTickerProviderStateMixin {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  
  // State
  bool _isLoading = true;
  String? _error;
  bool _isGeneratingPdf = false;
  
  // Data holders
  Booking? _booking;
  Map<String, dynamic>? _serviceDetails;
  Map<String, dynamic>? _homeownerDetails;
  Map<String, dynamic>? _handymanDetails;
  String? _paymentMethod;

  // *** NEW: Animation state variables ***
  late AnimationController _animationController;
  double _rotationY = 0.0;

  @override
  void initState() {
    super.initState();
    _loadReceiptData();
    // *** NEW: Initialize animation controller ***
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // Duration for the spring-back
    );
  }

  // *** NEW: Dispose animation controller ***
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadReceiptData() async {
    try {
      final bookingSnapshot = await _dbRef.child('bookings').child(widget.bookingId).get();
      if (!mounted || !bookingSnapshot.exists) throw Exception("Booking not found.");

      final bookingDataMap = Map<String, dynamic>.from(bookingSnapshot.value as Map);
      final bookingData = Booking.fromSnapshot(bookingSnapshot);
      final paymentId = bookingDataMap['paymentId'] as String?;

      final results = await Future.wait([
        _dbRef.child('services').child(bookingData.serviceId).get(),
        _dbRef.child('users').child(bookingData.homeownerId).get(),
        _dbRef.child('users').child(bookingData.handymanId).get(),
        if (paymentId != null) _dbRef.child('payments').child(paymentId).get(),
      ]);

      if (!mounted) return;

      final serviceSnap = results[0];
      final homeownerSnap = results[1];
      final handymanSnap = results[2];
      
      String? finalPaymentMethod;
      if (paymentId != null && results.length > 3) {
        final paymentSnap = results[3];
        if (paymentSnap.exists) {
          final paymentDataMap = Map<String, dynamic>.from(paymentSnap.value as Map);
          finalPaymentMethod = paymentDataMap['paymentMethod'] as String?;
        }
      }

      setState(() {
        _booking = bookingData;
        _paymentMethod = finalPaymentMethod;
        _serviceDetails = serviceSnap.exists ? Map<String, dynamic>.from(serviceSnap.value as Map) : null;
        _homeownerDetails = homeownerSnap.exists ? Map<String, dynamic>.from(homeownerSnap.value as Map) : null;
        _handymanDetails = handymanSnap.exists ? Map<String, dynamic>.from(handymanSnap.value as Map) : null;
        _isLoading = false;
      });

    } catch(e) {
      print("Error loading receipt data: $e");
      if(mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load receipt data: ${e.toString()}";
        });
      }
    }
  }

  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final pdf = pw.Document(version: PdfVersion.pdf_1_5, compress: true);
    final font = await PdfGoogleFonts.poppinsRegular();
    final boldFont = await PdfGoogleFonts.poppinsBold();
    
    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) {
          return _buildPdfReceipt(font, boldFont);
        },
      ),
    );

    return pdf.save();
  }
  
  Future<void> _handlePdfGeneration() async {
    if (_isGeneratingPdf) return;

    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) => _generatePdf(format),
        name: 'FixIt_Receipt_${widget.bookingId}.pdf',
      );
    } catch (e) {
      print("Error generating PDF: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to generate PDF."), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        actions: [
          _isGeneratingPdf
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Download PDF',
                onPressed: (_isLoading || _error != null) ? null : _handlePdfGeneration,
              )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildReceiptContent(),
                ),
    );
  }

  // *** MODIFIED: This widget now handles the spinning animation ***
  Widget _buildReceiptContent() {
    return GestureDetector(
      onPanUpdate: (details) {
        // Update rotation based on horizontal drag
        setState(() {
          _rotationY += details.delta.dx / 100; // Adjust sensitivity
        });
      },
      onPanEnd: (details) {
        // Animate the card back to its original position
        final Animation<double> springAnimation = Tween<double>(
          begin: _rotationY,
          end: 0.0, // Settle back to 0 rotation
        ).animate(CurvedAnimation(parent: _animationController, curve: Curves.elasticOut));

        _animationController.reset();
        springAnimation.addListener(() {
          setState(() {
            _rotationY = springAnimation.value;
          });
        });
        _animationController.forward();
      },
      child: Transform(
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001) // Add perspective for 3D effect
          ..rotateY(_rotationY),
        alignment: FractionalOffset.center,
        child: Card(
          elevation: 8, // Increased elevation for better 3D effect
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const Divider(thickness: 1, height: 32),
                _buildPartyDetails(),
                const Divider(thickness: 1, height: 32),
                _buildBookingSummary(),
                const SizedBox(height: 24),
                _buildCostBreakdown(),
                const Divider(thickness: 1, height: 32),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI Widget Builders (No changes below this point) ---
  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FixIt', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
              Text('Your Trusted Handyman Service', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('TAX INVOICE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('ID: #${widget.bookingId}', style: const TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPartyDetails() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildDetailBlock('Billed To (Homeowner)', [
          _homeownerDetails?['name'] ?? 'N/A',
          _homeownerDetails?['address'] ?? 'N/A',
          _homeownerDetails?['phoneNumber'] ?? 'N/A',
        ])),
        const SizedBox(width: 16),
        Expanded(child: _buildDetailBlock('From (Handyman)', [
          _handymanDetails?['name'] ?? 'N/A',
          _handymanDetails?['address'] ?? 'N/A',
           _handymanDetails?['phoneNumber'] ?? 'N/A',
        ])),
      ],
    );
  }

  Widget _buildBookingSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDetailRow('Booking Date:', DateFormat.yMMMd().add_jm().format(_booking!.bookingDateTime)),
        _buildDetailRow('Service Date:', DateFormat.yMMMd().add_jm().format(_booking!.scheduledDateTime)),
        _buildDetailRow('Payment Method:', _paymentMethod?.capitalize() ?? 'N/A'),
      ],
    );
  }

  Widget _buildCostBreakdown() {
    final double price = (_booking!.price ?? 0.0);
    final int quantity = _booking!.quantity > 0 ? _booking!.quantity : 1;
    final String priceDetails = _booking!.priceType == 'Hourly'
        ? 'RM ${price.toStringAsFixed(2)} x $quantity Hours'
        : 'Fixed Price';

    return Column(
      children: [
        Table(
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(2),
          },
          children: [
            _buildTableRow('Description', 'Amount', isHeader: true),
            _buildTableRow(_booking!.serviceName, ''),
            _buildTableRow(priceDetails, 'RM ${(_booking!.subtotal/100.0).toStringAsFixed(2)}'),
            _buildTableRow('SST (8%)', 'RM ${(_booking!.tax/100.0).toStringAsFixed(2)}'),
          ],
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(width: 24),
              Text('RM ${(_booking!.total/100.0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('Thank you for choosing FixIt!', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'FixIt Services | 123 Tech Avenue, Cyberjaya, 63000 Selangor | +603-1234 5678 | support@fixit.com.my',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildDetailBlock(String title, List<String> details) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ...details.map((text) => Text(text, style: TextStyle(color: Colors.grey[700]))),
      ],
    );
  }

  Widget _buildDetailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: Colors.grey[700])),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500), textAlign: TextAlign.end,)),
        ],
      ),
    );
  }
  
  TableRow _buildTableRow(String left, String right, {bool isHeader = false}) {
    final style = isHeader ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return TableRow(
      children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(left, style: style)),
        Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(right, style: style, textAlign: TextAlign.right)),
      ],
    );
  }

  // --- PDF Widget Builders ---
  pw.Widget _buildPdfReceipt(pw.Font font, pw.Font boldFont) {
    final baseStyle = pw.TextStyle(font: font, fontSize: 10);
    final boldStyle = pw.TextStyle(font: boldFont, fontSize: 10);
    final primaryColor = PdfColor.fromHex("#1976D2");
    
    final double price = (_booking!.price ?? 0.0);
    final int quantity = _booking!.quantity > 0 ? _booking!.quantity : 1;
    final String priceDetails = _booking!.priceType == 'Hourly'
        ? 'RM ${price.toStringAsFixed(2)} x $quantity Hours'
        : 'Fixed Price';

    return pw.Padding(
      padding: const pw.EdgeInsets.all(30),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('FixIt', style: pw.TextStyle(font: boldFont, fontSize: 24, color: primaryColor)),
                  pw.Text('Your Trusted Handyman Service', style: baseStyle.copyWith(color: PdfColors.grey600)),
                ],
              )),
              pw.SizedBox(width: 16),
              pw.Expanded(child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('TAX INVOICE', style: pw.TextStyle(font: boldFont, fontSize: 16)),
                  pw.SizedBox(height: 4),
                  pw.Text('ID: #${widget.bookingId}', style: baseStyle.copyWith(color: PdfColors.grey600)),
                ],
              )),
            ],
          ),
          pw.Divider(height: 32),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Billed To (Homeowner)', style: boldStyle),
                pw.SizedBox(height: 4),
                pw.Text(_homeownerDetails?['name'] ?? 'N/A', style: baseStyle),
                pw.Text(_homeownerDetails?['address'] ?? 'N/A', style: baseStyle),
                pw.Text(_homeownerDetails?['phoneNumber'] ?? 'N/A', style: baseStyle),
              ])),
              pw.SizedBox(width: 16),
              pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('From (Handyman)', style: boldStyle),
                pw.SizedBox(height: 4),
                pw.Text(_handymanDetails?['name'] ?? 'N/A', style: baseStyle),
                pw.Text(_handymanDetails?['address'] ?? 'N/A', style: baseStyle),
                pw.Text(_handymanDetails?['phoneNumber'] ?? 'N/A', style: baseStyle),
              ])),
            ]
          ),
          pw.Divider(height: 32),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Booking Date:', style: baseStyle), pw.Text(DateFormat.yMMMd().add_jm().format(_booking!.bookingDateTime), style: boldStyle)]),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Service Date:', style: baseStyle), pw.Text(DateFormat.yMMMd().add_jm().format(_booking!.scheduledDateTime), style: boldStyle)]),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Payment Method:', style: baseStyle), pw.Text(_paymentMethod?.capitalize() ?? 'N/A', style: boldStyle)]),
          pw.SizedBox(height: 24),
          pw.Table.fromTextArray(
            headerStyle: boldStyle,
            cellStyle: baseStyle,
            columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2)},
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {1: pw.Alignment.centerRight},
            headers: ['Description', 'Amount'],
            data: [
              [_booking!.serviceName, ''],
              [priceDetails, 'RM ${(_booking!.subtotal / 100.0).toStringAsFixed(2)}'],
              ['SST (8%)', 'RM ${(_booking!.tax / 100.0).toStringAsFixed(2)}'],
            ],
          ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Total Amount', style: pw.TextStyle(font: boldFont, fontSize: 14)),
              pw.SizedBox(width: 24),
              pw.Text('RM ${(_booking!.total / 100.0).toStringAsFixed(2)}', style: pw.TextStyle(font: boldFont, fontSize: 14)),
            ],
          ),
          pw.Spacer(),
          pw.Divider(height: 32),
          pw.Center(child: pw.Text('Thank you for choosing FixIt!', style: boldStyle)),
          pw.SizedBox(height: 8),
          pw.Center(child: pw.Text(
            'FixIt Services | 123 Tech Avenue, Cyberjaya, 63000 Selangor | +603-1234 5678 | support@fixit.com.my',
            style: baseStyle.copyWith(fontSize: 8, color: PdfColors.grey600),
            textAlign: pw.TextAlign.center
          )),
        ]
      )
    );
  }
}

// Helper to capitalize the first letter of a string
extension StringExtension on String {
    String capitalize() {
      if (isEmpty) return "";
      return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
    }
}
