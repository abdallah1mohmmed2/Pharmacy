// lib/core/widgets/manager_pin_dialog.dart
import 'package:flutter/material.dart';

class ManagerPinDialog {
  const ManagerPinDialog._();

  static Future<String?> show(BuildContext context,
      {String title = 'تأكيد صلاحية المدير'}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(title),
              content: TextField(
                  controller: controller,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                      labelText: title.contains('المالك')
                          ? 'رمز المالك'
                          : 'رمز المدير')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('إلغاء')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext, controller.text),
                    child: const Text('تأكيد')),
              ],
            ));
    controller.dispose();
    return result;
  }
}
