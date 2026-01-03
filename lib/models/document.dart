import 'package:flutter/material.dart';

class TextAttributes {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final String? fontFamily;
  final double? fontSize;
  final bool monospace;
  final String? linkUrl;

  const TextAttributes({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.fontFamily,
    this.fontSize = 12.0,
    this.monospace = false,
    this.linkUrl,
  });
  TextAttributes copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    String? fontFamily,
    double? fontSize,
    bool? monospace,
    String? linkUrl,
  }) {
    return TextAttributes(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      monospace: monospace ?? this.monospace,
      linkUrl: linkUrl ?? this.linkUrl,
    );
  }

  TextAttributes clone() => copyWith();

  TextStyle toTextStyle({
    double height = 1.0,
    bool includeMonospaceBackground = true,
    String? defaultFontFamily,
  }) {
    return TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      fontFamily: fontFamily ?? defaultFontFamily,
      fontSize: fontSize ?? 12.0,
      height: height,
      backgroundColor: (monospace && includeMonospaceBackground)
          ? Colors.brown.withValues(alpha: 0.15)
          : null,
      color: linkUrl != null ? Colors.blue : null,
      decoration: TextDecoration.combine([
        if (underline || linkUrl != null) TextDecoration.underline,
        if (strikethrough) TextDecoration.lineThrough,
      ]),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bold': bold,
      'italic': italic,
      'underline': underline,
      'strikethrough': strikethrough,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'monospace': monospace,
      'linkUrl': linkUrl,
    };
  }

  factory TextAttributes.fromJson(Map<String, dynamic> json) {
    return TextAttributes(
      bold: json['bold'] ?? false,
      italic: json['italic'] ?? false,
      underline: json['underline'] ?? false,
      strikethrough: json['strikethrough'] ?? false,
      fontFamily: json['fontFamily'],
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 12.0,
      monospace: json['monospace'] ?? false,
      linkUrl: json['linkUrl'],
    );
  }
}

class TextRun {
  final String text;
  final TextAttributes attributes;

  TextRun({required this.text, required this.attributes});

  TextRun clone() => TextRun(text: text, attributes: attributes);

  Map<String, dynamic> toJson() {
    return {'text': text, 'attributes': attributes.toJson()};
  }

  factory TextRun.fromJson(Map<String, dynamic> json) {
    return TextRun(
      text: json['text'] ?? '',
      attributes: TextAttributes.fromJson(json['attributes'] ?? {}),
    );
  }
}

enum ParagraphAlignment { left, center, right, justify }

enum ParagraphType {
  normal,
  blockquote,
  bulletList,
  numberedList,
  horizontalRule,
  codeBlock,
}

class Paragraph {
  final List<TextRun> runs;
  final ParagraphAlignment alignment;
  final double lineSpacing;
  ParagraphType type;
  int indent;
  int? listIndex;
  int? originalIndex;
  final int offsetInOriginal;
  double? cachedHeight;
  double? cachedWidth;

  String get text => runs.map((r) => r.text).join('');

  Paragraph({
    required this.runs,
    this.alignment = ParagraphAlignment.left,
    this.lineSpacing = 1.0,
    this.type = ParagraphType.normal,
    this.indent = 0,
    this.listIndex,
    this.isContinuation = false,
    this.originalIndex,
    this.offsetInOriginal = 0,
  });

  bool isContinuation;

  Paragraph clone() {
    final p = Paragraph(
      runs: runs.map((r) => r.clone()).toList(),
      alignment: alignment,
      lineSpacing: lineSpacing,
      type: type,
      indent: indent,
      listIndex: listIndex,
      isContinuation: isContinuation,
      originalIndex: originalIndex,
      offsetInOriginal: offsetInOriginal,
    );
    p.cachedHeight = cachedHeight;
    p.cachedWidth = cachedWidth;
    return p;
  }

  Map<String, dynamic> toJson() {
    return {
      'runs': runs.map((r) => r.toJson()).toList(),
      'alignment': alignment.index,
      'lineSpacing': lineSpacing,
      'type': type.index,
      'indent': indent,
      if (listIndex != null) 'listIndex': listIndex,
      'isContinuation': isContinuation,
    };
  }

  factory Paragraph.fromJson(Map<String, dynamic> json) {
    return Paragraph(
      runs:
          (json['runs'] as List<dynamic>?)
              ?.map((r) => TextRun.fromJson(r))
              .toList() ??
          [],
      alignment: ParagraphAlignment.values[json['alignment'] ?? 0],
      lineSpacing: (json['lineSpacing'] as num?)?.toDouble() ?? 1.0,
      type: ParagraphType.values[json['type'] ?? 0],
      indent: json['indent'] ?? 0,
      listIndex: json['listIndex'],
      isContinuation: json['isContinuation'] ?? false,
    );
  }

  double get structuralLeftOffset {
    if (type == ParagraphType.blockquote) {
      return 20.0; // 4.0 border + 16.0 padding
    } else if (type == ParagraphType.bulletList ||
        type == ParagraphType.numberedList) {
      return (24.0 * indent) + 32.0;
    }
    return 0.0;
  }

