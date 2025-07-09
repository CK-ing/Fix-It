import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class CustomRequestPage extends StatefulWidget {
  final String handymanId;
  final String handymanName;
  final String? handymanImageUrl;

  const CustomRequestPage({
    required this.handymanId,
    required this.handymanName,
    this.handymanImageUrl,
    super.key,
  });

  @override
  State<CustomRequestPage> createState() => _CustomRequestPageState();
}

class _CustomRequestPageState extends State<CustomRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final _dbRef = FirebaseDatabase.instance.ref(); 
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _uuid = const Uuid();

  // State
  final List<File> _imageFiles = [];
  String? _selectedBudgetRange;
  bool _isSubmitting = false;
  bool _isAnalyzing = false;

  final List<String> _budgetRanges = [
    'Below RM100',
    'RM100 - RM300',
    'RM300 - RM500',
    'RM500 - RM1000',
    'Above RM1000',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_imageFiles.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can upload a maximum of 5 photos.')),
      );
      return;
    }
    try {
      final List<XFile> pickedFiles = await _imagePicker.pickMultiImage(
        imageQuality: 70,
        maxWidth: 1024,
      );
      if (pickedFiles.isNotEmpty) {
        setState(() {
          _imageFiles.addAll(pickedFiles.map((f) => File(f.path)).take(5 - _imageFiles.length));
        });
      }
    } catch (e) {
      print("Error picking images: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error picking images.')),
      );
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageFiles.removeAt(index);
    });
  }

  Future<void> _analyzeImageWithAI() async {
    if (_imageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload a photo first.')));
      return;
    }
    setState(() => _isAnalyzing = true);

    try {
      // 1. Convert the image to a Base64 string
      final imageBytes = await _imageFiles.first.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      // 2. Construct the prompt for the Gemini API
      final apiKey = dotenv.env['GEMINI_API_KEY'] ?? "API_KEY_NOT_FOUND";
      final apiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey';
      
      final systemPrompt = """
        You are an expert home repair assistant.
        Your task is to analyze the attached image of a home maintenance or repair issue.
        Based on the image, suggest a short, 3–5 words JOB TITLE and a brief, one-sentence DESCRIPTION of the problem.
        Respond ONLY with a valid JSON object containing two keys: "title" and "description".
        For example: {"title": "Leaky Pipe Under Sink", "description": "There appears to be a water leak from the U-bend pipe under the kitchen sink."}
      """;

      // 3. Make the API call
      final uri = Uri.parse(apiUrl);
      final response = await _postWithRetries(uri, {
        'contents': [{
          'parts': [
            {'text': systemPrompt},
            {'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image}}
          ]
        }]
      });

      if (response == null) {
        throw Exception('No response from Gemini API.');
      }

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        final aiResponseText = responseBody['candidates'][0]['content']['parts'][0]['text'];
        
        // 4. Clean Up Ai Response then Parse the JSON response and update the UI
        String cleanResponse = aiResponseText.trim();

        // Sometimes Gemini wraps the response in ```json ... ```
        if (cleanResponse.startsWith('```')) {
          cleanResponse = cleanResponse.replaceAll(RegExp(r'```[a-zA-Z]*'), '').trim();
        }

        // Then parse
        final aiJson = jsonDecode(cleanResponse);
        final suggestedTitle = aiJson['title'] as String?;
        final suggestedDescription = aiJson['description'] as String?;

        if (mounted) {
          setState(() {
            if (suggestedTitle != null) _titleController.text = suggestedTitle;
            if (suggestedDescription != null) _descriptionController.text = suggestedDescription;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI analysis complete!'), backgroundColor: Colors.green));
        }
      } else {
        throw Exception('Failed to get response from Gemini API: ${response.body}');
      }
    } catch (e) {
      print("Error analyzing image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI analysis failed. Please enter details manually.'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _submitRequest() async {
    if (_isSubmitting) return; // Guard against double submits
    if (_imageFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload at least one photo of the issue.'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to submit a request.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final newRequestRef = FirebaseDatabase.instance.ref('custom_requests').push();
      final requestId = newRequestRef.key;
      if (requestId == null) throw Exception("Could not generate request ID.");

      // Upload photos
      List<String> photoUrls = [];
      if (_imageFiles.isNotEmpty) {
        for (var file in _imageFiles) {
          final fileName = _uuid.v4();
          final storageRef = FirebaseStorage.instance.ref().child('custom_request_photos/$requestId/$fileName.jpg');
          await storageRef.putFile(file);
          final url = await storageRef.getDownloadURL();
          photoUrls.add(url);
        }
      }

      // Prepare data to save
      final Map<String, dynamic> requestData = {
        'requestId': requestId,
        'homeownerId': currentUser.uid,
        'handymanId': widget.handymanId,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'budgetRange': _selectedBudgetRange,
        'photoUrls': photoUrls,
        'status': 'Pending', // Initial status
        'createdAt': ServerValue.timestamp,
      };

      // Save to database
      await newRequestRef.set(requestData);

      final homeownerSnapshot = await _dbRef.child('users/${currentUser.uid}/name').get();
      final homeownerName = homeownerSnapshot.value as String? ?? 'A customer';
      
      await _createNotification(
        userId: widget.handymanId,
        title: 'New Custom Job Request!',
        body: '$homeownerName has sent you a custom service request.',
        bookingId: requestId,
        type: 'custom_request',
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Request Sent"),
          content: Text("Your custom request has been sent to ${widget.handymanName}. You will be notified when they respond."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back from this page
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );

    } catch (e) {
      print("Error submitting custom request: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit request: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Custom Service'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildHandymanHeader(),
            const SizedBox(height: 24),
            _buildSectionTitle('Add Photos *'),
            _buildPhotoUploader(),
            const SizedBox(height: 12),
            _buildAnalyzeButton(), // <-- NEW BUTTON
            const SizedBox(height: 24),
            _buildSectionTitle('What do you need help with? *'),
            _buildTitleField(),
            const SizedBox(height: 16),
            _buildSectionTitle('Describe Your Job *'),
            _buildDescriptionField(),
            const SizedBox(height: 24),
            _buildSectionTitle('Your Budget *'),
            _buildBudgetDropdown(),
            
          ],
        ),
      ),
      bottomNavigationBar: _buildSubmitButton(),
    );
  }

  Future<void> _createNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
    String? bookingId,
  }) async {
    final notificationsRef = _dbRef.child('notifications/$userId').push();
    await notificationsRef.set({
      'notificationId': notificationsRef.key,
      'title': title,
      'body': body,
      'type': type,
      'bookingId': bookingId,
      'isRead': false,
      'createdAt': ServerValue.timestamp,
    });
  }

  Widget _buildHandymanHeader() {
    return Card(
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey[200],
              backgroundImage: widget.handymanImageUrl != null
                  ? NetworkImage(widget.handymanImageUrl!)
                  : null,
              child: widget.handymanImageUrl == null
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Requesting from", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(
                    widget.handymanName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyzeButton() {
  return Center(
    child: ElevatedButton.icon(
      onPressed: _imageFiles.isEmpty || _isAnalyzing || _isSubmitting ? null : _analyzeImageWithAI,
      icon: const Icon(Icons.auto_awesome_outlined),
      label: _isAnalyzing
          ? const _WaveAnimatedText(text: "Analyze Photo with AI")
          : const Text("Analyze Photo with AI"),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
    ),
  );
}

  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleController,
      enabled: !_isSubmitting, // disable while submitting
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: 'e.g., Mow the lawn, Fix leaky pipe, etc.',
        hintStyle: TextStyle(fontStyle: FontStyle.italic),
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter a short title for your job.';
        }
        if (value.length > 50) {
          return 'Title cannot be more than 50 characters.';
        }
        return null;
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      maxLines: 6,
      enabled: !_isSubmitting, // disable while submitting
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: 'Please describe the job in as much detail as possible. What needs to be done? What are the measurements? etc.',
        hintStyle: TextStyle(fontStyle: FontStyle.italic),
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      validator: (value) {
        if (value == null || value.trim().length < 20) {
          return 'Please provide a detailed description (at least 20 characters).';
        }
        return null;
      },
    );
  }

  Widget _buildPhotoUploader() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
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
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
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

  Widget _buildBudgetDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedBudgetRange,
      decoration: const InputDecoration(
        labelText: 'Select your budget range',
        border: OutlineInputBorder(),
      ),
      items: _budgetRanges.map((range) {
        return DropdownMenuItem(value: range, child: Text(range));
      }).toList(),
      onChanged: _isSubmitting ? null : (value) {
        setState(() => _selectedBudgetRange = value);
      },
      validator: (value) => value == null ? 'Please select a budget range' : null,
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          onPressed: _isSubmitting ? null : _submitRequest,
          child: _isSubmitting
              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Text('Submit Request'),
        ),
      ),
    );
  }
  
  Future<http.Response?> _postWithRetries(Uri uri, Map<String, dynamic> body,
    {int maxRetries = 3, Duration delay = const Duration(seconds: 2)}) async {
  int attempt = 0;
  http.Response? lastResponse;

  while (attempt < maxRetries) {
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return response; // ✅ Success
    }

    final bodyJson = jsonDecode(response.body);
    final errorCode = bodyJson['error']?['code'];
    if (errorCode != 503) {
      //  Non-retriable error
      return response;
    }

    attempt++;
    if (attempt < maxRetries) {
      await Future.delayed(delay);
    }
    lastResponse = response;
  }

  return lastResponse; // after all retries
}
}

class _WaveAnimatedText extends StatefulWidget {
  final String text;

  const _WaveAnimatedText({required this.text, super.key});

  @override
  State<_WaveAnimatedText> createState() => _WaveAnimatedTextState();
}

class _WaveAnimatedTextState extends State<_WaveAnimatedText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.text.length, (i) {
            final progress = _controller.value;
            // Phase shift per character
            final phase = (progress * 2 * 3.1416) + (i * 0.4);
            // Sine wave between 0.4 and 1.0
            final opacity = 0.4 + 0.6 * (0.5 + 0.5 * sin(phase));
            return Opacity(
              opacity: opacity,
              child: Text(
                widget.text[i],
                style: const TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
