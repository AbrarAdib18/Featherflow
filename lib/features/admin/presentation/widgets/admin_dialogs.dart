import 'package:flutter/material.dart';

import '../admin_theme.dart';

Future<void> showAdminDetails(BuildContext context,
    {required String title,
    required IconData icon,
    required List<MapEntry<String, String>> fields}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: AColors.primary.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: AColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AColors.textPrimary)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close,
                      size: 18, color: AColors.textSecondary)),
            ]),
            const SizedBox(height: 10),
            ...fields.map((field) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(field.key,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AColors.grey)),
                      const SizedBox(height: 3),
                      Text(field.value,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AColors.textPrimary,
                              height: 1.35)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    ),
  );
}

Future<String?> showAdminTextPrompt(BuildContext context,
    {required String title,
    required String label,
    required String actionLabel,
    String initialValue = '',
    int maxLines = 4}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.viewInsetsOf(ctx).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AColors.textPrimary)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: maxLines,
            style: const TextStyle(fontSize: 13, color: AColors.textPrimary),
            decoration: InputDecoration(
                labelText: label,
                filled: true,
                fillColor: AColors.surface2,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(ctx, value);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              child: Text(actionLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

Future<Map<String, String>?> showAdminRecordEditor(
  BuildContext context, {
  required String title,
  required Map<String, String> fields,
}) async {
  final controllers = {
    for (final field in fields.entries)
      field.key: TextEditingController(text: field.value),
  };
  final result = await showModalBottomSheet<Map<String, String>>(
    context: context,
    backgroundColor: AColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.viewInsetsOf(ctx).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AColors.textPrimary)),
            const SizedBox(height: 14),
            for (final entry in controllers.entries) ...[
              TextField(
                controller: entry.value,
                style:
                    const TextStyle(fontSize: 13, color: AColors.textPrimary),
                decoration: InputDecoration(
                  labelText: entry.key,
                  filled: true,
                  fillColor: AColors.surface2,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {
                  for (final entry in controllers.entries)
                    entry.key: entry.value.text.trim(),
                }),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13)),
                child: const Text('Save Changes',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  for (final controller in controllers.values) {
    controller.dispose();
  }
  return result;
}
