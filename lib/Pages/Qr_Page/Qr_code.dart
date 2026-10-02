import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:delego/Theme/theme_controller.dart';


class QrCode extends StatefulWidget {
  const QrCode({super.key});

  @override
  State<QrCode> createState() => _QrCodeState();
}

class _QrCodeState extends State<QrCode> {
  Uint8List? _qrCodeImage;

  @override
  void initState() {
    super.initState();
    _loadQrCodeImage();
  }

  Future<void> _loadQrCodeImage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? base64Image = prefs.getString('qr');
    if (base64Image != null) {
      setState(() {
        _qrCodeImage = base64Decode(base64Image);
      });
    } else {
      print("No QR code image found in SharedPreferences.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0.0,
        backgroundColor: scheme.primary,
        iconTheme: IconThemeData(
          color: scheme.onPrimary,
        ),
        title: Text(
          'Food QR Code',
          style: textTheme.titleLarge?.copyWith(
            color: scheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Transform.translate(
          offset: const Offset(0, -20),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: _qrCodeImage != null
                ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Show this QR outside the food counter",
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 20),
                Image.memory(
                  _qrCodeImage!,
                  width: 200,
                  height: 200,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 20),
                Text(
                  "Bon appétit! Enjoy your meal 🍽️",
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            )
                : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.qr_code_rounded,
                  size: 100,
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 20),
                Text(
                  "No QR Code available.",
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Error! No QR code available, contact the Organizing Committee",
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
