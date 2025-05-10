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

  // Selected values for dropdowns
  String? _selectedCategory;
  String? _selectedPriceType;
  String? _selectedState;
  String? _selectedDistrict; // *** NEW: For selected district ***
  File? _imageFile; // To store the selected image

  // Image validation state
  bool _imageError = false;

  // Loading state
  bool _isAdding = false;

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

  // *** NEW: Data for Districts by State (Sample - expand as needed) ***
  final Map<String, List<String>> _malaysianDistrictsByState = {
    'Johor': ['Johor Bahru', 'Batu Pahat', 'Kluang', 'Kulai', 'Muar', 'Kota Tinggi', 'Segamat', 'Pontian', 'Tangkak', 'Mersing'],
    'Kedah': ['Kota Setar', 'Kuala Muda', 'Kubang Pasu', 'Kulim', 'Langkawi', 'Padang Terap', 'Pendang', 'Sik', 'Yan', 'Baling', 'Bandar Baharu', 'Pokok Sena'],
    'Kelantan': ['Kota Bharu', 'Pasir Mas', 'Tumpat', 'Pasir Puteh', 'Bachok', 'Kuala Krai', 'Machang', 'Tanah Merah', 'Jeli', 'Gua Musang'],
    'Melaka': ['Melaka Tengah', 'Alor Gajah', 'Jasin'],
    'Negeri Sembilan': ['Seremban', 'Jempol', 'Port Dickson', 'Tampin', 'Kuala Pilah', 'Rembau', 'Jelebu'],
    'Pahang': ['Kuantan', 'Temerloh', 'Bentong', 'Maran', 'Rompin', 'Pekan', 'Bera', 'Raub', 'Jerantut', 'Lipis', 'Cameron Highlands'],
    'Penang': ['Timur Laut (George Town)', 'Barat Daya (Balik Pulau)', 'Seberang Perai Utara (Butterworth)', 'Seberang Perai Tengah (Bukit Mertajam)', 'Seberang Perai Selatan (Nibong Tebal)'],
    'Perak': ['Kinta (Ipoh)', 'Larut, Matang dan Selama (Taiping)', 'Manjung (Seri Manjung)', 'Hilir Perak (Teluk Intan)', 'Kerian (Parit Buntar)', 'Batang Padang (Tapah)', 'Kuala Kangsar', 'Perak Tengah (Seri Iskandar)', 'Hulu Perak (Gerik)', 'Kampar', 'Muallim (Tanjung Malim)', 'Bagan Datuk'],
    'Perlis': ['Perlis (Kangar)'], // Perlis has no formal districts, often the state itself is considered
    'Sabah': ['Kota Kinabalu', 'Sandakan', 'Tawau', 'Lahad Datu', 'Keningau', 'Penampang', 'Semporna', 'Papar', 'Tuaran', 'Kinabatangan', 'Beluran', 'Beaufort', 'Kudat', 'Ranau', 'Sipitang', 'Kota Belud', 'Kota Marudu', 'Tambunan', 'Tenom', 'Kuala Penyu', 'Pitas', 'Putatan', 'Telupid', 'Tongod', 'Kunak', 'Nabawan', 'Kalabakan'],
    'Sarawak': ['Kuching', 'Miri', 'Sibu', 'Bintulu', 'Serian', 'Samarahan', 'Sri Aman', 'Betong', 'Sarikei', 'Kapit', 'Mukah', 'Limbang', 'Bau', 'Lundu', 'Simunjan', /* Add more as needed */],
    'Selangor': ['Petaling (Petaling Jaya, Shah Alam)', 'Hulu Langat (Kajang)', 'Gombak (Selayang)', 'Klang', 'Kuala Langat (Banting)', 'Sepang', 'Kuala Selangor', 'Sabak Bernam', 'Hulu Selangor'],
    'Terengganu': ['Kuala Terengganu', 'Kemaman', 'Dungun', 'Besut', 'Hulu Terengganu', 'Marang', 'Setiu', 'Kuala Nerus'],
    'Kuala Lumpur': ['Kuala Lumpur'], // Wilayah Persekutuan usually not broken down further in this context
    'Labuan': ['Labuan'],
    'Putrajaya': ['Putrajaya'],
  };

  List<String> _districtsForSelectedState = []; // To hold districts for the selected state

  // --- Helper to update district list based on selected state ---
  void _updateDistrictList(String? selectedState) {
    if (selectedState != null && _malaysianDistrictsByState.containsKey(selectedState)) {
      setState(() {
        _districtsForSelectedState = _malaysianDistrictsByState[selectedState]!;
        _selectedDistrict = null; // Reset district when state changes
      });
    } else {
      setState(() {
        _districtsForSelectedState = [];
        _selectedDistrict = null;
      });
    }
  }


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
          _imageError = false;
        });
      }
    } catch (e) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking image: $e')),);
       }
       print("Image Picker Error: $e");
    }
  }

  Future<void> _addService() async {
    setState(() { _imageError = false; });

    if (_imageFile == null) {
      setState(() { _imageError = true; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload a service image.'), backgroundColor: Colors.orange,));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authentication error. Please log in again.')),);
      return;
    }

    setState(() { _isAdding = true; });

    try {
      final newServiceRef = _database.child('services').push();
      final serviceId = newServiceRef.key;
      if (serviceId == null) throw Exception("Failed to generate service ID.");

      final fileExtension = path.extension(_imageFile!.path);
      final fileName = '$serviceId$fileExtension';
      final Reference storageRef = _storage.ref().child('service_images/$fileName');
      final UploadTask uploadTask = storageRef.putFile(_imageFile!);
      final TaskSnapshot snapshot = await uploadTask;
      final imageUrl = await snapshot.ref.getDownloadURL();

      final newService = HandymanService(
        id: serviceId,
        handymanId: uid,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        priceType: _selectedPriceType!,
        imageUrl: imageUrl,
        category: _selectedCategory!,
        state: _selectedState!,
        district: _selectedDistrict, // *** NEW: Add selected district ***
        availability: 'Available',
        createdAt: DateTime.now(),
      );

      await newServiceRef.set(newService.toMap());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service added successfully!'), backgroundColor: Colors.green, duration: Duration(seconds: 2),));
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add service: ${error.toString()}'), backgroundColor: Colors.red, duration: const Duration(seconds: 4),));
      print("Error adding service: $error");
    } finally {
      if (mounted) setState(() { _isAdding = false; });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
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
                _buildImagePicker(),
                const SizedBox(height: 20),
                _buildTextFormField(controller: _nameController, labelText: 'Service Name *', validator: (value) => (value == null || value.isEmpty) ? 'Please enter service name' : null,),
                const SizedBox(height: 16),
                _buildDropdownFormField(value: _selectedCategory, items: _categories, labelText: 'Service Category *', onChanged: (value) => setState(() => _selectedCategory = value), validator: (value) => (value == null) ? 'Please select a category' : null,),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildTextFormField(controller: _priceController, labelText: 'Price (RM) *', keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (value) { if (value == null || value.isEmpty) return 'Enter price'; if (double.tryParse(value) == null) return 'Invalid number'; if (double.parse(value) <= 0) return 'Price must be > 0'; return null; },),),
                    const SizedBox(width: 12),
                    Expanded(child: _buildDropdownFormField(value: _selectedPriceType, items: _priceTypes, labelText: 'Price Type *', onChanged: (value) => setState(() => _selectedPriceType = value), validator: (value) => (value == null) ? 'Select type' : null,),),
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
                      _updateDistrictList(value); // *** NEW: Update district list on state change ***
                    });
                  },
                  validator: (value) => (value == null) ? 'Please select a state' : null,
                ),
                const SizedBox(height: 16),

                // *** NEW: Service Area (District) Dropdown ***
                if (_selectedState != null && _districtsForSelectedState.isNotEmpty) // Only show if state is selected and districts exist
                  _buildDropdownFormField(
                    value: _selectedDistrict,
                    items: _districtsForSelectedState,
                    labelText: 'Service Area (District) *',
                    onChanged: (value) => setState(() => _selectedDistrict = value),
                    // Validator can be optional or required based on your business logic
                    validator: (value) => (value == null) ? 'Please select a district' : null,
                    // Note: The 'enabled' property is handled by the visibility (_selectedState != null)
                    // and also within _buildDropdownFormField via _isAdding.
                  ),
                if (_selectedState != null && _districtsForSelectedState.isNotEmpty)
                  const SizedBox(height: 16), // Add spacing if district dropdown is shown

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

  Widget _buildImagePicker() {
    final borderColor = _imageError ? Colors.red : (_imageFile == null ? Colors.grey : Theme.of(context).primaryColor);
    return Center(
      child: Column(
        children: [
          Container(
            height: 160, width: double.infinity,
            decoration: BoxDecoration(border: Border.all(color: borderColor, width: _imageError ? 2.0 : 1.0), borderRadius: BorderRadius.circular(12), color: Colors.grey[100],),
            child: InkWell(
              onTap: _isAdding ? null : _pickImage, borderRadius: BorderRadius.circular(12),
              child: _imageFile != null
                ? ClipRRect(borderRadius: BorderRadius.circular(11), child: Image.file(_imageFile!, fit: BoxFit.cover, width: double.infinity, height: 160,),)
                : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.add_photo_alternate_outlined, size: 50, color: borderColor), const SizedBox(height: 8), Text('Upload Service Image *', style: TextStyle(color: borderColor)),],),),),),
          if (_imageFile != null && !_isAdding) Padding(padding: const EdgeInsets.only(top: 4.0), child: TextButton.icon(icon: const Icon(Icons.close, size: 18), label: const Text('Remove Image'), onPressed: () => setState(() { _imageFile = null; _imageError = false; }), style: TextButton.styleFrom(foregroundColor: Colors.red),),),
        ],
      ),
    );
  }

  Widget _buildTextFormField({ required TextEditingController controller, required String labelText, TextInputType keyboardType = TextInputType.text, int maxLines = 1, FormFieldValidator<String>? validator,}) {
    return TextFormField(
      controller: controller, keyboardType: keyboardType, maxLines: maxLines,
      decoration: InputDecoration(labelText: labelText, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0), alignLabelWithHint: maxLines > 1,),
      validator: validator, enabled: !_isAdding, autovalidateMode: AutovalidateMode.onUserInteraction,);
  }

 Widget _buildDropdownFormField({ required String? value, required List<String> items, required String labelText, required ValueChanged<String?> onChanged, FormFieldValidator<String?>? validator, bool enabled = true, // Added enabled flag
 }) {
   return DropdownButtonFormField<String>(
     value: value,
     items: items.map((String item) {
       return DropdownMenuItem<String>(value: item, child: Text(item, overflow: TextOverflow.ellipsis),);
     }).toList(),
     // Disable if _isAdding OR if explicitly passed as not enabled
     onChanged: (_isAdding || !enabled) ? null : onChanged,
     decoration: InputDecoration(
       labelText: labelText, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
       // Optionally, change fill color if disabled (though parent logic usually handles this)
       // filled: !enabled,
       // fillColor: !enabled ? Colors.grey[200] : null,
     ),
     validator: validator, isExpanded: true, autovalidateMode: AutovalidateMode.onUserInteraction,);
 }

  Widget _buildSubmitButton() {
    return ElevatedButton.icon(
      icon: _isAdding ? Container(width: 20, height: 20, padding: const EdgeInsets.all(2.0), child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0),) : const Icon(Icons.add_circle_outline),
      label: Text(_isAdding ? 'Adding Service...' : 'Add Service'),
      onPressed: _isAdding ? null : _addService,
      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600), elevation: 3, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),),);
  }
}