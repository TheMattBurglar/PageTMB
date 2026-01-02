import 'dart:convert';
import 'package:flutter/painting.dart';
import 'package:xml/xml.dart';
import 'package:archive/archive.dart';
import '../models/document.dart';
import '../constants.dart';

class DocxExporter {
  /// Generates a .docx file as a byte array.
  static Future<List<int>> generateDocx(
    Document document,
    EdgeInsets margins,
    String defaultFontFamily,
  ) async {
    final archive = Archive();

    // 1. [Content_Types].xml
    archive.addFile(
      ArchiveFile(
        '[Content_Types].xml',
        utf8.encode(_buildContentTypes()).length,
        utf8.encode(_buildContentTypes()),
      ),
    );

    // 2. _rels/.rels
    archive.addFile(
      ArchiveFile(
        '_rels/.rels',
        utf8.encode(_buildRels()).length,
        utf8.encode(_buildRels()),
      ),
    );

    // 3. word/_rels/document.xml.rels
    archive.addFile(
      ArchiveFile(
        'word/_rels/document.xml.rels',
        utf8.encode(_buildDocumentRels()).length,
        utf8.encode(_buildDocumentRels()),
      ),
    );

    // 4. word/styles.xml
    archive.addFile(
      ArchiveFile(
        'word/styles.xml',
        utf8.encode(_buildStyles(defaultFontFamily)).length,
        utf8.encode(_buildStyles(defaultFontFamily)),
      ),
    );

    // 5. word/document.xml
    final docXmlContent = _buildDocumentXml(document, margins);
    archive.addFile(
      ArchiveFile(
        'word/document.xml',
        utf8.encode(docXmlContent).length,
        utf8.encode(docXmlContent),
      ),
    );

    final encoder = ZipEncoder();
    return encoder.encode(archive);
  }

