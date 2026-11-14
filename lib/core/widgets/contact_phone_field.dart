import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';

/// Data from one user-selected entry, never from a full contacts scan.
class SelectedPhoneContact {
  const SelectedPhoneContact({required this.phone, this.name = ''});
  final String phone;
  final String name;
}

typedef PhoneContactSelector = Future<SelectedPhoneContact?> Function();

/// The native Android contact picker grants access only to the user's selection.
/// It does not need READ_CONTACTS, WRITE_CONTACTS, or a broad address-book scan.
Future<SelectedPhoneContact?> pickAndroidPhoneContact() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    throw UnsupportedError('اختيار جهات الاتصال متاح في تطبيق أندرويد فقط.');
  }
  final contact = await FlutterNativeContactPicker().selectPhoneNumber();
  if (contact == null) return null; // The user cancelled.
  final numbers = contact.phoneNumbers;
  final selected = contact.selectedPhoneNumber ??
      (numbers != null && numbers.isNotEmpty ? numbers.first : null);
  if (selected == null || selected.trim().isEmpty) {
    throw StateError('جهة الاتصال المحددة لا تحتوي على رقم هاتف.');
  }
  return SelectedPhoneContact(
    name: contact.fullName?.trim() ?? '',
    phone: selected.trim(),
  );
}

/// Uses the application's existing TextField and InputDecoration styling.
class ContactPhoneField extends StatefulWidget {
  const ContactPhoneField({
    super.key,
    required this.nameController,
    required this.phoneController,
    this.selector,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final PhoneContactSelector? selector;

  @override
  State<ContactPhoneField> createState() => _ContactPhoneFieldState();
}

class _ContactPhoneFieldState extends State<ContactPhoneField> {
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final selected = await (widget.selector ?? pickAndroidPhoneContact)();
      if (!mounted || selected == null) return; // Cancel is not an error.
      final chosenPhone = selected.phone.trim();
      if (chosenPhone.isEmpty) {
        throw StateError('جهة الاتصال المحددة لا تحتوي على رقم هاتف.');
      }
      widget.phoneController.text = chosenPhone;
      if (widget.nameController.text.trim().isEmpty &&
          selected.name.trim().isNotEmpty) {
        widget.nameController.text = selected.name.trim();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر اختيار رقم الهاتف من جهات الاتصال. يمكنك إدخاله يدوياً.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = widget.selector != null ||
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    return TextField(
      key: const ValueKey('party-contact-phone'),
      controller: widget.phoneController,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        labelText: 'الهاتف',
        suffixIcon: supported
            ? IconButton(
                key: const ValueKey('pick-party-contact'),
                tooltip: 'اختيار رقم من جهات الاتصال',
                onPressed: _picking ? null : _pick,
                icon: const Icon(Icons.contacts_outlined),
              )
            : null,
      ),
    );
  }
}
