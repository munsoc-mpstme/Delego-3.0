import 'package:flutter/material.dart';

import 'package:delego/Pages/Study Guides/PDF_viewers/IPC_pdfviewer.dart';
import 'package:delego/Pages/Study Guides/PDF_viewers/UNODC_pdfviewer.dart';
import 'package:delego/Pages/Study Guides/PDF_viewers/UNSC_pdfviewer.dart';
import 'package:delego/widgets/neon.dart';

class _Guide {
  const _Guide(this.title, this.cover, [this.page]);
  final String title;
  final String cover;

  /// Null until the study guide PDF for this committee has been added.
  final Widget Function()? page;
}

class StudyGuidespage extends StatelessWidget {
  StudyGuidespage({super.key});

  static const _dir = 'assets/images/committees';

  final List<_Guide> _guides = [
    _Guide('UNSC', '$_dir/unsc.webp', () => UnscPdfviewer()),
    _Guide('CCC', '$_dir/ccc.webp'),
    _Guide('PSC', '$_dir/psc.webp'),
    _Guide('WTO', '$_dir/wto.webp'),
    _Guide('UNODC', '$_dir/unodc.webp', () => UnodcPdfviewer()),
    _Guide('UNICEF', '$_dir/unicef.webp'),
    _Guide('ECOSOC', '$_dir/ecosoc.webp'),
    _Guide('IPC', '$_dir/ipc.webp', () => IpcPdfviewer()),
  ];

  void _open(BuildContext context, _Guide g) {
    final page = g.page;
    if (page == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text('${g.title} study guide is coming soon.')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        centerTitle: false,
        title: const Text('STUDY GUIDES'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _guides.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, i) {
              final g = _guides[i];
              return FolderCard(
                title: g.title,
                cover: g.cover,
                tag: g.page == null ? 'SOON' : 'PDF',
                onTap: () => _open(context, g),
              );
            },
          ),
        ],
      ),
    );
  }
}