  TextPainter buildPainter({
    double? maxWidth,
    TextAlign? textAlign,
    String? marker,
    double? lineSpacing,
    String? defaultFontFamily,
  }) {
    final double effectiveLineSpacing = lineSpacing ?? this.lineSpacing;
    final List<InlineSpan> spans = [];
    final List<PlaceholderDimensions> dimensions = [];

    // Add marker if it exists
    if (marker != null) {
      // Find the first run to get styling
      final baseStyle = runs.isNotEmpty
          ? runs.first.attributes.toTextStyle(
              height: effectiveLineSpacing,
              includeMonospaceBackground: type != ParagraphType.codeBlock,
              defaultFontFamily: defaultFontFamily,
            )
          : TextStyle(
              fontSize: 12.0,
              height: effectiveLineSpacing,
              fontFamily: defaultFontFamily,
            );

      spans.add(
        TextSpan(
          text: marker,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ),
      );
      // Fixed width for the marker column
      spans.add(const TextSpan(text: ' '));
    }

    for (var run in runs) {
      final style = run.attributes.toTextStyle(
        height: effectiveLineSpacing,
        includeMonospaceBackground: type != ParagraphType.codeBlock,
        defaultFontFamily: defaultFontFamily,
      );
      final text = run.text;

      if (text.contains('\t')) {
        final parts = text.split('\t');
        final spaceTp = TextPainter(
          text: TextSpan(text: '    ', style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final tabWidth = spaceTp.width;

        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) {
            spans.add(TextSpan(text: parts[i], style: style));
          }
          if (i < parts.length - 1) {
            final h = (style.fontSize ?? 12.0) * (style.height ?? 1.0);
            spans.add(
              WidgetSpan(
                child: SizedBox(width: tabWidth, height: h),
                baseline: TextBaseline.alphabetic,
                alignment: PlaceholderAlignment.baseline,
              ),
            );
            dimensions.add(
              PlaceholderDimensions(
                size: Size(tabWidth, h),
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
              ),
            );
          }
        }
      } else {
        spans.add(TextSpan(text: text, style: style));
      }
    }

    final String? firstFontFamily = runs.isNotEmpty
        ? runs.first.attributes.fontFamily
        : defaultFontFamily;
    final rootStyle = TextStyle(
      color: Colors.black,
      height: effectiveLineSpacing,
      fontFamily: firstFontFamily,
      fontSize: 12.0,
    );
    final tp = TextPainter(
      text: TextSpan(children: spans, style: rootStyle),
      textDirection: TextDirection.ltr,
      textAlign: textAlign ?? _getTextAlign(alignment),
      strutStyle: StrutStyle(
        fontFamily: firstFontFamily,
        fontSize: runs.isNotEmpty
            ? runs.first.attributes.fontSize ?? 12.0
            : 12.0,
        height: effectiveLineSpacing,
        forceStrutHeight: true,
      ),
    );

    if (dimensions.isNotEmpty) {
      tp.setPlaceholderDimensions(dimensions);
    }

    if (maxWidth != null) {
      if (alignment == ParagraphAlignment.left) {
        tp.layout(maxWidth: maxWidth);
      } else {
        tp.layout(minWidth: maxWidth, maxWidth: maxWidth);
      }
    }

    // Ensure empty paragraphs have a height
    final double minHeight =
        (runs.isNotEmpty ? (runs.first.attributes.fontSize ?? 12.0) : 12.0) *
        effectiveLineSpacing;
    if (tp.height < minHeight) {
      // We can't easily force TextPainter height, but we can return its metrics or handle it in callers.
      // However, Paginator uses tp.height directly.
      // For now, let's just be aware that tp.height with an empty string but valid style SHOULD have height in Flutter.
    }

    return tp;
  }

  static TextAlign _getTextAlign(ParagraphAlignment alignment) {
    switch (alignment) {
      case ParagraphAlignment.left:
        return TextAlign.left;
      case ParagraphAlignment.center:
        return TextAlign.center;
      case ParagraphAlignment.right:
        return TextAlign.right;
      case ParagraphAlignment.justify:
        return TextAlign.justify;
    }
  }
}

class DocumentMetadata {
  final String version;
  final int editorModeIndex;
  final DateTime lastModified;
  final String author;
  final String title;

  DocumentMetadata({
    this.version = "1.0",
    this.editorModeIndex = 0, // Defaults to Freestyle or 0
    DateTime? lastModified,
    this.author = "",
    this.title = "",
  }) : lastModified = lastModified ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'editorModeIndex': editorModeIndex,
      'lastModified': lastModified.toIso8601String(),
      'author': author,
      'title': title,
    };
  }

  factory DocumentMetadata.fromJson(Map<String, dynamic> json) {
    return DocumentMetadata(
      version: json['version'] ?? "1.0",
      editorModeIndex: json['editorModeIndex'] ?? 0,
      lastModified: json['lastModified'] != null
          ? DateTime.tryParse(json['lastModified'])
          : null,
      author: json['author'] ?? "",
      title: json['title'] ?? "",
    );
  }
}

class Document {
  final List<Paragraph> paragraphs;
  DocumentMetadata metadata;

  Document({required this.paragraphs, DocumentMetadata? metadata})
    : metadata = metadata ?? DocumentMetadata();

  static Document empty() {
    return Document(
      paragraphs: [
        Paragraph(
          runs: [TextRun(text: '', attributes: const TextAttributes())],
        ),
      ],
      metadata: DocumentMetadata(),
    );
  }

  Document clone() => Document(
    paragraphs: paragraphs.map((p) => p.clone()).toList(),
    metadata: DocumentMetadata(
      version: metadata.version,
      editorModeIndex: metadata.editorModeIndex,
      lastModified: metadata.lastModified,
      author: metadata.author,
      title: metadata.title,
    ),
  );

  Map<String, dynamic> toJson() {
    return {
      'metadata': metadata.toJson(),
      'paragraphs': paragraphs.map((p) => p.toJson()).toList(),
    };
  }

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      metadata: DocumentMetadata.fromJson(json['metadata'] ?? {}),
      paragraphs:
          (json['paragraphs'] as List<dynamic>?)
              ?.map((p) => Paragraph.fromJson(p))
              .toList() ??
          [],
    );
  }
}
