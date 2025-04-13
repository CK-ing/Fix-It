import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseDatabase.instance.ref();
  final _storage = FirebaseStorage.instance;

  bool _isSaving = false;
  File? _imageFile;
  String? _downloadUrl;

  late TextEditingController _phoneController;
  late TextEditingController _addressController;
  late TextEditingController _descriptionController;

  String? _selectedCategory;
  String? _selectedState;
  String? _establishedYear;
  bool? _isAvailable;
  String _role = '';
  String _name = '';
  String _email = '';

  final List<String> _categories = ['Electrician', 'Plumber', 'Carpenter', 'Painter', 'Cleaner'];
  final List<String> _states = [
    'Johor', 'Kedah', 'Kelantan', 'Melaka', 'Negeri Sembilan', 'Pahang',
    'Penang', 'Perak', 'Perlis', 'Sabah', 'Sarawak', 'Selangor',
    'Terengganu', 'Kuala Lumpur', 'Putrajaya', 'Labuan'
  ];

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _descriptionController = TextEditingController();
    _loadUserData();
  }

  void _loadUserData() async {
    final uid = _auth.currentUser!.uid;
    final snapshot = await _db.child('users/$uid').get();
    if(mounted){
      if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      setState(() {
        _role = data['role'] ?? '';
        _name = data['name'] ?? '';
        _email = data['email'] ?? '';
        _phoneController.text = data['phoneNumber'] ?? '';
        _addressController.text = data['address'] ?? '';
        _selectedCategory = data['category'];
        _selectedState = data['areaOfService'];
        _establishedYear = data['establishedSince']?.toString();
        dynamic availabilityData = data['availability']; // Read dynamically
      if (availabilityData is bool) {
        _isAvailable = availabilityData; // Use if already boolean
      } else if (availabilityData is String) {
         // Convert string (case-insensitive) from old saves
        _isAvailable = availabilityData.toLowerCase() == 'available';
      } else {
        _isAvailable = false; // Default to false if null or other type
      }
        _descriptionController.text = data['description'] ?? '';
        _downloadUrl = data['profileImageUrl'];
      });
    }
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _uploadImage(String uid) async {
    if (_imageFile == null) return;
    final ref = _storage.ref().child('profile photo/$uid.jpg');
    await ref.putFile(_imageFile!);
    _downloadUrl = await ref.getDownloadURL();
  }

  Future<void> _getCurrentLocation() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
    if (placemarks.isNotEmpty) {
      final p = placemarks.first;
      setState(() {
        _addressController.text = '${p.street}, ${p.locality}, ${p.postalCode} ${p.administrativeArea}';
      });
    }
  }

  Future<void> _selectYear() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year),
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() => _establishedYear = DateFormat('yyyy').format(picked));
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    final uid = _auth.currentUser!.uid;
    await _uploadImage(uid);
    final Map<String, Object?> updateData = {
      'phoneNumber': _phoneController.text,
      'profileImageUrl': _downloadUrl,
    };
    if (_role == 'Homeowner') {
      updateData['address'] = _addressController.text;
    } else if (_role == 'Handyman') {
      updateData['category'] = _selectedCategory;
      updateData['areaOfService'] = _selectedState;
      updateData['establishedSince'] = _establishedYear;
      updateData['availability'] = _isAvailable ?? false;
      updateData['description'] = _descriptionController.text;
    }
    await _db.child('users/$uid').update(updateData);
    setState(() => _isSaving = false);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHandyman = _role == 'Handyman';

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: _role.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundImage: _imageFile != null
                              ? FileImage(_imageFile!)
                              : (_downloadUrl != null ? NetworkImage(_downloadUrl!) 
                              : const AssetImage('assets/images/default_profile.png'))
                                  as ImageProvider?,
                          backgroundColor: Colors.white,
                        ),
                        IconButton(
                          icon: const Icon(Icons.camera_alt),
                          onPressed: _isSaving ? null : _pickImage,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildField('Name', _name, enabled: false),
                    _buildField('Email', _email, enabled: false),
                    _buildTextField('Phone Number', _phoneController),
                    if (!isHandyman)
                      _buildLocationField('Address', _addressController, _getCurrentLocation),
                    if (isHandyman) ...[
                      _buildDropdown('Category', _categories, _selectedCategory, (v) => setState(() => _selectedCategory = v)),
                      _buildDropdown('Area of Service', _states, _selectedState, (v) => setState(() => _selectedState = v)),
                      _buildButtonField('Established Since', _establishedYear, _selectYear),
                      _buildDropdown(
  'Availability',
  ['Available', 'Not Available'],
  _isAvailable == true ? 'Available' : 'Not Available',
  (v) => setState(() => _isAvailable = v == 'Available'),
),

                      _buildTextField('Description', _descriptionController, maxLines: 3),
                    ],
                    const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveChanges,
                  child: Text(
                    _isSaving ? 'Saving...' : 'Save Changes',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
                  ],
                ),
              ),
          ),
    );
  }

  Widget _buildField(String label, String value, {bool enabled = true}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: value,
            enabled: enabled && !_isSaving,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
        ],
      );

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            enabled: !_isSaving,
            maxLines: maxLines,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
        ],
      );

  Widget _buildDropdown(String label, List<String> options, String? selectedValue, ValueChanged<String?> onChanged) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: selectedValue,
            onChanged: _isSaving ? null : onChanged,
            items: options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
        ],
      );

  Widget _buildLocationField(String label, TextEditingController controller, VoidCallback onTapIcon) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            enabled: !_isSaving,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.my_location),
                onPressed: _isSaving ? null : onTapIcon,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      );

  Widget _buildButtonField(String label, String? value, VoidCallback onTap) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _isSaving ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(value ?? 'Select Year'),
                  const Icon(Icons.calendar_today),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
}