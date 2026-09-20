import 'package:flutter/material.dart';

// Updated PDF viewers (from your new data)
import 'package:delego/Pages/Study Guides/PDF_viewers/G20_pdfviewer.dart';
import 'package:delego/Pages/Study Guides/PDF_viewers/IPC_pdfviewer.dart';
import 'package:delego/Pages/Study Guides/PDF_viewers/LokSabha_pdfviewer.dart';
import 'package:delego/Pages/Study Guides/PDF_viewers/UNCSW_pdfviewer.dart';
import 'package:delego/Pages/Study Guides/PDF_viewers/UNEA_pdfviewer.dart';
import 'package:delego/Pages/Study Guides/PDF_viewers/UNODC_pdfviewer.dart';
import 'package:delego/Pages/Study Guides/PDF_viewers/UNSC_pdfviewer.dart';

class StudyGuidespage extends StatefulWidget {
  @override
  State<StudyGuidespage> createState() => _StudyGuidesPageState();
}

class _StudyGuidesPageState extends State<StudyGuidespage> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.primary,
        iconTheme: IconThemeData(color: scheme.onPrimary),
        title: Text(
          'Study Guides',
          style: textTheme.titleLarge?.copyWith(
            color: scheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      backgroundColor: scheme.surface,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Study Guides",
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                  fontSize: 30.0,
                ),
              ),
              const SizedBox(height: 8.0),
              Text(
                "Click to view the PDF",
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 16.0,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 20.0),

              // Updated list items from your new data, themed buttons preserved
              _buildStudyGuideButton(
                context,
                scheme,
                textTheme,
                'G20',
                G20Pdfviewer(),
              ),
              _buildStudyGuideButton(
                context,
                scheme,
                textTheme,
                'Historical Lok Sabha',
                LoksabhaPdfviewer(),
              ),
              _buildStudyGuideButton(
                context,
                scheme,
                textTheme,
                'IPC',
                IpcPdfviewer(),
              ),
              _buildStudyGuideButton(
                context,
                scheme,
                textTheme,
                'UNCSW',
                UncswPdfviewer(),
              ),
              _buildStudyGuideButton(
                context,
                scheme,
                textTheme,
                'UNEA',
                UneaPdfviewer(),
              ),
              _buildStudyGuideButton(
                context,
                scheme,
                textTheme,
                'UNODC',
                UnodcPdfviewer(),
              ),
              _buildStudyGuideButton(
                context,
                scheme,
                textTheme,
                'UNSC',
                UnscPdfviewer(),
              ),
              // _buildStudyGuideButton(
              //   context,
              //   scheme,
              //   textTheme,
              //   'ICC',
              //   Icc_PdfViewer(),
              // ),
            ],
          ),
        ),
      ),
    );
  }

  // Themed button helper (no hard-coded colors)
  Widget _buildStudyGuideButton(
      BuildContext context,
      ColorScheme scheme,
      TextTheme textTheme,
      String title,
      Widget page,
      ) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => page),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.12),
              blurRadius: 8.0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left side: Title
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 22.0,
              ),
            ),
            // Right side: PDF icon
            Icon(
              Icons.picture_as_pdf,
              size: 40.0,
              color: scheme.onPrimary,
            ),
          ],
        ),
      ),
    );
  }
}
