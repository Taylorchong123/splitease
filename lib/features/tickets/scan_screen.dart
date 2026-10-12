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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a bill')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _busy
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B6EF3).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Reading your bill with AI OCR…',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Extracting dishes, prices, quantities, and tax.',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Card
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00C897).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.document_scanner, size: 48, color: Color(0xFF00C897)),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Snap or Upload Receipt',
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Take a clear, well-lit photo of your receipt. SplitEase AI will read items, quantities, and prices automatically.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF64748B), height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Camera Option
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1B6EF3),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => _scan(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Use Camera'),
                      ),
                      const SizedBox(height: 12),

                      // Gallery Option
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => _scan(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose from Gallery'),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
