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

    test('an unusual name survives git quoting it', () {
      final raw = [
        r'diff --git "a/docs/caf\303\251.md" "b/docs/caf\303\251.md"',
        'index 1111111..2222222 100644',
        r'--- "a/docs/caf\303\251.md"',
        r'+++ "b/docs/caf\303\251.md"',
        '@@ -1 +1 @@',
        '+text',
      ].join('\n');

      expect(selectDiff(raw).files, ['docs/café.md']);
    });

    test('a path containing " b/" is not cut in half', () {
      final raw = [
        'diff --git a/docs/old b/file.md b/docs/old b/file.md',
        'index 1111111..2222222 100644',
        '--- a/docs/old b/file.md',
        '+++ b/docs/old b/file.md',
        '@@ -1 +1 @@',
        '+text',
      ].join('\n');

      expect(selectDiff(raw).files, ['docs/old b/file.md']);
    });

    test('a deleted file is reported by its old path', () {
      final raw = [
        'diff --git a/lib/gone.dart b/lib/gone.dart',
        'deleted file mode 100644',
        'index 1111111..0000000',
        '--- a/lib/gone.dart',
        '+++ /dev/null',
        '@@ -1 +0,0 @@',
        '-final x = 1;',
      ].join('\n');

      expect(selectDiff(raw).files, ['lib/gone.dart']);
    });

    test('a mode change carries only the header', () {
      final raw = [
        'diff --git a/tooling/scripts/format.sh b/tooling/scripts/format.sh',
        'old mode 100644',
        'new mode 100755',
      ].join('\n');

      expect(selectDiff(raw).files, ['tooling/scripts/format.sh']);
    });

    test('an empty diff is empty, not a crash', () {
      expect(selectDiff('').isEmpty, isTrue);
      expect(selectDiff('').files, isEmpty);
    });
  });
}
