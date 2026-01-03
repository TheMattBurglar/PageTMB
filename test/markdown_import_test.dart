import 'package:flutter_test/flutter_test.dart';
import 'package:pagetmb/models/document.dart';
import 'package:pagetmb/logic/editor_controller.dart'; // To access parseMarkdownToDocument

void main() {
  group('Markdown Import', () {
    test('Imports headers as Bold + FontSize with preserved spacing', () {
      final doc = parseMarkdownToDocument('# Header 1\n\n## Header 2');
      // Should be 3 paragraphs: H1, empty, H2
      expect(doc.paragraphs.length, 3);

      final p1 = doc.paragraphs[0];
      expect(p1.runs.first.text, 'Header 1');
      expect(p1.runs.first.attributes.fontSize, 32.0);

      expect(doc.paragraphs[1].runs.first.text, '');

      final p2 = doc.paragraphs[2];
      expect(p2.runs.first.text, 'Header 2');
      expect(p2.runs.first.attributes.fontSize, 26.0);
    });

    test('Imports tight headers without extra space', () {
      final doc = parseMarkdownToDocument('# H1\n## H2');
      // Should be exactly 2 paragraphs
      expect(doc.paragraphs.length, 2);
      expect(doc.paragraphs[0].runs.first.text, 'H1');
      expect(doc.paragraphs[1].runs.first.text, 'H2');
    });

    test('Imports task list checkboxes', () {
      final doc = parseMarkdownToDocument('- [x] Done\n- [ ] Todo');
      // Tight list: 2 paragraphs
      expect(doc.paragraphs.length, 2);
      expect(doc.paragraphs[0].runs.map((r) => r.text).join(), '[x] Done');
      expect(doc.paragraphs[1].runs.map((r) => r.text).join(), '[ ] Todo');
    });

    test('Imports blockquotes with correct type', () {
      final doc = parseMarkdownToDocument('> This is a quote');
      expect(doc.paragraphs.length, 1);
      final p = doc.paragraphs.first;

      expect(p.type, ParagraphType.blockquote);
      expect(p.runs.first.text, 'This is a quote');
    });

    test('Imports bullet lists with correct type', () {
      final doc = parseMarkdownToDocument('* Item 1\n- Item 2');
      expect(doc.paragraphs.length, 2);

      expect(doc.paragraphs[0].type, ParagraphType.bulletList);
      expect(doc.paragraphs[0].runs.first.text, 'Item 1');

      expect(doc.paragraphs[1].type, ParagraphType.bulletList);
      expect(doc.paragraphs[1].runs.first.text, 'Item 2');
    });

    test('Imports multi-line code blocks and trims trailing newline', () {
      final doc = parseMarkdownToDocument('```bash\nline1\nline2\n```');
      // Should be 1 paragraph (code block)
      expect(doc.paragraphs.length, 1);
      final p = doc.paragraphs.first;
      expect(p.type, ParagraphType.codeBlock);
      // The content should be 'line1\nline2'. The newline after line2 should be trimmed.
      expect(p.runs.first.text, 'line1\nline2');
    });

    test('Imports centered text and complex blocks', () {
      final doc = parseMarkdownToDocument('<center>Centered Line</center>');
      expect(doc.paragraphs.length, 1);
      expect(doc.paragraphs.first.alignment, ParagraphAlignment.center);
      expect(doc.paragraphs.first.runs.first.text, 'Centered Line');

      final doc2 = parseMarkdownToDocument(
        '<center>\n# Centered Header\n</center>',
      );
      // Depending on package:markdown, it might be 1 paragraph or multiple
      // With my new logic, it should ideally be centered.
      expect(
        doc2.paragraphs.any((p) => p.alignment == ParagraphAlignment.center),
        isTrue,
      );
    });

    test('Imports inline bold', () {
      final doc = parseMarkdownToDocument('This is **bold** text');
      expect(doc.paragraphs.length, 1);
      final p = doc.paragraphs.first;

      expect(p.runs.length, 3);
      expect(p.runs[1].text, 'bold');
      expect(p.runs[1].attributes.bold, true);
    });
    test('Imports links correctly', () {
      final doc = parseMarkdownToDocument('Check [Google](https://google.com)');
      expect(doc.paragraphs.length, 1);
      final p = doc.paragraphs.first;
      // We expect [Check , Google]
      expect(p.runs.length, 2);
      expect(p.runs[1].text, 'Google');
      expect(p.runs[1].attributes.linkUrl, 'https://google.com');
    });

    test('Imports headers with new font sizes', () {
      final doc = parseMarkdownToDocument(
        '### H3\n#### H4\n##### H5\n###### H6',
      );
      expect(doc.paragraphs.length, 4);
      expect(doc.paragraphs[0].runs.first.attributes.fontSize, 20.0);
      expect(doc.paragraphs[1].runs.first.attributes.fontSize, 16.0);
      expect(doc.paragraphs[2].runs.first.attributes.fontSize, 14.0);
      expect(doc.paragraphs[3].runs.first.attributes.fontSize, 13.0);
    });
  });
}
