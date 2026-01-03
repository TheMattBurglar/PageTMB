import '../models/document.dart';

class MarkdownExporter {
  /// Generates a Markdown string from a [Document].
  static String generateMarkdown(Document document) {
    final buffer = StringBuffer();

    for (int i = 0; i < document.paragraphs.length; i++) {
      final p = document.paragraphs[i];

      // Handle Horizontal Rule
      if (p.type == ParagraphType.horizontalRule) {
        buffer.writeln('---');
        if (i < document.paragraphs.length - 1) buffer.writeln();
        continue;
      }

      // Handle Code Block
      if (p.type == ParagraphType.codeBlock) {
        buffer.writeln('```');
        buffer.write(p.text);
        buffer.writeln();
        buffer.writeln('```');
        if (i < document.paragraphs.length - 1) buffer.writeln();
        continue;
      }

      // Start line prefix
      String prefix = '';

      // Handle Blockquotes
      if (p.type == ParagraphType.blockquote) {
        prefix = '> ';
      }
      // Handle Lists
      else if (p.type == ParagraphType.bulletList) {
        prefix = '${_getIndent(p.indent)}- ';
      } else if (p.type == ParagraphType.numberedList) {
        prefix = '${_getIndent(p.indent)}${p.listIndex ?? 1}. ';
      }

      // Handle Centering (wrap entire paragraph if needed)
      final bool isCentered = p.alignment == ParagraphAlignment.center;
      if (isCentered) buffer.write('<center>');

      // Handle Headers (based on font size and bold)
      final hLevel = _getHeaderLevel(p);
      if (hLevel > 0) {
        buffer.write('#' * hLevel + ' ');
      } else {
        buffer.write(prefix);
      }

      // Write Runs
      for (var run in p.runs) {
        buffer.write(_formatRun(run, isHeader: hLevel > 0));
      }

      if (isCentered) buffer.write('</center>');

      buffer.writeln();
    }

    return buffer.toString();
  }

  static String _getIndent(int level) {
    return '  ' * level;
  }

  static int _getHeaderLevel(Paragraph p) {
    if (p.runs.isEmpty) return 0;
    final firstRun = p.runs.first;
    // We check if it's bold and has a specific font size
    if (!firstRun.attributes.bold) return 0;

    final fontSize = firstRun.attributes.fontSize ?? 12.0;
    if (fontSize >= 32.0) return 1;
    if (fontSize >= 26.0) return 2;
    if (fontSize >= 20.0) return 3;
    if (fontSize >= 16.0) return 4;
    if (fontSize >= 14.0) return 5;
    if (fontSize >= 13.0) return 6;
    // We avoid H6 at 12.0 because it's ambiguous with normal bold text

    return 0;
  }

  static String _formatRun(TextRun run, {bool isHeader = false}) {
    String text = run.text;
    if (text.isEmpty) return '';

    final attrs = run.attributes;

    // Apply styles in order: strikethrough, underline, italic, bold
    if (attrs.strikethrough) text = '~~$text~~';
    if (attrs.underline) text = '<u>$text</u>';
    if (attrs.italic) text = '*$text*';
    // Only apply bold if not in a header (headers are bold by default)
    if (attrs.bold && !isHeader) {
      text = '**$text**';
    }

    // Monospace detection for code snippets
    if (attrs.monospace) {
      text = '`$text`';
    }

    // Link detection
    if (attrs.linkUrl != null) {
      text = '[$text](${attrs.linkUrl})';
    }

    return text;
  }
}
