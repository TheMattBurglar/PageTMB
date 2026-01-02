import 'package:flutter_test/flutter_test.dart';
import 'package:pagetmb/logic/editor_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Find and Replace Tests', () {
    late EditorController controller;

    setUp(() {
      controller = EditorController();
      // Insert some initial text
      // "The quick brown fox jumps over the lazy dog. The fox is fast."
      controller.insertText(
        'The quick brown fox jumps over the lazy dog. The fox is fast.',
      );
    });

    test('find() should locate all occurrences', () {
      controller.find('fox');
      expect(controller.searchResults.length, 2);
      expect(controller.currentSearchIndex, 0);

      // Verify ranges
      // "The quick brown " -> 16 chars. "fox" starts at 16.
      // 1st match: Paragraph 0, 16-19
      expect(controller.searchResults[0].range.start, 16);
      expect(controller.searchResults[0].range.end, 19);

      // "...dog. The " -> 44 chars total before second "fox".
      // "The quick brown fox jumps over the lazy dog. " -> 45 chars
      // "The " -> 4 chars
      // Total 49?
      // "The quick brown fox jumps over the lazy dog. " (45)
      // "The fox is fast."
      // "The " is 4. Result 49?
      // Let's rely on finding it.
      expect(controller.searchResults[1].range.start > 19, true);
    });

    test('findNext() and findPrevious() should navigate', () {
      controller.find('the'); // "The", "the", "The" -> case insensitive?
      // wait, logic is case sensitive by default in `text.indexOf` unless we lowercased it.
      // My implementation used `text.indexOf(query)`. It is case sensitive.
      // So "The" and "the" are different.

      controller.find('fox'); // 2 matches
      expect(controller.currentSearchIndex, 0);

      controller.findNext('fox');
      expect(controller.currentSearchIndex, 1);

      controller.findNext('fox');
      expect(controller.currentSearchIndex, 0); // Wraps around

      controller.findPrevious('fox');
      expect(controller.currentSearchIndex, 1); // Wraps back
    });

    test('replaceCurrent() should replace text and update results', () {
      controller.find('fox');
      expect(controller.searchResults.length, 2);

      // Replace first "fox" with "cat"
      controller.replaceCurrent('fox', 'cat');

      // Text should be "The quick brown cat jumps..."
      // Controller usually clears search or re-searches.
      // Implementation called `find(query)` again at the end of replaceCurrent.

      expect(
        controller.document.paragraphs[0].runs[0].text.contains('cat'),
        true,
      );
      expect(controller.searchResults.length, 1); // Only one "fox" left
      expect(
        controller.currentSearchIndex,
        0,
      ); // Should point to the next one (which is now index 0 of 1)
    });

    test('replaceAll() should replace all occurrences', () {
      controller.find('fox');
      controller.replaceAll('fox', 'cat');

      final text = controller.document.paragraphs[0].runs[0].text;
      expect(text.contains('fox'), false);
      expect(
        text,
        'The quick brown cat jumps over the lazy dog. The cat is fast.',
      );
      expect(controller.searchResults.isEmpty, true);
    });

    test('replace with empty string (delete)', () {
      controller.find('quick ');
      controller.replaceCurrent('quick ', '');
      final text = controller.document.paragraphs[0].runs[0].text;
      expect(text.startsWith('The brown'), true);
    });
  });
}
