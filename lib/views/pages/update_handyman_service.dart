import 'package:flutter/material.dart';
import 'dart:io'; // Import for File
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path; // Import path


class UpdateHandymanServicePage extends StatefulWidget {
  final String serviceId; // Receive the service ID

  const UpdateHandymanServicePage({required this.serviceId, super.key});

  @override
  _UpdateHandymanServicePageState createState() => _UpdateHandymanServicePageState();
}

class _UpdateHandymanServicePageState extends State<UpdateHandymanServicePage> {
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

  // Image state
  File? _newImageFile; // To store a newly picked image for update
  String? _initialImageUrl; // To store the initial image URL loaded from DB

  // State flags
  bool _isLoadingData = true; // To show loading indicator while fetching initial data
  bool _isUpdating = false; // To show progress during update
  bool _isDeleting = false; // To show progress during delete
  bool _hasChanges = false; // To enable/disable update button

  // Store initial values to detect changes
  Map<String, dynamic> _initialServiceData = {};

  // Firebase
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();
  final _storage = FirebaseStorage.instance;

  // --- Dropdown Options (Same as Add Page) ---
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

  @override
  void initState() {
    super.initState();
    _loadServiceData();
  }

  // --- Data Loading ---
  Future<void> _loadServiceData() async {
    setState(() { _isLoadingData = true; });
    try {
      final snapshot = await _database.child('services').child(widget.serviceId).get();

      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        // Store initial data for change detection
        _initialServiceData = Map.from(data); // Make a copy

        // Populate controllers and state variables
        _nameController.text = data['name'] ?? '';
        _descriptionController.text = data['description'] ?? '';
        _priceController.text = (data['price'] ?? 0.0).toString();
        _selectedCategory = data['category'];
        _selectedPriceType = data['priceType'];
        _selectedState = data['state'];
        _initialImageUrl = data['imageUrl']; // Store initial image URL

        // Add listeners AFTER populating controllers to detect subsequent changes
        _addChangeListeners();

      } else {
        // Handle case where service doesn't exist
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Service not found.'), backgroundColor: Colors.red),
          );
          Navigator.of(context).pop(); // Go back if service not found
        }
      }
    } catch (error) {
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading service: $error'), backgroundColor: Colors.red),
          );
       }
       print("Error loading service data: $error");
       if (mounted) Navigator.of(context).pop(); // Go back on error
    } finally {
      if (mounted) {
        setState(() { _isLoadingData = false; });
      }
    }
  }

  // Add listeners to detect form changes
  void _addChangeListeners() {
    _nameController.addListener(_checkForChanges);
    _descriptionController.addListener(_checkForChanges);
    _priceController.addListener(_checkForChanges);
    // Dropdowns and image changes are handled via setState which calls _checkForChanges
  }

  // Remove listeners when disposing
  void _removeChangeListeners() {
     _nameController.removeListener(_checkForChanges);
     _descriptionController.removeListener(_checkForChanges);
     _priceController.removeListener(_checkForChanges);
  }

  // Function to check if any data has changed from initial values
  void _checkForChanges() {
    bool changed = false;
    // Compare text fields
    if (_nameController.text != (_initialServiceData['name'] ?? '')) changed = true;
    if (_descriptionController.text != (_initialServiceData['description'] ?? '')) changed = true;
    // Compare price carefully (parse to double)
    final currentPrice = double.tryParse(_priceController.text);
    final initialPrice = (_initialServiceData['price'] as num?)?.toDouble();
    if (currentPrice != initialPrice) changed = true;

    // Compare dropdowns
    if (_selectedCategory != _initialServiceData['category']) changed = true;
    if (_selectedPriceType != _initialServiceData['priceType']) changed = true;
    if (_selectedState != _initialServiceData['state']) changed = true;

    // Compare image (if a new one was picked)
    if (_newImageFile != null) changed = true;

    // Update the state only if the change status differs
    if (changed != _hasChanges) {
       setState(() { _hasChanges = changed; });
    }
  }


  // --- Image Picker ---
  Future<void> _pickImage() async {
    if (!mounted) return;
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (pickedFile != null) {
        setState(() {
          _newImageFile = File(pickedFile.path);
          _checkForChanges(); // Check for changes after picking image
        });
      }
    } catch (e) {
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
       }
       print("Image Picker Error: $e");
    }
  }

  // --- Form Update ---
  Future<void> _updateService() async {
    // 1. Validate Image (must have either initial or new image)
    if (_newImageFile == null && _initialImageUrl == null) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a service image.'), backgroundColor: Colors.orange),
      );
      // Optionally highlight image picker border again if needed
      return;
    }

    // 2. Validate the rest of the form
    if (!_formKey.currentState!.validate()) {
       ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all required fields correctly.')),
       );
      return;
    }

    // 3. Check Auth
    final uid = _auth.currentUser?.uid;
    if (uid == null) { /* Handle auth error */ return; }

    // 4. Set loading state
    setState(() { _isUpdating = true; });

    try {
      String? finalImageUrl = _initialImageUrl; // Start with the initial URL

      // 5. Upload NEW Image IF it exists
      if (_newImageFile != null) {
        // Define filename using serviceId (safe as serviceId is final)
        final fileExtension = path.extension(_newImageFile!.path);
        final fileName = '${widget.serviceId}$fileExtension';
        final Reference storageRef = _storage.ref().child('service_images/$fileName');

        // Upload the new file
        final UploadTask uploadTask = storageRef.putFile(_newImageFile!);
        final TaskSnapshot snapshot = await uploadTask;
        finalImageUrl = await snapshot.ref.getDownloadURL(); // Get the NEW URL

        // OPTIONAL BUT RECOMMENDED: Delete the old image if it existed and URL changed
        if (_initialImageUrl != null && _initialImageUrl!.isNotEmpty && _initialImageUrl != finalImageUrl) {
          try {
            await _storage.refFromURL(_initialImageUrl!).delete();
             print("Old image deleted successfully.");
          } catch (deleteError) {
            // Log error but don't stop the update process
            print("Error deleting old image: $deleteError");
          }
        }
      }

      // 6. Prepare updated data map
      // Note: We update all fields for simplicity here.
      // Alternatively, only include fields that actually changed.
      final Map<String, dynamic> updatedData = {
        'handymanId': uid, // Keep handymanId consistent
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': double.parse(_priceController.text.trim()),
        'priceType': _selectedPriceType!,
        'imageUrl': finalImageUrl, // Use the final URL (either old or new)
        'category': _selectedCategory!,
        'state': _selectedState!,
        'availability': _initialServiceData['availability'] ?? 'Available', // Preserve original availability or default
        'createdAt': _initialServiceData['createdAt'] ?? DateTime.now().toIso8601String(), // Preserve original creation time
        'updatedAt': DateTime.now().toIso8601String(), // Add/Update modification time
      };

      // 7. Update data in Firebase Realtime Database
      await _database.child('services').child(widget.serviceId).update(updatedData);

      // 8. Show Success & Reset State
      if (mounted) {
        // Update initial data to reflect the save
        _initialServiceData = Map.from(updatedData);
        _initialImageUrl = finalImageUrl; // Update initial URL if it changed
        _newImageFile = null; // Clear the newly picked file state

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Service updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
           _hasChanges = false; // Reset changes flag after successful update
        });
      }
    } catch (error) {
      // 9. Handle Errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update service: $error'), backgroundColor: Colors.red),
        );
      }
      print("Error updating service: $error");
    } finally {
      // 10. Reset loading state
      if (mounted) {
         setState(() { _isUpdating = false; });
      }
    }
  }

  // --- Delete Service ---
  Future<void> _showDeleteConfirmationDialog() async {
     // Prevent showing dialog if already deleting
     if (_isDeleting || !mounted) return;

     final bool? confirmDelete = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Confirm Deletion'),
            content: const Text('Are you sure you want to delete this service? This action cannot be undone.'),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(false), // Return false
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
                onPressed: () => Navigator.of(context).pop(true), // Return true
              ),
            ],
          );
        },
     );

     // If user confirmed deletion
     if (confirmDelete == true) {
        _deleteService();
     }
  }

  Future<void> _deleteService() async {
     if (!mounted) return;
     setState(() { _isDeleting = true; }); // Show loading indicator

     try {
        // 1. Delete from Realtime Database
        await _database.child('services').child(widget.serviceId).remove();

        // 2. Delete Image from Storage (if URL exists)
        if (_initialImageUrl != null && _initialImageUrl!.isNotEmpty) {
           try {
              await _storage.refFromURL(_initialImageUrl!).delete();
              print("Service image deleted from storage.");
           } catch (storageError) {
              // Log error but proceed, as DB entry is more critical
              print("Error deleting service image from storage: $storageError");
              // Optionally inform user image couldn't be deleted
              if(mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('Service data deleted, but failed to delete image from storage.'), backgroundColor: Colors.orange),
                 );
              }
           }
        }

        // 3. Show Success and Navigate Back
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Service deleted successfully.'), backgroundColor: Colors.green),
           );
           // Pop twice if you want to go back past the home page potentially,
           // or just once to return to home page. Adjust as needed.
           Navigator.of(context).pop();
        }

     } catch (error) {
        // Handle Errors
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Failed to delete service: $error'), backgroundColor: Colors.red),
           );
        }
        print("Error deleting service: $error");
     } finally {
        if (mounted) {
           setState(() { _isDeleting = false; }); // Hide loading indicator
        }
     }
  }


  @override
  void dispose() {
    // Dispose controllers and remove listeners
    _removeChangeListeners();
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
        title: const Text('Update Service'),
        elevation: 1,
        actions: [
          // Delete Button
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete Service',
            // Disable button while deleting or loading initial data
            onPressed: (_isDeleting || _isLoadingData) ? null : _showDeleteConfirmationDialog,
          ),
        ],
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator()) // Show loading indicator while fetching
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // --- Image Picker Widget ---
                      _buildImagePicker(),
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
                        onChanged: (value) => setState(() { _selectedCategory = value; _checkForChanges(); }),
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
                              onChanged: (value) => setState(() { _selectedPriceType = value; _checkForChanges(); }),
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
                        onChanged: (value) => setState(() { _selectedState = value; _checkForChanges(); }),
                        validator: (value) => (value == null) ? 'Please select a state' : null,
                      ),
                      const SizedBox(height: 16),

                      // --- Description Input ---
                      _buildTextFormField(
                        controller: _descriptionController,
                        labelText: 'Service Description *',
                        maxLines: 4,
                        validator: (value) => (value == null || value.isEmpty) ? 'Please enter service description' : null,
                      ),
                      const SizedBox(height: 24),

                      // --- Update Button ---
                      _buildSubmitButton(), // Now handles update logic
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
    // Determine border color based on validation state (_hasChanges implies validation passed if button enabled)
    // For simplicity, just check if _initialImageUrl or _newImageFile exists
    final bool hasImage = _newImageFile != null || (_initialImageUrl != null && _initialImageUrl!.isNotEmpty);
    final borderColor = !hasImage && _hasChanges ? Colors.red : Colors.grey; // Simplified error indication

    return Center(
      child: Column(
        children: [
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[100],
            ),
            child: InkWell(
              onTap: (_isUpdating || _isDeleting) ? null : _pickImage, // Disable tap when busy
              borderRadius: BorderRadius.circular(12),
              child: Stack( // Use Stack to overlay image/placeholder
                alignment: Alignment.center,
                children: [
                  // Display new image if picked
                  if (_newImageFile != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.file(
                        _newImageFile!, fit: BoxFit.cover, width: double.infinity, height: 160,
                      ),
                    )
                  // Display initial image if no new one picked AND initial exists
                  else if (_initialImageUrl != null && _initialImageUrl!.isNotEmpty)
                     ClipRRect(
                       borderRadius: BorderRadius.circular(11),
                       child: Image.network( // Load initial image from URL
                         _initialImageUrl!,
                         fit: BoxFit.cover, width: double.infinity, height: 160,
                         // Add loading/error builders for network image
                         loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
                         errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                       ),
                     )
                  // Placeholder if no image exists (initial or new)
                  else
                     const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 50, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('Upload Service Image *', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
          // Show 'Change Image' button only if not currently busy
          if (!_isUpdating && !_isDeleting)
             Padding(
               padding: const EdgeInsets.only(top: 4.0),
               child: TextButton.icon(
                 icon: Icon(_initialImageUrl != null || _newImageFile != null ? Icons.edit : Icons.add_photo_alternate, size: 18),
                 label: Text(_initialImageUrl != null || _newImageFile != null ? 'Change Image' : 'Upload Image'),
                 onPressed: _pickImage,
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
      // Disable field when updating or deleting
      enabled: !_isUpdating && !_isDeleting,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      // Call _checkForChanges when field content changes
      // Note: This is handled by the listener added in initState
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
           child: Text(item, overflow: TextOverflow.ellipsis),
         );
       }).toList(),
       // Disable dropdown when updating or deleting
       onChanged: (_isUpdating || _isDeleting) ? null : onChanged,
       decoration: InputDecoration(
         labelText: labelText,
         border: const OutlineInputBorder(),
         contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
       ),
       validator: validator,
       isExpanded: true,
       autovalidateMode: AutovalidateMode.onUserInteraction,
     );
  }

  // Helper method for building the Submit (Update) button
  Widget _buildSubmitButton() {
    return ElevatedButton.icon(
      icon: _isUpdating
          ? Container(
              width: 20, height: 20, padding: const EdgeInsets.all(2.0),
              child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),
            )
          : const Icon(Icons.save_alt_outlined), // Save icon for update
      label: Text(_isUpdating ? 'Updating...' : 'Update Service'),
      // Disable button if no changes, or if updating/deleting
      onPressed: (_hasChanges && !_isUpdating && !_isDeleting) ? _updateService : null,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        // Grey out button visually when disabled
        disabledBackgroundColor: Colors.grey[300],
        disabledForegroundColor: Colors.grey[500],
      ),
    );
  }
}
