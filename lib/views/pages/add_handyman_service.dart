import 'dart:io'; // Import for File
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path; // Import path


import '../../models/handyman_services.dart'; // Adjust path if needed


class AddHandymanServicePage extends StatefulWidget {
  const AddHandymanServicePage({super.key});

  @override
  _AddHandymanServicePageState createState() => _AddHandymanServicePageState();
}

class _AddHandymanServicePageState extends State<AddHandymanServicePage> {
  // Form Key
  final _formKey = GlobalKey<FormState>();

  // Controllers for TextFormFields
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  // Removed: final _establishedSinceController = TextEditingController();

  // Selected values for dropdowns
  String? _selectedCategory;
  String? _selectedPriceType;
  String? _selectedState;
  File? _imageFile; // To store the selected image

  // Image validation state
  bool _imageError = false; // To highlight image picker if validation fails

  // Loading state
  bool _isAdding = false; // To disable button and show loading indicator during submission

  // Firebase
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();
  final _storage = FirebaseStorage.instance;

  // --- Dropdown Options ---
  final List<String> _categories = [
    'Plumbing', 'Electrical', 'Cleaning', 'Air Cond',
    'Carpentry', 'Painting', 'Appliance Repair', 'Home Renovation', 'Other'
  ];
  final List<String> _priceTypes = ['Fixed', 'Hourly'];
  final List<String> _malaysianStates = [
    'Johor', 'Kedah', 'Kelantan', 'Kuala Lumpur', 'Labuan', 'Melaka',
    'Negeri Sembilan', 'Pahang', 'Penang', 'Perak', 'Perlis', 'Putrajaya',
    'Sabah', 'Sarawak', 'Selangor', 'Terengganu'
  ];

