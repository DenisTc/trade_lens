import 'package:domain/domain.dart';
import 'package:features_markets/src/connection_dot.dart';
import 'package:features_markets/src/pair_tile.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The 20 catalog pairs with live prices, searchable by symbol or name.
class MarketsScreen extends ConsumerStatefulWidget {
  const MarketsScreen({required this.onOpenPair, super.key, this.title});

  final void Function(Instrument instrument) onOpenPair;
  final String? title;

  @override
  ConsumerState<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends ConsumerState<MarketsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instruments = ref.watch(marketInstrumentsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? context.l10n.tabMarkets),
        actions: const [ConnectionDot()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const Key('markets_search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.l10n.search,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
        ),
      ),
      body: AsyncValueView<List<Instrument>>(
        value: instruments,
        error: (error, _) => ErrorView(
          error: error,
          onRetry: ref.read(retryMarketSourceProvider),
        ),
        data: (all) {
          final visible = filterInstruments(all, _search.text);
          if (visible.isEmpty) {
            return Center(child: Text(context.l10n.nothingMatches));
          }
          return ListView.builder(
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final instrument = visible[index];
              return PairTile(
                key: ValueKey(instrument.symbol),
                instrument: instrument,
                onTap: () => widget.onOpenPair(instrument),
              );
            },
          );
        },
      ),
      bottomNavigationBar: const SafeArea(child: DataSourceBadge()),
    );
  }
}

/// Case-insensitive match on symbol, base symbol or asset name.
List<Instrument> filterInstruments(List<Instrument> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  return [
    for (final i in all)
      if (i.symbol.toLowerCase().contains(q) ||
          i.base.symbol.toLowerCase().contains(q) ||
          i.base.name.toLowerCase().contains(q))
        i,
  ];
}
