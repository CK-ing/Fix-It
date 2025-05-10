import 'package:flutter/material.dart';
import 'dart:io'; // Import for File
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path; // Import path

// Assuming HandymanService model is in the same directory or adjust path
import '../../models/handyman_services.dart';


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

  // Selected values for dropdowns
  String? _selectedCategory;
  String? _selectedPriceType;
  String? _selectedState;
  String? _selectedDistrict; // *** NEW: For selected district ***

  // Image state
  File? _newImageFile;
  String? _initialImageUrl;

  // State flags
  bool _isLoadingData = true;
  bool _isUpdating = false;
  bool _isDeleting = false;
  bool _hasChanges = false;

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

  // *** NEW: Data for Districts by State (Sample - should be consistent with Add page) ***
  final Map<String, List<String>> _malaysianDistrictsByState = {
    'Johor': ['Johor Bahru', 'Batu Pahat', 'Kluang', 'Kulai', 'Muar', 'Kota Tinggi', 'Segamat', 'Pontian', 'Tangkak', 'Mersing'],
    'Kedah': ['Kota Setar', 'Kuala Muda', 'Kubang Pasu', 'Kulim', 'Langkawi', 'Padang Terap', 'Pendang', 'Sik', 'Yan', 'Baling', 'Bandar Baharu', 'Pokok Sena'],
    'Kelantan': ['Kota Bharu', 'Pasir Mas', 'Tumpat', 'Pasir Puteh', 'Bachok', 'Kuala Krai', 'Machang', 'Tanah Merah', 'Jeli', 'Gua Musang'],
    'Melaka': ['Melaka Tengah', 'Alor Gajah', 'Jasin'],
    'Negeri Sembilan': ['Seremban', 'Jempol', 'Port Dickson', 'Tampin', 'Kuala Pilah', 'Rembau', 'Jelebu'],
    'Pahang': ['Kuantan', 'Temerloh', 'Bentong', 'Maran', 'Rompin', 'Pekan', 'Bera', 'Raub', 'Jerantut', 'Lipis', 'Cameron Highlands'],
    'Penang': ['Timur Laut (George Town)', 'Barat Daya (Balik Pulau)', 'Seberang Perai Utara (Butterworth)', 'Seberang Perai Tengah (Bukit Mertajam)', 'Seberang Perai Selatan (Nibong Tebal)'],
    'Perak': ['Kinta (Ipoh)', 'Larut, Matang dan Selama (Taiping)', 'Manjung (Seri Manjung)', 'Hilir Perak (Teluk Intan)', 'Kerian (Parit Buntar)', 'Batang Padang (Tapah)', 'Kuala Kangsar', 'Perak Tengah (Seri Iskandar)', 'Hulu Perak (Gerik)', 'Kampar', 'Muallim (Tanjung Malim)', 'Bagan Datuk'],
    'Perlis': ['Perlis (Kangar)'],
    'Sabah': ['Kota Kinabalu', 'Sandakan', 'Tawau', 'Lahad Datu', 'Keningau', 'Penampang', 'Semporna', 'Papar', 'Tuaran', 'Kinabatangan', 'Beluran', 'Beaufort', 'Kudat', 'Ranau', 'Sipitang', 'Kota Belud', 'Kota Marudu', 'Tambunan', 'Tenom', 'Kuala Penyu', 'Pitas', 'Putatan', 'Telupid', 'Tongod', 'Kunak', 'Nabawan', 'Kalabakan'],
    'Sarawak': ['Kuching', 'Miri', 'Sibu', 'Bintulu', 'Serian', 'Samarahan', 'Sri Aman', 'Betong', 'Sarikei', 'Kapit', 'Mukah', 'Limbang', 'Bau', 'Lundu', 'Simunjan', /* Add more as needed */],
    'Selangor': ['Petaling (Petaling Jaya, Shah Alam)', 'Hulu Langat (Kajang)', 'Gombak (Selayang)', 'Klang', 'Kuala Langat (Banting)', 'Sepang', 'Kuala Selangor', 'Sabak Bernam', 'Hulu Selangor'],
    'Terengganu': ['Kuala Terengganu', 'Kemaman', 'Dungun', 'Besut', 'Hulu Terengganu', 'Marang', 'Setiu', 'Kuala Nerus'],
    'Kuala Lumpur': ['Kuala Lumpur'],
    'Labuan': ['Labuan'],
    'Putrajaya': ['Putrajaya'],
  };

  List<String> _districtsForSelectedState = [];

  @override
  void initState() {
    super.initState();
    _loadServiceData();
  }

  // --- Helper to update district list based on selected state ---
  void _updateDistrictList(String? selectedState, {String? initialDistrict}) {
    if (selectedState != null && _malaysianDistrictsByState.containsKey(selectedState)) {
      // Check if widget is still mounted before calling setState
      if (mounted) {
        setState(() {
          _districtsForSelectedState = _malaysianDistrictsByState[selectedState]!;
          // If an initialDistrict is provided and it exists in the new list, set it.
          // Otherwise, or if no initialDistrict, reset _selectedDistrict.
          if (initialDistrict != null && _districtsForSelectedState.contains(initialDistrict)) {
            _selectedDistrict = initialDistrict;
          } else {
            _selectedDistrict = null; // Reset district when state changes or initialDistrict not valid
          }
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _districtsForSelectedState = [];
          _selectedDistrict = null;
        });
      }
    }
  }


  Future<void> _loadServiceData() async {
    if (!mounted) return;
    setState(() { _isLoadingData = true; });
    try {
      final snapshot = await _database.child('services').child(widget.serviceId).get();
      if (!mounted) return;

      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        _initialServiceData = Map.from(data);

        _nameController.text = data['name'] ?? '';
        _descriptionController.text = data['description'] ?? '';
        _priceController.text = (data['price'] ?? 0.0).toString();
        _selectedCategory = data['category'];
        _selectedPriceType = data['priceType'];
        _selectedState = data['state'];
        _initialImageUrl = data['imageUrl'];

        // *** NEW: Populate district list based on loaded state and set selected district ***
        if (_selectedState != null) {
          _updateDistrictList(_selectedState, initialDistrict: data['district'] as String?);
        } else {
          _updateDistrictList(null); // Clear districts if no state
        }
        // _selectedDistrict is set within _updateDistrictList
        
        _addChangeListeners();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service not found.'), backgroundColor: Colors.red),);
          Navigator.of(context).pop();
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading service: $error'), backgroundColor: Colors.red),);
        Navigator.of(context).pop();
      }
      print("Error loading service data: $error");
    } finally {
      if (mounted) setState(() { _isLoadingData = false; });
    }
  }

  void _addChangeListeners() {
    _nameController.addListener(_checkForChanges);
    _descriptionController.addListener(_checkForChanges);
    _priceController.addListener(_checkForChanges);
  }

  void _removeChangeListeners() {
     _nameController.removeListener(_checkForChanges);
     _descriptionController.removeListener(_checkForChanges);
     _priceController.removeListener(_checkForChanges);
  }

  void _checkForChanges() {
    bool changed = false;
    if (_nameController.text != (_initialServiceData['name'] ?? '')) changed = true;
    if (_descriptionController.text != (_initialServiceData['description'] ?? '')) changed = true;
    final currentPrice = double.tryParse(_priceController.text);
    final initialPrice = (_initialServiceData['price'] as num?)?.toDouble();
    if (currentPrice != initialPrice) changed = true;

    if (_selectedCategory != _initialServiceData['category']) changed = true;
    if (_selectedPriceType != _initialServiceData['priceType']) changed = true;
    if (_selectedState != _initialServiceData['state']) changed = true;
    // *** NEW: Check for district changes ***
    if (_selectedDistrict != _initialServiceData['district']) changed = true;

    if (_newImageFile != null) changed = true;

    if (changed != _hasChanges && mounted) { // Add mounted check
        setState(() { _hasChanges = changed; });
    }
  }

  Future<void> _pickImage() async { /* ... remains same ... */
    if (!mounted) return;
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (pickedFile != null) {
        setState(() {
          _newImageFile = File(pickedFile.path);
          _checkForChanges(); 
        });
      }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
       print("Image Picker Error: $e");
    }
  }

  Future<void> _updateService() async {
    if (_newImageFile == null && (_initialImageUrl == null || _initialImageUrl!.isEmpty)) { // Check for empty initial URL too
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload a service image.'), backgroundColor: Colors.orange),);
       return;
    }
    if (!_formKey.currentState!.validate()) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields correctly.')),);
       return;
    }
    // *** NEW: Validate district if a state is selected and districts are available ***
    if (_selectedState != null && _districtsForSelectedState.isNotEmpty && _selectedDistrict == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a district for the chosen state.'), backgroundColor: Colors.orange,),);
        return;
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) { 
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authentication Error. Please log in again.'), backgroundColor: Colors.red),);
      return; 
    }

    setState(() { _isUpdating = true; });

    try {
      String? finalImageUrl = _initialImageUrl;
      if (_newImageFile != null) {
        final fileExtension = path.extension(_newImageFile!.path);
        final fileName = '${widget.serviceId}$fileExtension';
        final Reference storageRef = _storage.ref().child('service_images/$fileName');
        final UploadTask uploadTask = storageRef.putFile(_newImageFile!);
        final TaskSnapshot snapshot = await uploadTask;
        finalImageUrl = await snapshot.ref.getDownloadURL();
        if (_initialImageUrl != null && _initialImageUrl!.isNotEmpty && _initialImageUrl != finalImageUrl) {
          try {
            await _storage.refFromURL(_initialImageUrl!).delete();
            print("Old image deleted successfully.");
          } catch (deleteError) { print("Error deleting old image: $deleteError"); }
        }
      }

      final Map<String, dynamic> updatedData = {
        'handymanId': uid,
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': double.parse(_priceController.text.trim()),
        'priceType': _selectedPriceType!,
        'imageUrl': finalImageUrl,
        'category': _selectedCategory!,
        'state': _selectedState!,
        'district': _selectedDistrict, // *** NEW: Save updated district ***
        'availability': _initialServiceData['availability'] ?? 'Available',
        'createdAt': _initialServiceData['createdAt'] ?? DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await _database.child('services').child(widget.serviceId).update(updatedData);

      if (mounted) {
        _initialServiceData = Map.from(updatedData); // Update initial data for future change checks
        _initialImageUrl = finalImageUrl;
        _newImageFile = null;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service updated successfully!'), backgroundColor: Colors.green,));
        setState(() { _hasChanges = false; });
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update service: $error'), backgroundColor: Colors.red),);
      print("Error updating service: $error");
    } finally {
      if (mounted) setState(() { _isUpdating = false; });
    }
  }

  Future<void> _showDeleteConfirmationDialog() async { /* ... remains same ... */
    if (_isDeleting || !mounted) return;
    final bool? confirmDelete = await showDialog<bool>( context: context, builder: (BuildContext context) { return AlertDialog( title: const Text('Confirm Deletion'), content: const Text('Are you sure you want to delete this service? This action cannot be undone.'), actions: <Widget>[ TextButton( child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop(false),), TextButton( style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete'), onPressed: () => Navigator.of(context).pop(true),),],);},);
    if (confirmDelete == true) _deleteService();
  }
  Future<void> _deleteService() async { /* ... remains same ... */
    if (!mounted) return; setState(() { _isDeleting = true; });
    try {
      await _database.child('services').child(widget.serviceId).remove();
      if (_initialImageUrl != null && _initialImageUrl!.isNotEmpty) {
        try { await _storage.refFromURL(_initialImageUrl!).delete(); print("Service image deleted from storage."); }
        catch (storageError) { print("Error deleting service image from storage: $storageError"); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service data deleted, but failed to delete image from storage.'), backgroundColor: Colors.orange),); }
      }
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service deleted successfully.'), backgroundColor: Colors.green),); Navigator.of(context).pop(); }
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete service: $error'), backgroundColor: Colors.red),); print("Error deleting service: $error"); }
    finally { if (mounted) setState(() { _isDeleting = false; });}
  }

  @override
  void dispose() {
    _removeChangeListeners();
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Service'),
        elevation: 1,
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Delete Service', onPressed: (_isDeleting || _isLoadingData) ? null : _showDeleteConfirmationDialog,),
        ],
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildImagePicker(),
                      const SizedBox(height: 20),
                      _buildTextFormField(controller: _nameController, labelText: 'Service Name *', validator: (value) => (value == null || value.isEmpty) ? 'Please enter service name' : null,),
                      const SizedBox(height: 16),
                      _buildDropdownFormField(value: _selectedCategory, items: _categories, labelText: 'Service Category *', onChanged: (value) => setState(() { _selectedCategory = value; _checkForChanges(); }), validator: (value) => (value == null) ? 'Please select a category' : null,),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildTextFormField(controller: _priceController, labelText: 'Price (RM) *', keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (value) { if (value == null || value.isEmpty) return 'Enter price'; if (double.tryParse(value) == null) return 'Invalid number'; if (double.parse(value) <= 0) return 'Price must be > 0'; return null; },),),
                          const SizedBox(width: 12),
                          Expanded(child: _buildDropdownFormField(value: _selectedPriceType, items: _priceTypes, labelText: 'Price Type *', onChanged: (value) => setState(() { _selectedPriceType = value; _checkForChanges(); }), validator: (value) => (value == null) ? 'Select type' : null,),),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // --- Service Area (State) Dropdown ---
                      _buildDropdownFormField(
                        value: _selectedState,
                        items: _malaysianStates,
                        labelText: 'Service Area (State) *',
                        onChanged: (value) {
                          setState(() {
                            _selectedState = value;
                            _updateDistrictList(value); // Update district list
                            _checkForChanges(); // Check if this state change itself is a change
                          });
                        },
                        validator: (value) => (value == null) ? 'Please select a state' : null,
                      ),
                      const SizedBox(height: 16),

                      // *** NEW: Service Area (District) Dropdown ***
                      if (_selectedState != null && _districtsForSelectedState.isNotEmpty)
                        _buildDropdownFormField(
                          value: _selectedDistrict,
                          items: _districtsForSelectedState,
                          labelText: 'Service Area (District) *',
                          onChanged: (value) => setState(() {
                            _selectedDistrict = value;
                            _checkForChanges(); // Check for changes when district is selected
                          }),
                          validator: (value) => (value == null) ? 'Please select a district' : null,
                          enabled: !_isUpdating && !_isDeleting, // Use the helper's enabled flag
                        ),
                      if (_selectedState != null && _districtsForSelectedState.isNotEmpty)
                        const SizedBox(height: 16),


                      _buildTextFormField(controller: _descriptionController, labelText: 'Service Description *', maxLines: 4, validator: (value) => (value == null || value.isEmpty) ? 'Please enter service description' : null,),
                      const SizedBox(height: 24),
                      _buildSubmitButton(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildImagePicker() { /* ... remains same ... */
    final bool hasImage = _newImageFile != null || (_initialImageUrl != null && _initialImageUrl!.isNotEmpty);
    final borderColor = !hasImage && _hasChanges ? Colors.red : Colors.grey;
    return Center(child: Column(children: [ Container(height: 160, width: double.infinity, decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(12), color: Colors.grey[100],), child: InkWell(onTap: (_isUpdating || _isDeleting) ? null : _pickImage, borderRadius: BorderRadius.circular(12), child: Stack(alignment: Alignment.center, children: [ if (_newImageFile != null) ClipRRect(borderRadius: BorderRadius.circular(11), child: Image.file(_newImageFile!, fit: BoxFit.cover, width: double.infinity, height: 160,),) else if (_initialImageUrl != null && _initialImageUrl!.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(11), child: Image.network(_initialImageUrl!, fit: BoxFit.cover, width: double.infinity, height: 160, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()), errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),),) else const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.add_photo_alternate_outlined, size: 50, color: Colors.grey), SizedBox(height: 8), Text('Upload Service Image *', style: TextStyle(color: Colors.grey)),],),),],),),), if (!_isUpdating && !_isDeleting) Padding(padding: const EdgeInsets.only(top: 4.0), child: TextButton.icon(icon: Icon(_initialImageUrl != null || _newImageFile != null ? Icons.edit : Icons.add_photo_alternate, size: 18), label: Text(_initialImageUrl != null || _newImageFile != null ? 'Change Image' : 'Upload Image'), onPressed: _pickImage,),),],),);
  }

  Widget _buildTextFormField({ required TextEditingController controller, required String labelText, TextInputType keyboardType = TextInputType.text, int maxLines = 1, FormFieldValidator<String>? validator,}) {
    return TextFormField(controller: controller, keyboardType: keyboardType, maxLines: maxLines, decoration: InputDecoration(labelText: labelText, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0), alignLabelWithHint: maxLines > 1,), validator: validator, enabled: !_isUpdating && !_isDeleting, autovalidateMode: AutovalidateMode.onUserInteraction,);
  }

 Widget _buildDropdownFormField({ required String? value, required List<String> items, required String labelText, required ValueChanged<String?> onChanged, FormFieldValidator<String?>? validator, bool enabled = true, // Keep this for general purpose disabling
 }) {
   return DropdownButtonFormField<String>(
     value: value,
     items: items.map((String item) {
       return DropdownMenuItem<String>(value: item, child: Text(item, overflow: TextOverflow.ellipsis),);
     }).toList(),
     // Also consider overall form state for enabling
     onChanged: (_isUpdating || _isDeleting || !enabled) ? null : onChanged,
     decoration: InputDecoration(
       labelText: labelText, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
       // fillColor: !enabled || _isUpdating || _isDeleting ? Colors.grey[200] : null,
       // filled: !enabled || _isUpdating || _isDeleting,
     ),
     validator: validator, isExpanded: true, autovalidateMode: AutovalidateMode.onUserInteraction,);
 }

  Widget _buildSubmitButton() { /* ... remains same ... */
    return ElevatedButton.icon(icon: _isUpdating ? Container(width: 20, height: 20, padding: const EdgeInsets.all(2.0), child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),) : const Icon(Icons.save_alt_outlined), label: Text(_isUpdating ? 'Updating...' : 'Update Service'), onPressed: (_hasChanges && !_isUpdating && !_isDeleting) ? _updateService : null, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600), elevation: 3, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), disabledBackgroundColor: Colors.grey[300], disabledForegroundColor: Colors.grey[500],),);
  }
}