  // --- Image Picker ---
  Future<void> _pickImage() async {
    if (!mounted) return;
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _imageError = false; // Reset image error if image is picked
        });
      }
    } catch (e) {
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error picking image: $e')),
          );
       }
       print("Image Picker Error: $e");
    }
  }

  // --- Form Submission ---
  Future<void> _addService() async {
    // Reset image error state before validation
    setState(() { _imageError = false; });

    // 1. Validate Image First (Mandatory)
    if (_imageFile == null) {
      setState(() { _imageError = true; }); // Set error state to highlight picker
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload a service image.'),
          backgroundColor: Colors.orange, // Use a warning color
        ),
      );
      return; // Stop submission
    }

    // 2. Validate the rest of the form
    if (!_formKey.currentState!.validate()) {
       ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all required fields correctly.')),
       );
      return; // Stop if validation fails
    }

    // 3. Check authentication status
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication error. Please log in again.')),
        );
      }
      return;
    }

    // 4. Set loading state
    setState(() { _isAdding = true; });

    try {
      // 5. Generate Service ID (Push Key) FIRST
      final newServiceRef = _database.child('services').push();
      final serviceId = newServiceRef.key; // Get the unique key
      if (serviceId == null) {
        throw Exception("Failed to generate service ID."); // Handle potential error
      }

      // 6. Upload Image using Service ID as filename
      // Use the generated serviceId for the filename
      // Get the original file extension
      final fileExtension = path.extension(_imageFile!.path);
      final fileName = '$serviceId$fileExtension'; // e.g., -Nabcxyz123.jpg
      final Reference storageRef = _storage.ref().child('service_images/$fileName'); // Path in Storage
      final UploadTask uploadTask = storageRef.putFile(_imageFile!);
      final TaskSnapshot snapshot = await uploadTask; // Wait for upload
      final imageUrl = await snapshot.ref.getDownloadURL(); // Get URL

      // 7. Create HandymanService Object (without establishedSince)
      final newService = HandymanService(
        id: serviceId, // Use the generated key as the ID in the object as well
        handymanId: uid,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        priceType: _selectedPriceType!,
        imageUrl: imageUrl, // Use the URL from Storage
        category: _selectedCategory!,
        state: _selectedState!, // This is the service area state
        availability: 'Available', // Default availability
        // removed: establishedSince: int.parse(_establishedSinceController.text.trim()),
        createdAt: DateTime.now(), // Record creation time
      );

      // 8. Add data to Firebase Realtime Database using the generated key
      // The data will be saved at path: services/<serviceId>
      await newServiceRef.set(newService.toMap());

      // 9. Show Success Message and Navigate Back
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Service added successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(); // Go back
      }
    } catch (error) {
      // 10. Handle Errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add service: ${error.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      print("Error adding service: $error");
    } finally {
      // 11. Reset loading state
      if (mounted) {
         setState(() { _isAdding = false; });
      }
    }
  }

  @override
  void dispose() {
    // Dispose controllers
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    // removed: _establishedSinceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Service'),
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Image Picker Widget ---
                _buildImagePicker(), // Uses _imageError state for border
                const SizedBox(height: 20),

                // --- Service Name Input ---
                _buildTextFormField(
                  controller: _nameController,
                  labelText: 'Service Name *',
                  validator: (value) => (value == null || value.isEmpty) ? 'Please enter service name' : null,
                ),
                const SizedBox(height: 16),

                // --- Service Category Dropdown ---
                _buildDropdownFormField(
                  value: _selectedCategory,
                  items: _categories,
                  labelText: 'Service Category *',
                  onChanged: (value) => setState(() => _selectedCategory = value),
                  validator: (value) => (value == null) ? 'Please select a category' : null,
                ),
                const SizedBox(height: 16),

                // --- Price Row ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildTextFormField(
                        controller: _priceController,
                        labelText: 'Price (RM) *',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Enter price';
                          if (double.tryParse(value) == null) return 'Invalid number';
                          if (double.parse(value) <= 0) return 'Price must be > 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDropdownFormField(
                        value: _selectedPriceType,
                        items: _priceTypes,
                        labelText: 'Price Type *',
                        onChanged: (value) => setState(() => _selectedPriceType = value),
                        validator: (value) => (value == null) ? 'Select type' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // --- Service Area (State) Dropdown ---
                _buildDropdownFormField(
                  value: _selectedState,
                  items: _malaysianStates,
                  labelText: 'Service Area (State) *',
                  onChanged: (value) => setState(() => _selectedState = value),
                  validator: (value) => (value == null) ? 'Please select a state' : null,
                ),
                const SizedBox(height: 16),

                // --- REMOVED Established Since Input ---
                // const SizedBox(height: 16),

                // --- Description Input ---
                _buildTextFormField(
                  controller: _descriptionController,
                  labelText: 'Service Description *',
                  maxLines: 4,
                  validator: (value) => (value == null || value.isEmpty) ? 'Please enter service description' : null,
                ),
                const SizedBox(height: 24),

                // --- Submit Button ---
                _buildSubmitButton(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  // Helper method for building the Image Picker UI
  Widget _buildImagePicker() {
    // Use the _imageError state to change border color
    final borderColor = _imageError ? Colors.red : (_imageFile == null ? Colors.grey : Theme.of(context).primaryColor);
    return Center(
      child: Column(
        children: [
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor, width: _imageError ? 2.0 : 1.0), // Highlight border on error
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[100],
            ),
            child: InkWell(
              onTap: _isAdding ? null : _pickImage,
              borderRadius: BorderRadius.circular(12),
              child: _imageFile != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(
                      _imageFile!, fit: BoxFit.cover, width: double.infinity, height: 160,
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 50, color: borderColor), // Icon color matches border
                        const SizedBox(height: 8),
                        Text(
                          'Upload Service Image *', // Indicate mandatory
                          style: TextStyle(color: borderColor)
                        ),
                      ],
                    ),
                  ),
            ),
          ),
          // Show 'Remove Image' button only if an image is selected and not currently adding
          if (_imageFile != null && !_isAdding)
            Padding(
              padding: const EdgeInsets.only(top: 4.0), // Add some space
              child: TextButton.icon(
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Remove Image'),
                onPressed: () => setState(() {
                   _imageFile = null;
                   _imageError = false; // Reset error when image removed
                }),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ),
        ],
      ),
    );
  }

  // Helper method for building standard TextFormFields
  Widget _buildTextFormField({
    required TextEditingController controller,
    required String labelText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    FormFieldValidator<String>? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: labelText,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
        alignLabelWithHint: maxLines > 1,
      ),
      validator: validator,
      enabled: !_isAdding,
      autovalidateMode: AutovalidateMode.onUserInteraction,
    );
  }

   // Helper method for building DropdownButtonFormField
  Widget _buildDropdownFormField({
    required String? value,
    required List<String> items,
    required String labelText,
    required ValueChanged<String?> onChanged,
    FormFieldValidator<String?>? validator,
  }) {
     return DropdownButtonFormField<String>(
       value: value,
       items: items.map((String item) {
         return DropdownMenuItem<String>(
           value: item,
           child: Text(item, overflow: TextOverflow.ellipsis), // Prevent long text overflow
         );
       }).toList(),
       onChanged: _isAdding ? null : onChanged,
       decoration: InputDecoration(
         labelText: labelText,
         border: const OutlineInputBorder(),
         contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
       ),
       validator: validator,
       isExpanded: true, // Ensure it takes full width
       autovalidateMode: AutovalidateMode.onUserInteraction,
     );
  }

  // Helper method for building the Submit button
  Widget _buildSubmitButton() {
    return ElevatedButton.icon(
      icon: _isAdding
          ? Container(
              width: 20, height: 20,
              padding: const EdgeInsets.all(2.0),
              child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
            )
          : const Icon(Icons.add_circle_outline),
      label: Text(_isAdding ? 'Adding Service...' : 'Add Service'),
      onPressed: _isAdding ? null : _addService,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