  static String _buildContentTypes() {
    final builder = XmlBuilder();
    builder.processing(
      'xml',
      'version="1.0" encoding="UTF-8" standalone="yes"',
    );
    builder.element(
      'Types',
      namespaces: {
        'http://schemas.openxmlformats.org/package/2006/content-types': null,
      },
      nest: () {
        builder.element(
          'Default',
          attributes: {
            'Extension': 'rels',
            'ContentType':
                'application/vnd.openxmlformats-package.relationships+xml',
          },
        );
        builder.element(
          'Default',
          attributes: {'Extension': 'xml', 'ContentType': 'application/xml'},
        );
        builder.element(
          'Override',
          attributes: {
            'PartName': '/word/document.xml',
            'ContentType':
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml',
          },
        );
        builder.element(
          'Override',
          attributes: {
            'PartName': '/word/styles.xml',
            'ContentType':
                'application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml',
          },
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: false);
  }

  static String _buildRels() {
    final builder = XmlBuilder();
    builder.processing(
      'xml',
      'version="1.0" encoding="UTF-8" standalone="yes"',
    );
    builder.element(
      'Relationships',
      namespaces: {
        'http://schemas.openxmlformats.org/package/2006/relationships': null,
      },
      nest: () {
        builder.element(
          'Relationship',
          attributes: {
            'Id': 'rId1',
            'Type':
                'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
            'Target': 'word/document.xml',
          },
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: false);
  }

  static String _buildDocumentRels() {
    final builder = XmlBuilder();
    builder.processing(
      'xml',
      'version="1.0" encoding="UTF-8" standalone="yes"',
    );
    builder.element(
      'Relationships',
      namespaces: {
        'http://schemas.openxmlformats.org/package/2006/relationships': null,
      },
      nest: () {
        builder.element(
          'Relationship',
          attributes: {
            'Id': 'rId1',
            'Type':
                'http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles',
            'Target': 'styles.xml',
          },
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: false);
  }

  static String _buildStyles(String fontFamily) {
    // Basic styles definition
    final builder = XmlBuilder();
    builder.processing(
      'xml',
      'version="1.0" encoding="UTF-8" standalone="yes"',
    );
    builder.element(
      'w:styles',
      namespaces: {
        'http://schemas.openxmlformats.org/wordprocessingml/2006/main': 'w',
      },
      nest: () {
        builder.element(
          'w:docDefaults',
          nest: () {
            builder.element(
              'w:rPrDefault',
              nest: () {
                builder.element(
                  'w:rPr',
                  nest: () {
                    builder.element(
                      'w:rFonts',
                      attributes: {
                        'w:ascii': fontFamily,
                        'w:hAnsi': fontFamily,
                        'w:eastAsia': fontFamily,
                        'w:cs': fontFamily,
                      },
                    );
                    builder.element(
                      'w:sz',
                      attributes: {'w:val': '24'},
                    ); // 12pt
                    builder.element('w:szCs', attributes: {'w:val': '24'});
                    builder.element('w:lang', attributes: {'w:val': 'en-US'});
                  },
                );
              },
            );
          },
        );
      },
    );
    return builder.buildDocument().toXmlString(pretty: false);
  }

  static String _buildDocumentXml(Document document, EdgeInsets margins) {
    // We do NOT use Paginator here. We let Word handle the pagination flow.
    // Attempts to force exact page breaks matching Flutter's rendering have caused
    // overflow issues (blank pages) in external editors due to metric differences.
    // It is safer to export the content as a continuous stream.

    final builder = XmlBuilder();
    builder.processing(
      'xml',
      'version="1.0" encoding="UTF-8" standalone="yes"',
    );
    builder.element(
      'w:document',
      namespaces: {
        'http://schemas.openxmlformats.org/wordprocessingml/2006/main': 'w',
      },
      nest: () {
        builder.element(
          'w:body',
          nest: () {
            final modeIndex = document.metadata.editorModeIndex;
            final mode =
                (modeIndex >= 0 && modeIndex < EditorMode.values.length)
                ? EditorMode.values[modeIndex]
                : EditorMode.freestyle;

            if (mode == EditorMode.screenplay ||
                mode == EditorMode.manuscript) {
              _buildTitlePage(builder, document, mode);
            }

            for (var p in document.paragraphs) {
              _buildParagraph(builder, p);
            }

            // Section Properties (Margins) - must be at the end of body
            builder.element(
              'w:sectPr',
              nest: () {
                // Convert points (1/72) to twips (1/1440)
                // 1 point = 20 twips
                final top = (margins.top * 20).toInt().toString();
                final bottom = (margins.bottom * 20).toInt().toString();
                final left = (margins.left * 20).toInt().toString();
                final right = (margins.right * 20).toInt().toString();

                // Page Size (Letter)
                // 8.5 * 1440 = 12240
                // 11 * 1440 = 15840
                builder.element(
                  'w:pgSz',
                  attributes: {'w:w': '12240', 'w:h': '15840'},
                );

                builder.element(
                  'w:pgMar',
                  attributes: {
                    'w:top': top,
                    'w:right': right,
                    'w:bottom': bottom,
                    'w:left': left,
                    'w:header': '720', // Default header margin
                    'w:footer': '720',
                    'w:gutter': '0',
                  },
                );
              },
            );
          },
        );
      },
    );

    return builder.buildDocument().toXmlString(pretty: false);
  }

  static void _buildParagraph(XmlBuilder builder, Paragraph p) {
    if (p.type == ParagraphType.horizontalRule) {
      builder.element(
        'w:p',
        nest: () {
          builder.element(
            'w:pPr',
            nest: () {
              builder.element(
                'w:pBdr',
                nest: () {
                  builder.element(
                    'w:bottom',
                    attributes: {
                      'w:val': 'single',
                      'w:sz': '6',
                      'w:space': '1',
                      'w:color': 'auto',
                    },
                  );
                },
              );
            },
          );
        },
      );
      return;
    }

    builder.element(
      'w:p',
      nest: () {
        builder.element(
          'w:pPr',
          nest: () {
            // Alignment
            String align = 'left';
            if (p.alignment == ParagraphAlignment.center) align = 'center';
            if (p.alignment == ParagraphAlignment.right) align = 'right';
            if (p.alignment == ParagraphAlignment.justify) align = 'both';
            builder.element('w:jc', attributes: {'w:val': align});

            // Spacing
            // Use exact line height to match Flutter's rendering.
            // Disable Widow/Orphan control to match Flutter's simple flow
            builder.element('w:widowControl', attributes: {'w:val': '0'});

            // Spacing
            double fontSize = 12.0;
            if (p.runs.isNotEmpty) {
              fontSize = p.runs.first.attributes.fontSize ?? 12.0;
            }
            final exactTwips = (fontSize * p.lineSpacing * 20)
                .toInt()
                .toString();

            builder.element(
              'w:spacing',
              attributes: {
                'w:line': exactTwips,
                'w:lineRule': 'exact',
                'w:before': '0',
                'w:after': '0',
              },
            );

            // Indentation
            int indentLeft =
                (p.indent * 720); // 0.5 inch per indent level in twips

            // Handle Blockquote visual indent
            if (p.type == ParagraphType.blockquote) {
              indentLeft += 720; // Extra indent for BQ
              // We can also add a border here for BQ if we really want, but let's stick to indent for now.
              // Word requires w:pbdr for borders.
              builder.element(
                'w:pBdr',
                nest: () {
                  builder.element(
                    'w:left',
                    attributes: {
                      'w:val': 'single',
                      'w:sz': '12', // 1/8 pt units? 4 = 0.5pt. 12 = 1.5pt
                      'w:space': '24', // spacing from text
                      'w:color': 'AAAAAA',
                    },
                  );
                },
              );
            }

            if (indentLeft > 0) {
              builder.element(
                'w:ind',
                attributes: {'w:left': indentLeft.toString()},
              );
            }
          },
        );

        // Handle List Markers Visual Simulation
        // Word is bad at resuming visual lists without semantic numbering.
        // But semantic numbering is hard to generate linearly.
        // We will inject a run with the bullet/number if it's the start of a list item.
        if (!p.isContinuation) {
          String? marker;
          if (p.type == ParagraphType.bulletList) {
            if (p.indent == 0) {
              marker = "•\t";
            } else if (p.indent == 1)
              marker = "◦\t";
            else
              marker = "▪\t";
          } else if (p.type == ParagraphType.numberedList) {
            // Replicate the logic from PDF/Editor
            marker = "${p.listIndex ?? 1}.\t";
            if (p.indent == 1) {
              int idx = (p.listIndex ?? 1) - 1;
              const letters = "abcdefghijklmnopqrstuvwxyz";
              if (idx >= 0 && idx < letters.length) {
                marker = "${letters[idx]}.\t";
              }
            } else if (p.indent >= 2) {
              final romans = [
                "i",
                "ii",
                "iii",
                "iv",
                "v",
                "vi",
                "vii",
                "viii",
                "ix",
                "x",
              ];
              int idx = (p.listIndex ?? 1) - 1;
              if (idx >= 0 && idx < romans.length) marker = "${romans[idx]}.\t";
            }
          }

          if (marker != null) {
            // Apply Hanging Indent for the marker to sit left?
            // Or just inline it. Inline is simpler but wrapping is ugly.
            // Let's just inline it for now.
            builder.element(
              'w:r',
              nest: () {
                builder.element(
                  'w:rPr',
                  nest: () {
                    // Force Courier or specific font for consistency?
                    // Or assume paragraph font.
                    builder.element('w:b'); // Make markers bold
                  },
                );
                builder.element(
                  'w:t',
                  attributes: {'xml:space': 'preserve'},
                  nest: () {
                    builder.text(marker!);
                  },
                );
              },
            );
          }
        }

        // Runs
        // If empty runs, ensure at least one run so line height is respected?
        // Or w:spacing handles it.
        if (p.runs.isEmpty ||
            (p.runs.length == 1 && p.runs.first.text.isEmpty)) {
          // Empty paragraph, maybe just a break?
          // We rely on w:spacing to give it height.
        }

        for (var run in p.runs) {
          builder.element(
            'w:r',
            nest: () {
              builder.element(
                'w:rPr',
                nest: () {
                  if (run.attributes.fontFamily != null) {
                    builder.element(
                      'w:rFonts',
                      attributes: {
                        'w:ascii': run.attributes.fontFamily!,
                        'w:hAnsi': run.attributes.fontFamily!,
                      },
                    );
                  }
                  if (run.attributes.bold) builder.element('w:b');
                  if (run.attributes.italic) builder.element('w:i');
                  if (run.attributes.underline) {
                    builder.element('w:u', attributes: {'w:val': 'single'});
                  }
                  if (run.attributes.strikethrough) builder.element('w:strike');
                  if (run.attributes.fontSize != null) {
                    final sz = (run.attributes.fontSize! * 2)
                        .toInt()
                        .toString();
                    builder.element('w:sz', attributes: {'w:val': sz});
                    builder.element('w:szCs', attributes: {'w:val': sz});
                  }
                },
              );

              builder.element(
                'w:t',
                attributes: {'xml:space': 'preserve'},
                nest: () {
                  builder.text(run.text);
                },
              );
            },
          );
        }
      },
    ); // w:p
  }

  static void _buildTitlePage(
    XmlBuilder builder,
    Document document,
    EditorMode mode,
  ) {
    final title = document.metadata.title;
    final author = document.metadata.author;
    final isManuscript = mode == EditorMode.manuscript;
    final font = isManuscript
        ? PageConstants.manuscriptFont
        : PageConstants.screenplayFont;

    // Push down a bit (approx 1/3 of page)
    for (int i = 0; i < 15; i++) {
      builder.element('w:p');
    }

    // Title
    builder.element(
      'w:p',
      nest: () {
        builder.element(
          'w:pPr',
          nest: () {
            builder.element('w:jc', attributes: {'w:val': 'center'});
          },
        );
        builder.element(
          'w:r',
          nest: () {
            builder.element(
              'w:rPr',
              nest: () {
                builder.element(
                  'w:rFonts',
                  attributes: {'w:ascii': font, 'w:hAnsi': font},
                );
                builder.element('w:b');
                builder.element('w:sz', attributes: {'w:val': '36'}); // 18pt
              },
            );
            builder.element('w:t', nest: title.toUpperCase());
          },
        );
      },
    );

    // "by"
    builder.element(
      'w:p',
      nest: () {
        builder.element(
          'w:pPr',
          nest: () {
            builder.element('w:jc', attributes: {'w:val': 'center'});
          },
        );
        builder.element(
          'w:r',
          nest: () {
            builder.element(
              'w:rPr',
              nest: () {
                builder.element(
                  'w:rFonts',
                  attributes: {'w:ascii': font, 'w:hAnsi': font},
                );
                builder.element('w:sz', attributes: {'w:val': '24'}); // 12pt
              },
            );
            builder.element('w:t', nest: 'by');
          },
        );
      },
    );

    // Author
    builder.element(
      'w:p',
      nest: () {
        builder.element(
          'w:pPr',
          nest: () {
            builder.element('w:jc', attributes: {'w:val': 'center'});
          },
        );
        builder.element(
          'w:r',
          nest: () {
            builder.element(
              'w:rPr',
              nest: () {
                builder.element(
                  'w:rFonts',
                  attributes: {'w:ascii': font, 'w:hAnsi': font},
                );
                builder.element('w:sz', attributes: {'w:val': '28'}); // 14pt
              },
            );
            builder.element('w:t', nest: author);
          },
        );
      },
    );

    // Page Break
    builder.element(
      'w:p',
      nest: () {
        builder.element(
          'w:r',
          nest: () {
            builder.element('w:br', attributes: {'w:type': 'page'});
          },
        );
      },
    );
  }
}
