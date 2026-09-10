import 'package:ai_review/ai_review.dart';
import 'package:test/test.dart';

String chunk(String path, {int lines = 3}) => [
  'diff --git a/$path b/$path',
  'index 1111111..2222222 100644',
  '--- a/$path',
  '+++ b/$path',
  '@@ -1,$lines +1,$lines @@',
  for (var i = 0; i < lines; i++) '+line $i',
].join('\n');

void main() {
  group('isReviewable', () {
    test('generated, managed and binary files are not', () {
      for (final path in [
        'packages/domain/lib/src/asset.freezed.dart',
        'packages/data_local/lib/src/database.g.dart',
        'apps/mobile/lib/firebase_options.dart',
        'packages/features/shared/lib/src/l10n/app_localizations_ru.dart',
        'pubspec.lock',
        'apps/mobile/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
        'docs/demo/tradelens.gif',
        'docs/screenshots/markets_dark.png',
      ]) {
        expect(isReviewable(path), isFalse, reason: path);
      }
    });

    test('hand-written code, docs and CI are', () {
      for (final path in [
        'packages/sdui/lib/src/parser.dart',
        'apps/mobile/integration_test/app_test.dart',
        '.github/workflows/ci.yml',
        'README.md',
        'apps/mobile/android/app/build.gradle.kts',
      ]) {
        expect(isReviewable(path), isTrue, reason: path);
      }
    });
  });

  group('selectDiff', () {
    test('keeps the reviewable files in the order the diff had them', () {
      final diff = selectDiff(
        [
          chunk('packages/sdui/lib/src/parser.dart'),
          chunk('packages/data_local/lib/src/database.g.dart'),
          chunk('README.md'),
        ].join('\n'),
      );

      expect(diff.files, ['packages/sdui/lib/src/parser.dart', 'README.md']);
      expect(diff.skipped, ['packages/data_local/lib/src/database.g.dart']);
      expect(diff.text, contains('parser.dart'));
      expect(diff.text, isNot(contains('database.g.dart')));
    });

    test('a binary file is left out even when its path looks reviewable', () {
      final raw = [
        'diff --git a/assets/icon.bin b/assets/icon.bin',
        'index 1111111..2222222 100644',
        'Binary files a/assets/icon.bin and b/assets/icon.bin differ',
      ].join('\n');

      expect(selectDiff(raw).files, isEmpty);
      expect(selectDiff(raw).skipped, ['assets/icon.bin']);
    });

    test('over the budget it drops the largest files and says which', () {
      final raw = [
        chunk('small.dart', lines: 2),
        chunk('huge.dart', lines: 400),
        chunk('medium.dart', lines: 20),
      ].join('\n');

      final diff = selectDiff(raw, maxChars: 600);

      expect(diff.files, ['small.dart', 'medium.dart']);
      expect(diff.truncated, ['huge.dart']);
      expect(diff.text.length, lessThanOrEqualTo(600));
    });

    test('a rename reports the new path', () {
      final raw = [
        'diff --git a/lib/old.dart b/lib/new.dart',
        'similarity index 98%',
        'rename from lib/old.dart',
        'rename to lib/new.dart',
      ].join('\n');

      expect(selectDiff(raw).files, ['lib/new.dart']);
    });

    test('an empty diff is empty, not a crash', () {
      expect(selectDiff('').isEmpty, isTrue);
      expect(selectDiff('').files, isEmpty);
    });
  });
}
