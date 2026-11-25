import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../state/providers.dart';

/// Prompts the user to create a new custom category or rename an existing one.
/// Returns the saved category name, or `null` if cancelled.
Future<String?> showCategoryNameDialog(
  BuildContext context, {
  String? existingName,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CategoryNameDialog(existingName: existingName),
  );
}

/// Asks confirmation before deleting a custom category (documents keep their files).
Future<bool> confirmDeleteCategory(
  BuildContext context,
  WidgetRef ref,
  String name,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Hapus kelompok "$name"?'),
      content: const Text(
        'Dokumen di dalam kelompok ini tidak akan dihapus, hanya dilepas dari kelompok.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Hapus'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  try {
    await ref.read(categoriesProvider.notifier).delete(name);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(formatError(e))),
      );
    }
    return false;
  }
}

/// Bottom sheet with rename/delete actions for a custom category chip.
Future<void> showCustomCategoryActionsSheet(
  BuildContext context,
  WidgetRef ref,
  String categoryName,
) async {
  final scheme = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                const Icon(Icons.label_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Ubah nama kelompok'),
            onTap: () async {
              Navigator.pop(ctx);
              final renamed = await showCategoryNameDialog(
                context,
                existingName: categoryName,
              );
              if (renamed != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Kelompok diubah menjadi "$renamed"')),
                );
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
            title: Text(
              'Hapus kelompok',
              style: TextStyle(color: scheme.error),
            ),
            onTap: () async {
              Navigator.pop(ctx);
              final deleted = await confirmDeleteCategory(
                context,
                ref,
                categoryName,
              );
              if (deleted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Kelompok "$categoryName" dihapus')),
                );
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Modal sheet to pick an existing category, remove it (`''`), or create a new one.
/// Returns `null` when dismissed without selection.
Future<String?> showCategoryPickerSheet(
  BuildContext context, {
  required String currentTag,
  String title = 'Pilih kelompok',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CategoryPickerSheet(
      currentTag: currentTag,
      title: title,
    ),
  );
}

class _CategoryNameDialog extends ConsumerStatefulWidget {
  const _CategoryNameDialog({this.existingName});

  final String? existingName;

  @override
  ConsumerState<_CategoryNameDialog> createState() =>
      _CategoryNameDialogState();
}

class _CategoryNameDialogState extends ConsumerState<_CategoryNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ctrl;
  bool _saving = false;
  String? _serverError;

  bool get _isRename => widget.existingName != null;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.existingName ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_serverError != null) {
      setState(() => _serverError = null);
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final notifier = ref.read(categoriesProvider.notifier);
      final saved = _isRename
          ? await notifier.rename(widget.existingName!, _ctrl.text)
          : await notifier.create(_ctrl.text);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _serverError = formatError(e);
      });
      _formKey.currentState?.validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = ref.watch(categoriesProvider).value ?? documentTags;

    return AlertDialog(
      title: Text(_isRename ? 'Ubah nama kelompok' : 'Buat kelompok baru'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _ctrl,
          autofocus: true,
          enabled: !_saving,
          maxLength: maxCategoryNameLength,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: const InputDecoration(
            hintText: 'Contoh: Kuliah, Pajak, Medis',
          ),
          validator: (value) {
            if (_serverError != null) return _serverError;
            return validateCategoryName(
              value ?? '',
              existing,
              ignoreCurrent: widget.existingName,
            );
          },
          onChanged: (_) {
            if (_serverError != null) {
              setState(() => _serverError = null);
            }
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isRename ? 'Simpan' : 'Buat'),
        ),
      ],
    );
  }
}

class _CategoryPickerSheet extends ConsumerStatefulWidget {
  const _CategoryPickerSheet({
    required this.currentTag,
    required this.title,
  });

  final String currentTag;
  final String title;

  @override
  ConsumerState<_CategoryPickerSheet> createState() =>
      _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends ConsumerState<_CategoryPickerSheet> {
  late String _activeTag;

  @override
  void initState() {
    super.initState();
    _activeTag = widget.currentTag;
  }

  Future<void> _createAndPick() async {
    final created = await showCategoryNameDialog(context);
    if (created != null && mounted) {
      Navigator.of(context).pop(created);
    }
  }

  Future<void> _renameCustom(String oldName) async {
    final renamed = await showCategoryNameDialog(
      context,
      existingName: oldName,
    );
    if (renamed != null && mounted) {
      if (_activeTag.toLowerCase() == oldName.toLowerCase()) {
        setState(() => _activeTag = renamed);
      }
    }
  }

  Future<void> _deleteCustom(String name) async {
    final deleted = await confirmDeleteCategory(context, ref, name);
    if (deleted && mounted) {
      if (_activeTag.toLowerCase() == name.toLowerCase()) {
        setState(() => _activeTag = '');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? documentTags;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.yellow,
                      foregroundColor: AppColors.charcoal,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: _createAndPick,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Buat baru'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outline),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  ListTile(
                    leading: Icon(
                      _activeTag.isEmpty
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: _activeTag.isEmpty
                          ? AppColors.yellowDeep
                          : scheme.onSurfaceVariant,
                    ),
                    title: const Text('Tanpa kelompok'),
                    onTap: () => Navigator.of(context).pop(''),
                  ),
                  for (final tag in categories)
                    _buildCategoryTile(context, tag, scheme),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(
    BuildContext context,
    String tag,
    ColorScheme scheme,
  ) {
    final selected = _activeTag.toLowerCase() == tag.toLowerCase();
    final isCustom = !isDefaultCategory(tag);

    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? AppColors.yellowDeep : scheme.onSurfaceVariant,
      ),
      title: Text(
        tag,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      trailing: isCustom
          ? PopupMenuButton<String>(
              tooltip: 'Kelola kelompok',
              icon: Icon(
                Icons.more_horiz_rounded,
                color: scheme.onSurfaceVariant,
              ),
              onSelected: (action) {
                if (action == 'rename') {
                  _renameCustom(tag);
                } else if (action == 'delete') {
                  _deleteCustom(tag);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: Text('Ubah nama'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Hapus',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
            )
          : null,
      onTap: () => Navigator.of(context).pop(tag),
    );
  }
}
