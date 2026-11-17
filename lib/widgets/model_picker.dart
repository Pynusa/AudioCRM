import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../services/provider_catalog.dart';

/// Bottom sheet with recommended models, models fetched live from the API
/// for this key, search, and manual model-id input.
Future<void> showModelPickerSheet(
  BuildContext context, {
  required ApiKeyEntry keyEntry,
  required String title,
  required List<ModelOption> options,
  required String selected,
  required ValueChanged<String> onSelected,
  bool allowNone = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _ModelSheet(
      keyEntry: keyEntry,
      title: title,
      options: options,
      selected: selected,
      onSelected: onSelected,
      allowNone: allowNone,
    ),
  );
}

class _ModelSheet extends StatefulWidget {
  final ApiKeyEntry keyEntry;
  final String title;
  final List<ModelOption> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool allowNone;
  const _ModelSheet({
    required this.keyEntry,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.allowNone,
  });

  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  final _search = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<AppState>().fetchModels(widget.keyEntry);
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _pick(String id) {
    widget.onSelected(id);
    Navigator.pop(context);
  }

  Future<void> _manual() async {
    final c = TextEditingController(text: _search.text);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ID модели вручную'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'например, gemini-3.8-flash'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Выбрать')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) _pick(v);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final q = _search.text.trim().toLowerCase();
    final remote = (s.modelCache[widget.keyEntry.id] ?? [])
        .where((m) => q.isEmpty || m.toLowerCase().contains(q))
        .toList();
    final rec = widget.options
        .where((o) =>
            q.isEmpty ||
            o.id.toLowerCase().contains(q) ||
            o.title.toLowerCase().contains(q))
        .toList();

    Widget tile(String id, {String? title, String? note}) {
      final sel = id == widget.selected;
      return ListTile(
        dense: true,
        selected: sel,
        selectedTileColor: cs.primaryContainer.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title ?? id,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            [if (title != null) id, if (note != null) note].join(' · '),
            maxLines: 2),
        trailing: sel ? Icon(Icons.check_circle, color: cs.primary) : null,
        onTap: () => _pick(id),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  TextButton.icon(
                    onPressed: _manual,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Вручную'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Поиск модели',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  if (widget.allowNone)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.block),
                      title: const Text('Не использовать'),
                      selected: widget.selected.isEmpty,
                      onTap: () => _pick(''),
                    ),
                  if (rec.isNotEmpty) _header('Рекомендуемые'),
                  for (final o in rec) tile(o.id, title: o.title, note: o.note),
                  _header('Все модели вашего ключа'),
                  if (remote.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : OutlinedButton.icon(
                              onPressed: _fetch,
                              icon: const Icon(Icons.cloud_download_outlined),
                              label: Text(s.modelCache[widget.keyEntry.id] == null
                                  ? 'Загрузить список моделей из API'
                                  : 'Ничего не найдено — обновить'),
                            ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(_error!, style: TextStyle(color: cs.error)),
                    ),
                  for (final m in remote) tile(m),
                  if (remote.isNotEmpty)
                    TextButton.icon(
                      onPressed: _loading ? null : _fetch,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Обновить список'),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
