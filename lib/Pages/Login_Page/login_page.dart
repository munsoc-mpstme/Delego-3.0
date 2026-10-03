import 'package:delego/Pages/Profile_Page/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delego/Pages/Login_Page/register_page.dart';
import 'package:delego/Pages/Home_Page/home_page.dart';
import 'package:delego/constants/backend.dart';
import 'package:delego/Pages/Login_Page/forgot_password.dart';
import 'package:delego/Theme/theme_controller.dart';
import 'package:delego/auth/capabilities.dart';
import 'package:provider/provider.dart';


class LoginPage extends StatefulWidget {
  final ThemeController controller;
  const LoginPage({super.key, required this.controller});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();


  Future<void> setLoggedInBefore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lib', true);
  }

  Future<bool?> getLoggedInBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('lib');
  }

  Future<void> clearPref() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  void signUserIn() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final scheme = Theme.of(context).colorScheme;

    final email = usernameController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in both fields.")),
      );
      return;
    }

    final body = {'username': email, 'password': password};

    try {
      final response = await http.post(
        Uri.parse(Backend.baseUrl + '/login'),
        body: body,
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        encoding: Encoding.getByName('utf-8'),
      );
      // print('statusCode:${response.statusCode}');
      // print('statusBody:${response.body}');
      // print('Response headers: ${response.headers}');

      final responseData = json.decode(response.body);
      if (response.statusCode == 200) {
        final String token = responseData['access_token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);

        final response2 = await http.get(
          Uri.parse(Backend.baseUrl + '/delegates/me'),
          headers: {'Authorization': 'Bearer $token'},
        );
        final data = json.decode(response2.body);

        print("data=$data"); //printing the data returned from the backend

        if (data['detail'] == 'Please verify your email!') {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['detail']),
            backgroundColor: Theme.of(context).colorScheme.error,
          ));
          return;
        }

        final id = data['id'] ?? '';
        await prefs.setString('id', id);
        await prefs.setString('firstname', data['firstname'] ?? '');
        await prefs.setString('lastname', data['lastname'] ?? '');
        await prefs.setString('email', data['email'] ?? '');
        await prefs.setString('contact', data['contact'] ?? '');
        await prefs.setString('dateofbirth', data['dateofbirth'] ?? '');
        await prefs.setString('gender', data['gender'] ?? '');
        await prefs.setString('role', data['role'] ?? '');

        // Permissions come from the server; load them before the home screen decides
        // what to show (the sign-in token is already saved, so the call is authorised).
        await context.read<Capabilities>().refresh();
        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(controller: widget.controller),
          ),
        );

        if (await getLoggedInBefore() != true) {
          setLoggedInBefore();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Update Info'),
              backgroundColor: Theme.of(context).colorScheme.surface,
              action: SnackBarAction(
                label: "Profile",
                textColor: Theme.of(context).colorScheme.primary,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ProfilePage(controller: widget.controller),
                    ),
                  );
                },
              ),
            ),
          );
        }
      } else {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(responseData['detail'].toString()),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      Navigator.of(context).pop();

      print('Error: $e');
      print('Error Type: ${e.runtimeType}');

      String errorMessage = "An error occurred";

      try {
        // Try to parse error from response
        if (e.toString().contains('Bad state') ||
            e.toString().contains('SocketException')) {
          errorMessage = "Cannot connect to server";
        } else {
          // Extract error message from exception string
          final errorString = e.toString();

          // If it contains JSON-like content, try to parse it
          if (errorString.contains('{')) {
            final jsonMatch = RegExp(r'\{.*\}').firstMatch(errorString);
            if (jsonMatch != null) {
              final jsonStr = jsonMatch.group(0);
              final jsonResponse = jsonDecode(jsonStr!);
              errorMessage = jsonResponse['detail'] ??
                  jsonResponse['error'] ??
                  jsonResponse['message'] ??
                  errorString;
            } else {
              errorMessage = errorString;
            }
          } else {
            errorMessage = errorString;
          }
        }
      } catch (parseError) {
        print('Could not parse error: $parseError');
        errorMessage = e.toString();
      }

      print('Extracted Error: $errorMessage');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    InputDecoration themedInputDecoration(String hint) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
      );
    }

    Widget loginButton() {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
          ),
          onPressed: signUserIn,
          child: Text(
            'Login',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onPrimary,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: scheme.surface,
        elevation: 0,
        foregroundColor: scheme.onSurface,
      ),
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: Column(
              children: [
                // logo
                Container(
                  height: 160,
                  width: 160,
                  child: Image.asset("assets/images/logo_dotted.webp"),
                ),
                const SizedBox(height: 8),
                // title
                Text(
                  'DELEGO',
                  style: textTheme.headlineMedium?.copyWith(
                    color: scheme.tertiary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 30),

                // username
                TextField(
                  controller: usernameController,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: scheme.onSurface),
                  cursorColor: scheme.primary,
                  decoration: themedInputDecoration("Email ID"),
                ),
                const SizedBox(height: 16),

                // password
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: TextStyle(color: scheme.onSurface),
                  cursorColor: scheme.primary,
                  decoration: themedInputDecoration("Password"),
                ),
                const SizedBox(height: 10),

                // forgot password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ForgotPassword(),
                        ),
                      );
                    },
                    child: Text(
                      'Forgot Password?',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.tertiary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 25),

                // login button
                loginButton(),
                const SizedBox(height: 40),

                // sign up redirect
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Not a member?',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurface),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => RegisterPage()),
                        );
                      },
                      child: Text(
                        'Sign Up',
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.tertiary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
