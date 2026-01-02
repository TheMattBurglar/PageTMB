import 'package:flutter/services.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/document.dart';
import 'paginator.dart';

class PdfExporter {
  static Future<Uint8List> generatePdf(
    Document document,
    EdgeInsets margins,
    String modeName,
  ) async {
    final pdf = pw.Document();

    // Load fonts
    final courierPrimeRegular = await _loadFont(
      'Fonts/Courier_Prime/CourierPrime-Regular.ttf',
    );
    final courierPrimeBold = await _loadFont(
      'Fonts/Courier_Prime/CourierPrime-Bold.ttf',
    );
    final courierPrimeItalic = await _loadFont(
      'Fonts/Courier_Prime/CourierPrime-Italic.ttf',
    );
    final courierPrimeBoldItalic = await _loadFont(
      'Fonts/Courier_Prime/CourierPrime-BoldItalic.ttf',
    );

    final tinosRegular = await _loadFont('Fonts/Tinos/Tinos-Regular.ttf');
    final tinosBold = await _loadFont('Fonts/Tinos/Tinos-Bold.ttf');
    final tinosItalic = await _loadFont('Fonts/Tinos/Tinos-Italic.ttf');
    final tinosBoldItalic = await _loadFont('Fonts/Tinos/Tinos-BoldItalic.ttf');

    final ebGaramondRegular = await _loadFont(
      'Fonts/EB_Garamond/static/EBGaramond-Regular.ttf',
    );
    final ebGaramondBold = await _loadFont(
      'Fonts/EB_Garamond/static/EBGaramond-Bold.ttf',
    );
    final ebGaramondItalic = await _loadFont(
      'Fonts/EB_Garamond/static/EBGaramond-Italic.ttf',
    );
    final ebGaramondBoldItalic = await _loadFont(
      'Fonts/EB_Garamond/static/EBGaramond-BoldItalic.ttf',
    );

    final arimoRegular = await _loadFont(
      'Fonts/Arimo/static/Arimo-Regular.ttf',
    );
    final arimoBold = await _loadFont('Fonts/Arimo/static/Arimo-Bold.ttf');
    final arimoItalic = await _loadFont('Fonts/Arimo/static/Arimo-Italic.ttf');
    final arimoBoldItalic = await _loadFont(
      'Fonts/Arimo/static/Arimo-BoldItalic.ttf',
    );

    final playfairRegular = await _loadFont(
      'Fonts/Playfair_Display/static/PlayfairDisplay-Regular.ttf',
    );
    final playfairBold = await _loadFont(
      'Fonts/Playfair_Display/static/PlayfairDisplay-Bold.ttf',
    );
    final playfairItalic = await _loadFont(
      'Fonts/Playfair_Display/static/PlayfairDisplay-Italic.ttf',
    );
    final playfairBoldItalic = await _loadFont(
      'Fonts/Playfair_Display/static/PlayfairDisplay-BoldItalic.ttf',
    );

    final carlitoRegular = await _loadFont('Fonts/Carlito/Carlito-Regular.ttf');
    final carlitoBold = await _loadFont('Fonts/Carlito/Carlito-Bold.ttf');
    final carlitoItalic = await _loadFont('Fonts/Carlito/Carlito-Italic.ttf');
    final carlitoBoldItalic = await _loadFont(
      'Fonts/Carlito/Carlito-BoldItalic.ttf',
    );

    final Map<String, _FontFamily> fonts = {
      'Courier Prime': _FontFamily(
        regular: courierPrimeRegular,
        bold: courierPrimeBold,
        italic: courierPrimeItalic,
        boldItalic: courierPrimeBoldItalic,
      ),
      'Tinos': _FontFamily(
        regular: tinosRegular,
        bold: tinosBold,
        italic: tinosItalic,
        boldItalic: tinosBoldItalic,
      ),
      'EB Garamond': _FontFamily(
        regular: ebGaramondRegular,
        bold: ebGaramondBold,
        italic: ebGaramondItalic,
        boldItalic: ebGaramondBoldItalic,
      ),
      'Arimo': _FontFamily(
        regular: arimoRegular,
        bold: arimoBold,
        italic: arimoItalic,
        boldItalic: arimoBoldItalic,
      ),
      'Playfair Display': _FontFamily(
        regular: playfairRegular,
        bold: playfairBold,
        italic: playfairItalic,
        boldItalic: playfairBoldItalic,
      ),
      'Carlito': _FontFamily(
        regular: carlitoRegular,
        bold: carlitoBold,
        italic: carlitoItalic,
        boldItalic: carlitoBoldItalic,
      ),
    };

    final pages = Paginator.paginate(document, margins);

    // Inject Title Page if needed
    if (modeName.toLowerCase() == 'screenplay' ||
        modeName.toLowerCase() == 'manuscript') {
      _addTitlePage(pdf, document, fonts, modeName);
    }

    for (int i = 0; i < pages.length; i++) {
      final pageParagraphs = pages[i];
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            final pageNumber = i + 1;
            String pageText = "";
            pw.Font pageFont = fonts['Courier Prime']!.regular;

            switch (modeName.toLowerCase()) {
              case 'screenplay':
                if (pageNumber > 1) {
                  pageText = "$pageNumber.";
                }
                pageFont = fonts['Courier Prime']!.regular;
                break;
              case 'manuscript':
                final author = document.metadata.author;
                pageText =
                    "${author.isNotEmpty ? "$author / " : ""}$pageNumber";
                pageFont = fonts['Tinos']!.regular;
                break;
              case 'essay':
                pageText = "$pageNumber";
                pageFont = fonts['Tinos']!.regular;
                break;
              default:
                pageText = "$pageNumber";
                pageFont = fonts['Arimo']!.regular;
                break;
            }

            return pw.Stack(
              children: [
                pw.Padding(
                  padding: pw.EdgeInsets.fromLTRB(
                    margins.left,
                    margins.top,
                    margins.right,
                    margins.bottom,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      ...pageParagraphs.map(
                        (p) => _buildPdfParagraph(p, fonts, modeName),
                      ),
                    ],
                  ),
                ),
                if (pageText.isNotEmpty)
                  pw.Positioned(
                    top: 0.5 * 72.0, // 0.5" from top
                    right: 0.5 * 72.0, // 0.5" from right
                    child: pw.Text(
                      pageText,
                      style: pw.TextStyle(font: pageFont, fontSize: 12),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  static Future<pw.Font> _loadFont(String path) async {
    return pw.Font.ttf(await rootBundle.load(path));
  }

  static pw.Widget _buildPdfParagraph(
    Paragraph p,
    Map<String, _FontFamily> fonts,
    String modeName,
  ) {
    if (p.runs.isEmpty || (p.runs.isEmpty && p.type == ParagraphType.normal)) {
      // For truly empty paragraphs, use a single line height
      return pw.SizedBox(height: 12.0 * p.lineSpacing);
    }

    final children = <pw.InlineSpan>[];

    // Check if it's a list item to add marker
    pw.Widget? markerWidget;

    final markerStyle = _getPdfTextStyle(
      p.runs.isNotEmpty ? p.runs.first.attributes : const TextAttributes(),
      fonts,
      p.lineSpacing,
      modeName,
    ).copyWith(fontWeight: pw.FontWeight.bold);

    if (p.type == ParagraphType.bulletList) {
      if (p.indent == 0) {
        // Main bullet: "•" usually works, but can also be drawn. Let's stick to text if it works,
        // or draw fill circle. User only complained about nested.
        // But for consistency let's draw a filled circle.
        markerWidget = pw.Padding(
          padding: const pw.EdgeInsets.only(top: 5.0),
          child: pw.Container(
            width: 4,
            height: 4,
            decoration: const pw.BoxDecoration(
              color: PdfColors.black,
              shape: pw.BoxShape.circle,
            ),
          ),
        );
      } else if (p.indent == 1) {
        // Hollow bullet
        markerWidget = pw.Padding(
          padding: const pw.EdgeInsets.only(top: 5.0),
          child: pw.Container(
            width: 4,
            height: 4,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1),
              shape: pw.BoxShape.circle,
            ),
          ),
        );
      } else {
        // Square bullet
        markerWidget = pw.Padding(
          padding: const pw.EdgeInsets.only(top: 5.0),
          child: pw.Container(width: 4, height: 4, color: PdfColors.black),
        );
      }

      // Wrap it to align right in the marker box
      markerWidget = pw.Align(
        alignment: pw.Alignment.topRight,
        child: markerWidget,
      );
    } else if (p.type == ParagraphType.numberedList) {
      String markerText = "${p.listIndex ?? 1}.";
      if (p.indent == 1) {
        int idx = (p.listIndex ?? 1) - 1;
        const letters = "abcdefghijklmnopqrstuvwxyz";
        if (idx >= 0 && idx < letters.length) markerText = "${letters[idx]}.";
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
        if (idx >= 0 && idx < romans.length) markerText = "${romans[idx]}.";
      }

      markerWidget = pw.Text(
        markerText,
        style: markerStyle,
        textAlign: pw.TextAlign.right,
      );
    }

    // ... (runs processing)

    for (var run in p.runs) {
      children.add(
        pw.TextSpan(
          text: run.text,
          style: _getPdfTextStyle(
            run.attributes,
            fonts,
            p.lineSpacing,
            modeName,
          ),
        ),
      );
    }

    final baseStyle = _getPdfTextStyle(
      p.runs.isNotEmpty ? p.runs.first.attributes : const TextAttributes(),
      fonts,
      p.lineSpacing,
      modeName,
    );

    pw.Widget paragraphWidget;
    // If only one run and it's empty, we still want it to take up space
    if (p.runs.length == 1 && p.runs.first.text.isEmpty) {
      paragraphWidget = pw.SizedBox(
        height: (baseStyle.fontSize ?? 12.0) * p.lineSpacing,
      );
    } else {
      paragraphWidget = pw.RichText(
        textAlign: _getPdfTextAlign(p.alignment),
        text: pw.TextSpan(style: baseStyle, children: children),
      );
    }

    if (p.type == ParagraphType.blockquote) {
      paragraphWidget = pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            left: pw.BorderSide(color: PdfColors.grey, width: 2.0),
          ),
        ),
        padding: const pw.EdgeInsets.only(left: 16.0),
        child: paragraphWidget,
      );
    } else if (markerWidget != null && !p.isContinuation) {
      paragraphWidget = pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 24.0 * p.indent),
          pw.SizedBox(width: 32.0, child: markerWidget),
          pw.SizedBox(width: 8.0),
          pw.Expanded(child: paragraphWidget),
        ],
      );
    }

    return pw.Padding(padding: pw.EdgeInsets.zero, child: paragraphWidget);
  }

  static pw.TextStyle _getPdfTextStyle(
    TextAttributes attrs,
    Map<String, _FontFamily> fonts,
    double lineSpacing,
    String modeName,
  ) {
    String defaultFamily;
    switch (modeName.toLowerCase()) {
      case 'screenplay':
        defaultFamily = 'Courier Prime';
        break;
      case 'manuscript':
      case 'essay':
        defaultFamily = 'Tinos';
        break;
      default:
        defaultFamily = 'Arimo';
    }

    final familyName = attrs.fontFamily ?? defaultFamily;
    final family = fonts[familyName] ?? fonts['Courier Prime']!;
    pw.Font font;
    if (attrs.bold && attrs.italic) {
      font = family.boldItalic;
    } else if (attrs.bold) {
      font = family.bold;
    } else if (attrs.italic) {
      font = family.italic;
    } else {
      font = family.regular;
    }

    return pw.TextStyle(
      font: font,
      fontSize: attrs.fontSize ?? 12,
      height: lineSpacing, // Match Flutter's height multiplier
      decoration: pw.TextDecoration.combine([
        if (attrs.underline) pw.TextDecoration.underline,
        if (attrs.strikethrough) pw.TextDecoration.lineThrough,
      ]),
    );
  }

  static pw.TextAlign _getPdfTextAlign(ParagraphAlignment alignment) {
    switch (alignment) {
      case ParagraphAlignment.left:
        return pw.TextAlign.left;
      case ParagraphAlignment.center:
        return pw.TextAlign.center;
      case ParagraphAlignment.right:
        return pw.TextAlign.right;
      case ParagraphAlignment.justify:
        return pw.TextAlign.justify;
    }
  }

  static void _addTitlePage(
    pw.Document pdf,
    Document document,
    Map<String, _FontFamily> fonts,
    String modeName,
  ) {
    final title = document.metadata.title;
    final author = document.metadata.author;
    final isManuscript = modeName.toLowerCase() == 'manuscript';
    final pageFont = isManuscript
        ? fonts['Tinos'] ?? fonts['Courier Prime']!
        : fonts['Courier Prime']!;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  title.toUpperCase(),
                  style: pw.TextStyle(font: pageFont.bold, fontSize: 18),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'by',
                  style: pw.TextStyle(font: pageFont.regular, fontSize: 12),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  author,
                  style: pw.TextStyle(font: pageFont.regular, fontSize: 14),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FontFamily {
  final pw.Font regular;
  final pw.Font bold;
  final pw.Font italic;
  final pw.Font boldItalic;

  _FontFamily({
    required this.regular,
    required this.bold,
    required this.italic,
    required this.boldItalic,
  });
}
