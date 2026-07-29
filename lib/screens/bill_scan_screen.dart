import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../models/bill_item_model.dart';
import '../services/gemini_service.dart';
import '../utils/app_theme.dart';
import '../utils/money.dart';
import 'add_expense_screen.dart';
import 'add_personal_expense_screen.dart';

enum ScanState { idle, processing, done, error }

class BillScanScreen extends StatefulWidget {
  /// Null when scanning a bill for a personal transaction.
  final GroupModel? group;
  final List<UserModel> members;

  const BillScanScreen({super.key, this.group, this.members = const []});

  @override
  State<BillScanScreen> createState() => _BillScanScreenState();
}

class _BillScanScreenState extends State<BillScanScreen> {
  final _picker = ImagePicker();
  final _textRecognizer = TextRecognizer();

  ScanState _state = ScanState.idle;
  File? _image;
  List<BillItem> _items = [];
  String _statusMessage = '';

  static const List<String> _categories = [
    'General', 'Groceries', 'Food & Drink', 'Electronics',
    'Clothing', 'Transport', 'Health', 'Entertainment', 'Utilities',
  ];

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2000,
      );

      if (picked == null) return;

      setState(() {
        _image = File(picked.path);
        _state = ScanState.processing;
        _items = [];
      });
      await _processBill();
    } catch (e, st) {
      debugPrint('[BillScan] Image pick error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not load the image. Please try again.')));
      }
    }
  }

  Future<void> _processBill() async {
    // OCR
    setState(() => _statusMessage = 'Reading text from image...');

    try {
      final inputImage = InputImage.fromFile(_image!);
      final recognized = await _textRecognizer.processImage(inputImage);
      final rawText = recognized.text;

      if (rawText.trim().isEmpty) {
        setState(() {
          _state = ScanState.error;
          _statusMessage =
          'No text detected in the image. Try a clearer photo with better lighting.';
        });
        return;
      }

      // Gemini
      setState(() => _statusMessage = 'Extracting items...');

      final parsedItems = await GeminiService.parseBillText(rawText);

      if (parsedItems.isEmpty) {
        setState(() {
          _state = ScanState.error;
          _statusMessage =
          'No items could be found. Try adding items manually, or scan a clearer image.';
        });
        return;
      }

      setState(() {
        _items = parsedItems;
        _state = ScanState.done;
      });
    } catch (e, st) {
      debugPrint('[BillScan] Error during processing: $e\n$st');
      setState(() {
        _state = ScanState.error;
        _statusMessage = _friendlyError(e.toString());
      });
    }
  }

  String _friendlyError(String code) {
    if (code.contains('auth_error') || code.contains('403')) {
      return 'AI service authentication failed. Check your API key.';
    }
    if (code.contains('model_not_found') || code.contains('404')) {
      return 'AI service is temporarily unavailable. Please try again.';
    }
    if (code.contains('quota_exceeded') || code.contains('429')) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    if (code.contains('network_error') || code.contains('SocketException')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (code.contains('no_text')) {
      return 'No text detected. Try a clearer photo with better lighting.';
    }
    if (code.contains('parse_error') || code.contains('empty_response')) {
      return 'AI returned an unexpected response. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  void _editItem(int index) {
    final item = _items[index];
    final nameCtrl = TextEditingController(text: item.name);
    final priceCtrl =
    TextEditingController(text: item.price.toStringAsFixed(2));
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    String selectedCat = _categories.contains(item.category)
        ? item.category
        : 'General';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Edit Item',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Item Name'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: priceCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Price', prefixText: 'Rs '),
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      decoration: const InputDecoration(labelText: 'Qty'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedCat,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories
                    .map((c) =>
                    DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setModal(() => selectedCat = v!),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _items[index] = BillItem(
                        name: nameCtrl.text.trim().isEmpty
                            ? item.name
                            : nameCtrl.text.trim(),
                        price: double.tryParse(priceCtrl.text) ?? item.price,
                        category: selectedCat,
                        quantity:
                        int.tryParse(qtyCtrl.text) ?? item.quantity,
                      );
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addItem() {
    _items.add(BillItem(name: 'New Item', price: 0, category: 'General'));
    _editItem(_items.length - 1);
  }

  void _proceedToAddExpense() {
    final total =
    _items.fold<double>(0, (s, i) => s + i.price * i.quantity);
    final group = widget.group;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => group != null
            ? AddExpenseScreen(
                group: group,
                members: widget.members,
                prefillItems: _items,
                prefillTotal: total,
              )
            : AddPersonalExpenseScreen(
                prefillTotalCents: Money.fromMajor(total),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Bill'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case ScanState.idle:
        return _buildIdle();
      case ScanState.processing:
        return _buildLoading();
      case ScanState.done:
        return _buildResult();
      case ScanState.error:
        return _buildError();
    }
  }

  Widget _buildIdle() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Upload a photo of the receipt',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            // Dotted drop zone: tap to pick a file from gallery.
            GestureDetector(
              onTap: () => _pickImage(ImageSource.gallery),
              child: AspectRatio(
                aspectRatio: 1.5,
                child: CustomPaint(
                  painter: _DashedRRectPainter(
                      color: _image == null
                          ? AppTheme.divider
                          : AppTheme.primary),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _image != null
                        ? Image.file(_image!, fit: BoxFit.cover)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_outlined,
                                  size: 48, color: AppTheme.textSecondary),
                              const SizedBox(height: 10),
                              Text('Select file',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textSecondary)),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Divider(color: AppTheme.divider, height: 1),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Open camera and take photo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_image != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_image!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover),
              ),
              const SizedBox(height: 32),
            ],
            CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final total =
    _items.fold<double>(0, (s, i) => s + i.price * i.quantity);

    return Column(
      children: [
        // Header strip
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_image != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_image!,
                      width: 60, height: 60, fit: BoxFit.cover),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_items.length} items found',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      'Total: Rs ${total.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: _items.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              if (i == _items.length) {
                return OutlinedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Item Manually'),
                );
              }
              final item = _items[i];
              return _ItemCard(
                item: item,
                onEdit: () => _editItem(i),
                onDelete: () => setState(() => _items.removeAt(i)),
              );
            },
          ),
        ),

        // Bottom bar
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.divider)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _state = ScanState.idle;
                        _items = [];
                        _image = null;
                      }),
                      child: const Text('Rescan'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                      _items.isNotEmpty ? _proceedToAddExpense : null,
                      child: const Text('Use'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.error_outline,
                  color: AppTheme.errorColor, size: 36),
            ),
            const SizedBox(height: 20),
            Text('Scan Failed',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 10),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  height: 1.5),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _state = ScanState.idle;
                    _image = null;
                  }),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try Again'),
                ),
                ElevatedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Add Manually'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a rounded rectangle with a dashed stroke, used for the
/// receipt upload drop zone.
class _DashedRRectPainter extends CustomPainter {
  final Color color;

  _DashedRRectPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 16.0;
    const dashLength = 6.0;
    const gapLength = 5.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = math.min(dist + dashLength, metric.length);
        dashed.addPath(metric.extractPath(dist, next), Offset.zero);
        dist = next + gapLength;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ItemCard extends StatelessWidget {
  final BillItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ItemCard(
      {required this.item, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color:
            AppTheme.categoryColor(item.category).withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              '${item.quantity}x',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppTheme.categoryColor(item.category)),
            ),
          ),
        ),
        title: Text(item.name,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: CategoryBadge(category: item.category),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rs ${item.totalPrice.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 16),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ])),
                const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size: 16, color: AppTheme.errorColor),
                      SizedBox(width: 8),
                      Text('Delete',
                          style:
                          TextStyle(color: AppTheme.errorColor)),
                    ])),
              ],
              icon: Icon(Icons.more_vert,
                  size: 18, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}