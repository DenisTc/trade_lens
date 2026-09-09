import 'package:core/core.dart';
import 'package:domain/domain.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom sheet to add or edit a position. Numbers are parsed as
/// `Decimal` from the text; a locale decimal comma is accepted.
Future<void> showPositionEditor(BuildContext context, {Position? existing}) =>
    showModalBottomSheet<void>(
      context: context,
      // The tab screens live in a nested navigator under the shell's
      // floating tab bar; the sheet must open on the root navigator to
      // cover the bar instead of sliding in beneath it.
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      // The sheet's own context sees the keyboard inset; the page's
      // context under the shell may not.
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom:
              MediaQuery.viewInsetsOf(sheetContext).bottom +
              MediaQuery.paddingOf(sheetContext).bottom,
        ),
        child: PositionEditor(existing: existing),
      ),
    );

class PositionEditor extends ConsumerStatefulWidget {
  const PositionEditor({super.key, this.existing});

  final Position? existing;

  @override
  ConsumerState<PositionEditor> createState() => _PositionEditorState();
}

class _PositionEditorState extends ConsumerState<PositionEditor> {
  final _form = GlobalKey<FormState>();
  late Asset _asset = widget.existing?.asset ?? defaultAssets.first;
  late final _qty = TextEditingController(
    text: widget.existing?.qty.toString() ?? '',
  );
  late final _price = TextEditingController(
    text: widget.existing?.avgPrice.toString() ?? '',
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  var _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final assets = ref.watch(assetsProvider);
    final quote =
        ref.watch(marketDataSourceProvider).value?.defaultQuote ??
        widget.existing?.quote ??
        'USDT';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? l10n.addPosition : l10n.editPosition,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Asset>(
              key: const Key('position_asset'),
              initialValue: _asset,
              decoration: InputDecoration(labelText: l10n.asset),
              items: [
                for (final a in assets)
                  DropdownMenuItem(
                    value: a,
                    child: Text('${a.symbol} · ${a.name}'),
                  ),
              ],
              onChanged: widget.existing == null
                  ? (a) => setState(() => _asset = a ?? _asset)
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('position_qty'),
              controller: _qty,
              decoration: InputDecoration(labelText: l10n.quantity),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) =>
                  parseDecimal(v) == null ? l10n.invalidNumber : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('position_price'),
              controller: _price,
              decoration: InputDecoration(
                labelText: l10n.averagePrice,
                suffixText: widget.existing?.quote ?? quote,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) =>
                  parseDecimal(v) == null ? l10n.invalidNumber : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('position_note'),
              controller: _note,
              decoration: InputDecoration(labelText: l10n.note),
              maxLength: 80,
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('position_save'),
              onPressed: _saving ? null : () => _save(quote),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(String quote) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final qty = parseDecimal(_qty.text)!;
    final price = parseDecimal(_price.text)!;
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final commands = ref.read(portfolioCommandsProvider.notifier);
    final existing = widget.existing;
    try {
      if (existing == null) {
        await commands.add(
          asset: _asset,
          quote: quote,
          qty: qty,
          avgPrice: price,
          note: note,
        );
      } else {
        await commands.update(
          existing.copyWith(qty: qty, avgPrice: price, note: note),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Positive decimal from user text; `,` is accepted as the decimal mark.
Decimal? parseDecimal(String? text) {
  if (text == null) return null;
  final normalized = text.trim().replaceAll(' ', '').replaceAll(',', '.');
  final value = Decimal.tryParse(normalized);
  if (value == null || value <= Decimal.zero) return null;
  return value;
}
