import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/hazard_provider.dart';
import '../utils/theme.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _msgController = TextEditingController();
  
  String _selectedType = 'Traffic Jam';
  String _selectedLocation = 'Shahrah-e-Faisal Nursery';
  
  // Coordinate map for default locations in Karachi
  final Map<String, List<double>> _karachiLocations = {
    'Shahrah-e-Faisal Nursery': [24.8698, 67.0658],
    'Clifton Teen Talwar': [24.8138, 67.0281],
    'NED University Road': [24.9312, 67.1147],
    'Saddar Empress Market': [24.8624, 67.0298],
    'Tariq Road Market': [24.8719, 67.0583],
    'NIPA Chowrangi': [24.9175, 67.0972],
  };

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  void _broadcastAlert() {
    if (!_formKey.currentState!.validate()) return;

    final coords = _karachiLocations[_selectedLocation]!;
    final hazardProv = Provider.of<HazardProvider>(context, listen: false);

    hazardProv.addHazard(
      type: _selectedType,
      latitude: coords[0],
      longitude: coords[1],
      message: _msgController.text.trim(),
      reportedBy: 'Official System Admin',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Official Alert broadcasted at $_selectedLocation!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );

    _msgController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final authProv = Provider.of<AuthProvider>(context);
    final users = authProv.allUsers;
    
    // Calculate stats
    final totalUsers = users.length;
    final activeLogins = users.where((u) => u.isLoggedIn).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Control Panel', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.primaryGradient,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. STATS CARDS CARD
            const Text(
              'Application Metrics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.people_alt_outlined, color: AppTheme.primaryBlue),
                        const SizedBox(height: 12),
                        const Text('Registered Users', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('$totalUsers Users', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.security, color: Colors.green),
                        const SizedBox(height: 12),
                        const Text('Active Sessions', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('$activeLogins Logged In', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // 2. BROADCAST FORM CARD
            const Text(
              'Broadcast Road Alert',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppTheme.softShadow,
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _selectedType,
                      decoration: const InputDecoration(labelText: 'Alert Category'),
                      items: <String>['Traffic Jam', 'Road Condition', 'Accident', 'Rain', 'Pothole']
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedType = newValue;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedLocation,
                      decoration: const InputDecoration(labelText: 'Karachi Location Area'),
                      items: _karachiLocations.keys.map<DropdownMenuItem<String>>((String key) {
                        return DropdownMenuItem<String>(
                          value: key,
                          child: Text(key),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedLocation = newValue;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _msgController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.black),
                      decoration: const InputDecoration(
                        labelText: 'Detailed message',
                        hintText: 'e.g., Blockage near Nursery, commuters are advised to take alternative routes...',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please write the alert details';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: AppTheme.primaryGradient,
                        boxShadow: AppTheme.intenseShadow,
                      ),
                      child: ElevatedButton(
                        onPressed: _broadcastAlert,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                        ),
                        child: const Text('Broadcast Alert Now'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // 3. USER MANAGEMENT SUMMARY CARD
            const Text(
              'User Directories & Credentials',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppTheme.softShadow,
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: users.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final user = users[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: user.isAdmin ? Colors.orange.shade50 : Colors.blue.shade50,
                      child: Icon(
                        user.isAdmin ? Icons.admin_panel_settings : Icons.person,
                        color: user.isAdmin ? Colors.orange : AppTheme.primaryBlue,
                      ),
                    ),
                    title: Text(
                      user.fullName,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    subtitle: Text(
                      user.emailOrPhone,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: user.isLoggedIn ? Colors.green.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        user.isLoggedIn ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: user.isLoggedIn ? Colors.green : Colors.grey,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
