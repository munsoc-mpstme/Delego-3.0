import 'package:delego/widgets/mun_logo.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:delego/constants/backend.dart';
import 'package:delego/Pages/Login_Page/verify_email_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();

  Future<void> signUserUp() async {
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final email = usernameController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();
    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();

    if (email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty ||
        firstName.isEmpty ||
        lastName.isEmpty) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all fields.")),
      );
      return;
    }

    if (password != confirmPassword) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Passwords do not match.")),
      );
      return;
    }

    if (password.length < 8) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Password must be at least 8 characters long.")),
      );
      return;
    }

    final body = {
      'firstname': firstName,
      'lastname': lastName,
      'email': email,
      'password': password,
    };

    try {
      final response = await http.post(
        Uri.parse('${Backend.baseUrl}/mumbaimun/register'),
        body: jsonEncode(body),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );

      final responseData = json.decode(response.body);
      Navigator.of(context).pop();

      if (response.statusCode == 201) {
        // The account exists but cannot log in until the emailed code is entered.
        // (A server that does not report `verified` has already verified them.)
        final unverified = responseData['verified'] == false;
        if (!unverified) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Registration successful. You can log in now."),
              backgroundColor: scheme.primary,
            ),
          );
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        final verified = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => VerifyEmailPage(
              email: email,
              emailSent: responseData['email_sent'] != false,
            ),
          ),
        );
        if (!mounted) return;
        if (verified == true) {
          Navigator.pop(context); // back to the login page
          messenger.showSnackBar(const SnackBar(
            content: Text('Email verified. Log in with your password.'),
          ));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(responseData['detail'].toString()),
            backgroundColor: scheme.error,
          ),
        );
      }
    } catch (_) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("An error occurred. Please check your internet connection."),
          backgroundColor: scheme.error,
        ),
      );
    }
  }

  Widget buildTextField(TextEditingController controller, String hint, bool obscure) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: scheme.onSurface),
      cursorColor: scheme.primary,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MunLogoLink(
                  child: SizedBox(
                    height: 160,
                    width: 160,
                    child: Image.asset("assets/images/logo_solid.webp"),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'DELEGO',
                  style: textTheme.headlineMedium?.copyWith(
                    color: scheme.tertiary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 24),

                buildTextField(firstNameController, 'First Name', false),
                const SizedBox(height: 12),
                buildTextField(lastNameController, 'Last Name', false),
                const SizedBox(height: 12),
                buildTextField(usernameController, 'Email ID', false),
                const SizedBox(height: 12),
                buildTextField(passwordController, 'Password', true),
                const SizedBox(height: 12),
                buildTextField(confirmPasswordController, 'Confirm Password', true),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: signUserUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 3,
                  ),
                  child: Text(
                    'Sign Up',
                    style: textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already a member?',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Login',
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.tertiary,
                          fontWeight: FontWeight.w600,
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
