import 'package:core/core.dart';
import 'package:features_shared/features_shared.dart';
import 'package:features_shared/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.dark}) =>
      testApp(
        overrides: fakeOverrides(source: FakeMarketDataSource()),
        brightness: brightness,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('ChangeChip formats the percentage and colours by sign', (
    tester,
  ) async {
    await tester.pumpWidget(host(ChangeChip(pct: Decimal.parse('2.14'))));
    expect(find.text('+2.14%'), findsOneWidget);
    var text = tester.widget<Text>(find.text('+2.14%'));
    expect(text.style?.color, TradeLensPalette.dark.up);
    expect(text.style?.fontFamily, TradeLensFonts.mono);

    await tester.pumpWidget(host(ChangeChip(pct: Decimal.parse('-3.42'))));
    text = tester.widget<Text>(find.text('-3.42%'));
    expect(text.style?.color, TradeLensPalette.dark.down);

    await tester.pumpWidget(host(const ChangeChip()));
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('ChangeChip hugs its text instead of filling the column', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 200,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [ChangeChip(pct: Decimal.parse('1'))],
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byType(ChangeChip));
    expect(size.height, 22);
    expect(size.width, lessThan(100));
  });

  testWidgets('StatusChip shows the ring and label', (tester) async {
    await tester.pumpWidget(
      host(const StatusChip(label: 'Live', color: Colors.green)),
    );
    expect(find.text('Live'), findsOneWidget);
    expect(find.byType(LensRing), findsOneWidget);
  });

  testWidgets('GlassTabBar reports taps and marks the selection', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => host(
          SizedBox(
            width: 390,
            child: GlassTabBar(
              selectedIndex: selected,
              onSelected: (i) => setState(() => selected = i),
              tabs: const [
                GlassTab(key: Key('a'), icon: Icons.abc, label: 'A'),
                GlassTab(key: Key('b'), icon: Icons.ac_unit, label: 'B'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('a'))).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.byKey(const Key('b')));
    await tester.pumpAndSettle();
    expect(selected, 1);
    final semantics = tester.getSemantics(find.byKey(const Key('b')));
    expect(semantics.flagsCollection.isSelected.name, 'isTrue');
  });

  testWidgets('SettingsRow is at least 64 px and shows a chevron when '
      'tappable', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 390,
          child: SettingsRow(
            icon: Icons.tune,
            title: 'Title',
            subtitle: 'Sub',
            onTap: () {},
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(SettingsRow)).height,
      greaterThanOrEqualTo(64),
    );
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });
}
