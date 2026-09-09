import 'package:domain/domain.dart';
import 'package:features_markets/src/connection_dot.dart';
import 'package:features_markets/src/pair_tile.dart';
import 'package:features_shared/features_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The 20 catalog pairs with live prices. The header carries the wordmark,
/// the connection status and a search button that unfolds into a field.
class MarketsScreen extends ConsumerStatefulWidget {
  const MarketsScreen({required this.onOpenPair, super.key, this.title});

  final void Function(Instrument instrument) onOpenPair;
  final String? title;

  @override
  ConsumerState<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends ConsumerState<MarketsScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  var _searching = false;

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _search.clear();
    });
    if (_searching) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final instruments = ref.watch(marketInstrumentsProvider);
    final l10n = context.l10n;
    final t = context.tokens;
    return Scaffold(
      body: Column(
        children: [
          ScreenHeader(
            leading: _Wordmark(title: widget.title ?? l10n.appName),
            actions: [
              const ConnectionDot(),
              HeaderIconButton(
                key: const Key('markets_search_toggle'),
                icon: _searching ? Icons.close : Icons.search,
                tooltip: l10n.search,
                onPressed: _toggleSearch,
              ),
            ],
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                key: const Key('markets_search'),
                controller: _search,
                focusNode: _focus,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l10n.search,
                  prefixIcon: Icon(Icons.search, color: t.muted, size: 20),
                  isDense: true,
                ),
              ),
            )
          else
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.marketsSubtitle,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Text(
                    l10n.marketsColumns,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          Expanded(
            child: AsyncValueView<List<Instrument>>(
              value: instruments,
              loading: () => ListView(
                children: [
                  for (var i = 0; i < 8; i++) const PairTileSkeleton(),
                ],
              ),
              error: (error, _) => ErrorView(
                error: error,
                onRetry: ref.read(retryMarketSourceProvider),
              ),
              data: (all) {
                final visible = filterInstruments(all, _search.text);
                if (visible.isEmpty) {
                  return Center(child: Text(l10n.nothingMatches));
                }
                return ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + 8,
                  ),
                  itemCount: visible.length + 1,
                  itemBuilder: (context, index) {
                    if (index == visible.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: DataSourceBadge(),
                      );
                    }
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
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      LensRing(size: 26, color: context.tokens.accent),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
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
