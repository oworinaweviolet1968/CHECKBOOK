import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/database_helper.dart';
import '../services/supabase_service.dart';
import '../utils/colors.dart';

class ReceiptSettingsSheet extends StatefulWidget {
  const ReceiptSettingsSheet({super.key});

  static Future<void> show(BuildContext context) async {
    final name = await DatabaseHelper.instance.getSetting("receipt_shop_name") ?? "";
    final number = await DatabaseHelper.instance.getSetting("receipt_shop_number") ?? "";
    final location = await DatabaseHelper.instance.getSetting("receipt_location") ?? "";
    final phone = await DatabaseHelper.instance.getSetting("receipt_phone") ?? "";
    final phone2 = await DatabaseHelper.instance.getSetting("receipt_phone2") ?? "";

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _ReceiptSettingsSheetContent(
          initialName: name,
          initialNumber: number,
          initialLocation: location,
          initialPhone: phone,
          initialPhone2: phone2,
        ),
      ),
    );
  }

  @override
  State<ReceiptSettingsSheet> createState() => _ReceiptSettingsSheetState();
}

class _ReceiptSettingsSheetState extends State<ReceiptSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _ReceiptSettingsSheetContent extends StatefulWidget {
  final String initialName;
  final String initialNumber;
  final String initialLocation;
  final String initialPhone;
  final String initialPhone2;

  const _ReceiptSettingsSheetContent({
    required this.initialName,
    required this.initialNumber,
    required this.initialLocation,
    required this.initialPhone,
    required this.initialPhone2,
  });

  @override
  State<_ReceiptSettingsSheetContent> createState() => _ReceiptSettingsSheetContentState();
}

class _ReceiptSettingsSheetContentState extends State<_ReceiptSettingsSheetContent> {
  late TextEditingController _nameController;
  late TextEditingController _numberController;
  late TextEditingController _locationController;
  late TextEditingController _phoneController;
  late TextEditingController _phone2Controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _numberController = TextEditingController(text: widget.initialNumber);
    _locationController = TextEditingController(text: widget.initialLocation);
    _phoneController = TextEditingController(text: widget.initialPhone);
    _phone2Controller = TextEditingController(text: widget.initialPhone2);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    _phone2Controller.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      await DatabaseHelper.instance.saveSetting("receipt_shop_name", _nameController.text.trim());
      await DatabaseHelper.instance.saveSetting("receipt_shop_number", _numberController.text.trim());
      await DatabaseHelper.instance.saveSetting("receipt_location", _locationController.text.trim());
      await DatabaseHelper.instance.saveSetting("receipt_phone", _phoneController.text.trim());
      await DatabaseHelper.instance.saveSetting("receipt_phone2", _phone2Controller.text.trim());

      SupasService.instance.uploadReceiptSettings();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Receipt settings saved successfully', style: GoogleFonts.outfit()),
            backgroundColor: AppColors.primaryGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: ${e.toString()}', style: GoogleFonts.outfit()),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.0)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header Icon Badge & Title
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: AppColors.lightCyan,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.primaryGreen,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receipt Information',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Info displayed at the header of your printed receipts.',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.normal,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Shop Name Field
            _buildInputField(
              controller: _nameController,
              label: 'Shop Name',
              hint: 'e.g. Meto Electronics',
              icon: Icons.store_rounded,
              maxLength: 40,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 .&()\-\/,]')),
              ],
            ),
            const SizedBox(height: 16),

            // Shop Number Field
            _buildInputField(
              controller: _numberController,
              label: 'Shop Number',
              hint: 'e.g. Shop G15',
              icon: Icons.numbers_rounded,
              maxLength: 20,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 .#\-\/,]')),
              ],
            ),
            const SizedBox(height: 16),

            // Location Field
            _buildInputField(
              controller: _locationController,
              label: 'Location',
              hint: 'e.g. Kampala, Uganda',
              icon: Icons.location_on_rounded,
              maxLength: 40,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 .&()\-\/,]')),
              ],
            ),
            const SizedBox(height: 16),

            // Phone 1 Field
            _buildInputField(
              controller: _phoneController,
              label: 'Phone 1',
              hint: 'e.g. +256 701 234567',
              icon: Icons.phone_rounded,
              keyboardType: TextInputType.phone,
              maxLength: 25,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-\/(),]')),
              ],
            ),
            const SizedBox(height: 16),

            // Phone 2 Field
            _buildInputField(
              controller: _phone2Controller,
              label: 'Phone 2',
              hint: 'e.g. +256 780 654321',
              icon: Icons.phone_rounded,
              keyboardType: TextInputType.phone,
              maxLength: 25,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-\/(),]')),
              ],
            ),
            const SizedBox(height: 28),

            // Full-Width Elevated Save Button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shadowColor: const Color(0x3300D09C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        'Save Receipt Settings',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            counterText: "",
            hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 14),
            prefixIcon: Icon(icon, color: AppColors.primaryGreen, size: 20),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.0),
              borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2.0),
            ),
          ),
        ),
      ],
    );
  }
}
