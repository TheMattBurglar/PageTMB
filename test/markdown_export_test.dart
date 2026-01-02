import 'package:flutter_test/flutter_test.dart';
import 'package:pagetmb/models/document.dart';
import 'package:pagetmb/logic/markdown_exporter.dart';

void main() {
  group('Markdown Export', () {
    test('Exports headers correctly', () {
      final doc = Document(
        paragraphs: [
          Paragraph(
            runs: [
              TextRun(
                text: 'Header 1',
                attributes: const TextAttributes(bold: true, fontSize: 24.0),
              ),
            ],
          ),
          Paragraph(
            runs: [
              TextRun(
                text: 'Header 2',
                attributes: const TextAttributes(bold: true, fontSize: 20.0),
              ),
            ],
          ),
        ],
      );

      final md = MarkdownExporter.generateMarkdown(doc);
      expect(md, contains('# Header 1\n'));
      expect(md, contains('## Header 2\n'));
    });

    test('Exports inline styles correctly', () {
      final doc = Document(
        paragraphs: [
          Paragraph(
            runs: [
              TextRun(text: 'Plain ', attributes: const TextAttributes()),
              TextRun(
                text: 'bold',
                attributes: const TextAttributes(bold: true),
              ),
              TextRun(text: ' ', attributes: const TextAttributes()),
              TextRun(
                text: 'italic',
                attributes: const TextAttributes(italic: true),
              ),
              TextRun(text: ' ', attributes: const TextAttributes()),
              TextRun(
                text: 'underline',
                attributes: const TextAttributes(underline: true),
              ),
              TextRun(text: ' ', attributes: const TextAttributes()),
              TextRun(
                text: 'strike',
                attributes: const TextAttributes(strikethrough: true),
              ),
            ],
          ),
        ],
      );

      final md = MarkdownExporter.generateMarkdown(doc);
      expect(
        md,
        contains('Plain **bold** *italic* <u>underline</u> ~~strike~~'),
      );
    });

    test('Exports lists and blockquotes', () {
      final doc = Document(
        paragraphs: [
          Paragraph(
            runs: [TextRun(text: 'Quote', attributes: const TextAttributes())],
            type: ParagraphType.blockquote,
          ),
          Paragraph(
            runs: [TextRun(text: 'Bullet', attributes: const TextAttributes())],
            type: ParagraphType.bulletList,
          ),
          Paragraph(
            runs: [
              TextRun(text: 'Numbered', attributes: const TextAttributes()),
            ],
            type: ParagraphType.numberedList,
            listIndex: 1,
          ),
        ],
      );

      final md = MarkdownExporter.generateMarkdown(doc);
      expect(md, contains('> Quote'));
      expect(md, contains('- Bullet'));
      expect(md, contains('1. Numbered'));
    });

    test('Exports centered text', () {
      final doc = Document(
        paragraphs: [
          Paragraph(
            runs: [
              TextRun(text: 'Centered', attributes: const TextAttributes()),
            ],
            alignment: ParagraphAlignment.center,
          ),
        ],
      );

      final md = MarkdownExporter.generateMarkdown(doc);
      expect(md, contains('<center>Centered</center>'));
    });

    test('Exports code blocks and snippets', () {
      final doc = Document(
        paragraphs: [
          Paragraph(
            runs: [
              TextRun(text: 'Plain ', attributes: const TextAttributes()),
              TextRun(
                text: 'code',
                attributes: const TextAttributes(monospace: true),
              ),
            ],
          ),
          Paragraph(
            runs: [
              TextRun(
                text: 'print("hello")',
                attributes: const TextAttributes(monospace: true),
              ),
            ],
            type: ParagraphType.codeBlock,
          ),
        ],
      );

      final md = MarkdownExporter.generateMarkdown(doc);
      expect(md, contains('Plain `code`'));
      expect(md, contains('```\nprint("hello")\n```'));
    });

    test('Screenplay mode font does not trigger backticks', () {
      final doc = Document(
        paragraphs: [
          Paragraph(
            runs: [
              TextRun(
                text: 'SCENE START',
                attributes: const TextAttributes(
                  fontFamily: 'Courier Prime',
                  bold: true,
                ),
              ),
            ],
          ),
        ],
      );

      final md = MarkdownExporter.generateMarkdown(doc);
      expect(md, isNot(contains('`SCENE START`')));
      expect(md, contains('**SCENE START**'));
    });
    test('Exports links correctly', () {
      final doc = Document(
        paragraphs: [
          Paragraph(
            runs: [
              TextRun(text: 'Go to ', attributes: const TextAttributes()),
              TextRun(
                text: 'Google',
                attributes: const TextAttributes(linkUrl: 'https://google.com'),
              ),
            ],
          ),
        ],
      );

      final md = MarkdownExporter.generateMarkdown(doc);
      expect(md, contains('Go to [Google](https://google.com)'));
    });
  });
}
