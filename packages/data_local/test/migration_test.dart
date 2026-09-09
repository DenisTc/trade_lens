import 'package:data_local/data_local.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'drift/schema.dart';
import 'drift/schema_v1.dart' as v1;

/// Real migration, not schema creation: a database created at v1 with data
/// in it is upgraded to v2 and the rows must survive with `note == null`.
/// Schema snapshots live in `drift_schemas/` (drift_dev schema dump) and
/// the helper classes in `test/drift/` (drift_dev schema generate).
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('v1 → v2 keeps positions and adds a nullable note', () async {
    final schema = await verifier.schemaAt(1);
    final oldDb = v1.DatabaseAtV1(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO positions (id, asset_id, asset_symbol, asset_name, quote, '
      'qty, avg_price, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      ['p1', 'btc', 'BTC', 'Bitcoin', 'USDT', '0.5', '60000.01', 1757400000],
    );
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);

    final repo = DriftPortfolioRepository(db);
    final positions = await repo.positions();
    expect(positions.single.id, 'p1');
    expect(positions.single.qty.toString(), '0.5');
    expect(positions.single.avgPrice.toString(), '60000.01');
    expect(positions.single.note, isNull);

    await repo.upsert(positions.single.copyWith(note: 'after upgrade'));
    expect((await repo.positions()).single.note, 'after upgrade');
    await db.close();
  });

  test(
    'a fresh database created by onCreate matches the v2 snapshot',
    () async {
      // An empty in-memory database: opening it runs the app's own onCreate,
      // and the verifier compares the result with the v2 snapshot.
      final db = AppDatabase(NativeDatabase.memory());
      await verifier.migrateAndValidate(db, 2);
      await db.close();
    },
  );
}
