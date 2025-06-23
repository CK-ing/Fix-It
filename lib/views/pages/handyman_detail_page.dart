import 'package:flutter/material.dart';

class HandymanDetailPage extends StatefulWidget {
  final String handymanId;

  const HandymanDetailPage({
    required this.handymanId,
    super.key,
  });

  @override
  State<HandymanDetailPage> createState() => _HandymanDetailPageState();
}

class _HandymanDetailPageState extends State<HandymanDetailPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Handyman Profile'),
      ),
      body: Center(
        child: Text('Details for Handyman ID: ${widget.handymanId}'),
      ),
    );
  }
}