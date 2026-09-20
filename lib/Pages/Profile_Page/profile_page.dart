import 'package:delego/Pages/Login_Page/login_page.dart';
import 'package:flutter/material.dart';
import 'package:delego/constants/backend.dart';
import 'package:delego/Pages/Profile_Page/text_box.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delego/Theme/theme_controller.dart';

class ProfilePage extends StatefulWidget {
  final ThemeController controller;
  const ProfilePage({super.key, required this.controller});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? id, firstname, lastname, email, contact, dateofbirth, gender;

  Future<void> loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      id = prefs.getString('id');
      firstname = prefs.getString('firstname');
      lastname = prefs.getString('lastname');
      email = prefs.getString('email');
      contact = prefs.getString('contact');
      dateofbirth = prefs.getString('dateofbirth');
      gender = prefs.getString('gender');
      if (contact == '') contact = '-';
      if (gender == '') gender = 'Prefer not to say';
      if (dateofbirth == '') dateofbirth = 'dd-mm-yyyy';
    });
  }

  Future<void> updateUserData(String field, String newValue) async {
    switch (field) {
      case 'First Name':
        field = 'firstname'; break;
      case 'Last Name':
        field = 'lastname'; break;
      case 'Contact Number':
        field = 'contact'; break;
      case 'Date of Birth':
        field = 'dateofbirth'; break;
      case 'Gender':
        field = 'gender'; break;
    }
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(field, newValue);
    final token = prefs.getString('token');
    try {
      final response = await http.patch(
        Uri.parse('${Backend.baseUrl}/delegates/$id?$field=$newValue'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: [],
      );
      final responseData = json.decode(response.body);
      if (response.statusCode == 200) {
        switch (field) {
          case 'firstname': field = 'First Name'; break;
          case 'lastname': field = 'Last Name'; break;
          case 'contact': field = 'Contact Number'; break;
          case 'dateofbirth': field = 'Date of Birth'; break;
          case 'gender': field = 'Gender'; break;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$field updated successfully!"), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(responseData.toString(), style: TextStyle(color: Colors.red))),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error updating $field."), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    bool confirmDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Account"),
        content: const Text("Are you sure you want to delete your account? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;
    if (confirmDelete) {
      try {
        final response = await http.delete(
          Uri.parse('${Backend.baseUrl}/account'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (response.statusCode == 200) {
          await prefs.clear();
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => LoginPage(controller: widget.controller)),
                  (Route<dynamic> route) => false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Account deleted successfully."), backgroundColor: Colors.green),
          );
        } else {
          final responseData = json.decode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to delete account: ${responseData['detail']}"), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error deleting account."), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> editField(String field, String currentValue) async {
    String newValue = currentValue;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.surface,
        title: Text("Edit $field", style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
        content: TextField(
          autofocus: true,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
          decoration: InputDecoration(
            hintText: field == 'Date of Birth' ? "dd-mm-yyyy" : "Enter new $field",
            hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface.withValues(alpha: 0.5)),
          ),
          onChanged: (value) => newValue = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: textTheme.bodyMedium?.copyWith(color: scheme.primary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              if (field == 'Date of Birth') {
                final datePattern = RegExp(r"^(0[1-9]|[12][0-9]|3[01])-(0[1-9]|1[0-2])-(\d{4})$");
                if (!datePattern.hasMatch(newValue)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Invalid date format. Use dd-mm-yyyy."), backgroundColor: Colors.red),
                  );
                  return;
                }
                final dateParts = newValue.split('-');
                final day = int.parse(dateParts[0]);
                final month = int.parse(dateParts[1]);
                final year = int.parse(dateParts[2]);
                if (day > 31 || month > 12 || year < 1900 || year > DateTime.now().year) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Invalid date entered."), backgroundColor: Colors.red),
                  );
                  return;
                }
              }
              if (field == 'Contact Number') {
                final contactPattern = RegExp(r"^\+?\d{1,4}[\s\-]?\(?\d{1,4}\)?[\s\-]?\d{1,4}[\s\-]?\d{4,}$");
                if (!contactPattern.hasMatch(newValue)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Invalid contact number"), backgroundColor: Colors.red),
                  );
                  return;
                }
              }
              if (newValue.isNotEmpty && newValue != currentValue) {
                await updateUserData(field, newValue);
                loadUserData();
              }
            },
            child: Text('Save', style: textTheme.bodyMedium?.copyWith(color: scheme.primary)),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: scheme.onPrimary),
        backgroundColor: scheme.primary,
        centerTitle: true,
        title: Text('Settings', style: textTheme.titleLarge?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          Icon(Icons.person, size: 72, color: scheme.primary),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: Text(
              'My Profile',
              style: textTheme.titleMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          MyTextBox(
            text: firstname ?? 'First Name',
            sectionName: 'First Name',
            onPressed: () => editField('First Name', firstname ?? ''),
          ),
          MyTextBox(
            text: lastname ?? 'Last Name',
            sectionName: 'Last Name',
            onPressed: () => editField('Last Name', lastname ?? ''),
          ),
          MyTextBox(
            text: email ?? 'Email',
            sectionName: 'Email',
            onPressed: () => editField('Email', email ?? ''),
          ),
          MyTextBox(
            text: contact ?? 'Contact Number',
            sectionName: 'Contact Number',
            onPressed: () => editField('Contact Number', contact ?? ''),
          ),
          MyTextBox(
            text: dateofbirth ?? 'Date of Birth',
            sectionName: 'Date of Birth',
            onPressed: () => editField('Date of Birth', dateofbirth ?? ''),
          ),
          // MyTextBox(
          //   text: gender ?? 'Gender',
          //   sectionName: 'Gender',
          //   onPressed: () => editField('Gender', gender ?? ''),
          // ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'App Theme',
              style: textTheme.titleMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.system,
            groupValue: widget.controller.mode,
            onChanged: (mode) {
              if (mode != null) setState(() => widget.controller.setThemeMode(mode));
            },
            title: Text('System Default', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
            activeColor: scheme.primary,
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.light,
            groupValue: widget.controller.mode,
            onChanged: (mode) {
              if (mode != null) setState(() => widget.controller.setThemeMode(mode));
            },
            title: Text('Light', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
            activeColor: scheme.primary,
          ),
          RadioListTile<ThemeMode>(
            value: ThemeMode.dark,
            groupValue: widget.controller.mode,
            onChanged: (mode) {
              if (mode != null) setState(() => widget.controller.setThemeMode(mode));
            },
            title: Text('Dark', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
            activeColor: scheme.primary,
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.error,
              ),
              onPressed: deleteAccount,
              child: Text(
                "Delete Account",
                style: textTheme.bodyMedium?.copyWith(color: scheme.onError),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
