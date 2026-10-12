import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/bill_parser.dart';
import '../../services/ocr_service.dart';
import 'create_ticket_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _ocr = OcrService();
  bool _busy = false;
  String? _error;

  Future<void> _scan(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await _ocr.readText(picked.path);
      final parsed = BillParser.parse(text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => CreateTicketScreen(initial: parsed, source: 'scan', rawText: text),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read the bill: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a bill')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _busy
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Reading your bill…'),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Take a clear, well-lit photo of the bill. '
                      'You can review and correct everything afterwards.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _scan(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Use camera'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _scan(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose from gallery'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
