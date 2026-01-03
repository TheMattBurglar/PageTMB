import 'package:flutter/material.dart';
import '../models/document.dart';
import '../constants.dart';

class Paginator {
  static List<List<Paragraph>> paginate(
    Document document,
    EdgeInsets margins, {
    String? defaultFontFamily,
    double dpr = 1.0,
    double zoom = 1.0,
  }) {
    double pixelLock(double value, {bool forceCeil = false}) {
      final effectiveDpr = dpr * zoom;
      if (forceCeil) {
        return (value * effectiveDpr).ceilToDouble() / effectiveDpr;
      }
      return (value * effectiveDpr).roundToDouble() / effectiveDpr;
    }

    List<List<Paragraph>> pages = [[]];
    double currentHeight = 0;
    const double maxHeight = PageConstants.pageHeight;
    final double lockedTop = pixelLock(margins.top);
    final double lockedBottom = pixelLock(margins.bottom);
    final double availableHeight = maxHeight - lockedTop - lockedBottom;
    final double availableWidth = pixelLock(
      PageConstants.pageWidth - margins.left - margins.right,
      forceCeil: true,
    );

    for (int i = 0; i < document.paragraphs.length; i++) {
      Paragraph p = document.paragraphs[i].clone();
      p.originalIndex = i;
      p.isContinuation = false;

      while (true) {
        final double structuralOffset = p.structuralLeftOffset;
        final double maxWidth = availableWidth - pixelLock(structuralOffset);

        // Caching Logic
        double totalHeight;
        if (p.cachedHeight != null && p.cachedWidth == maxWidth) {
          totalHeight = p.cachedHeight!;
        } else {
          final textPainter = p.buildPainter(
            maxWidth: maxWidth,
            lineSpacing: p.lineSpacing,
            defaultFontFamily: defaultFontFamily,
          );

          final double paragraphGap = 0.0;
          final double minLineHeight =
              (p.runs.isNotEmpty
                  ? (p.runs.first.attributes.fontSize ?? 12.0)
                  : 12.0) *
              p.lineSpacing;

          totalHeight =
              (textPainter.height > minLineHeight
                  ? textPainter.height
                  : minLineHeight) +
              paragraphGap;

          // Write back to source paragraph (critical for persistence)
          // We need to access the original paragraph in the document, but 'p' here is a clone
          // created at the start of the loop (line 15).
          // Only cache if this is the full paragraph (not a continuation/remainder)
          if (!p.isContinuation) {
            document.paragraphs[i].cachedHeight = totalHeight;
            document.paragraphs[i].cachedWidth = maxWidth;
          }

          // Also update local clone for current logic
          p.cachedHeight = totalHeight;
          p.cachedWidth = maxWidth;
        }

        if (currentHeight + totalHeight <= availableHeight) {
          pages.last.add(p);
          currentHeight += totalHeight;
          break;
        } else {
          // If we are here, it means we didn't fit, so we need the textPainter to calculate split.
          // If we came from cache, we don't have textPainter!
          // So if we didn't fit and we used cache, we MUST now force a layout to handle the split.

          TextPainter textPainter;
          if (p.cachedHeight != null && p.cachedWidth == maxWidth) {
            textPainter = p.buildPainter(
              maxWidth: maxWidth,
              lineSpacing: p.lineSpacing,
              defaultFontFamily: defaultFontFamily,
            );
          } else {
            // We just measured it in the 'else' block above, but we didn't keep the painter variable in scope.
            // Efficiency trade-off: The case where a paragraph splits is rare (once per page).
            // Re-measuring here is acceptable to keep the code clean.
            // OR we can restructure to keep painter.
            textPainter = p.buildPainter(
              maxWidth: maxWidth,
              lineSpacing: p.lineSpacing,
              defaultFontFamily: defaultFontFamily,
            );
          }
          // Paragraph doesn't fit. Try to split it.
          final remainingSpace = availableHeight - currentHeight;

          // If available space is too small for even one line, skip to next page.
          // We use a safe/arbitrary min height check, or rely on metrics below.
          if (remainingSpace < 10.0 && pages.last.isNotEmpty) {
            pages.add([]);
            currentHeight = 0;
            continue;
          }

          final metrics = textPainter.computeLineMetrics();
          double usedHeight = 0.0;
          int lastFittingLineIndex = -1;

          for (int i = 0; i < metrics.length; i++) {
            final line = metrics[i];
            if (usedHeight + line.height <= remainingSpace + 0.5) {
              // 0.5 epsilon for float precision
              usedHeight += line.height;
              lastFittingLineIndex = i;
            } else {
              break;
            }
          }

          if (lastFittingLineIndex == -1) {
            // No lines fit.
            if (pages.last.isNotEmpty) {
              pages.add([]);
              currentHeight = 0;
              continue;
            } else {
              // Forced to fit at least one line if page is empty
              // But if it truly doesn't fit, we might just clip?
              // Standard behavior: Force at least one line or push.
              // If page is empty, we must take at least one line even if it clips,
              // or else infinite loop.
              lastFittingLineIndex = 0;
              usedHeight = metrics.isNotEmpty ? metrics[0].height : 0.0;
            }
          }

          // Use the end of the last fitting line as the split point
          // Query position at the bottom-right of the calculated usedHeight
          final splitPosition = textPainter.getPositionForOffset(
            Offset(availableWidth, usedHeight - 0.1),
          );
          final splitOffset = splitPosition.offset;

          final fullText = p.runs.map((r) => r.text).join();
          if (splitOffset <= 0 || splitOffset >= fullText.length) {
            // If splitOffset encompasses whole remaining text (e.g. slight rounding error),
            // just add the whole paragraph.
            if (splitOffset >= fullText.length) {
              pages.last.add(p);
              currentHeight += totalHeight;
              break;
            }
            // If 0, pushing entire p to next page
            if (pages.last.isNotEmpty) {
              pages.add([]);
              currentHeight = 0;
              continue;
            }
            // Should not happen if logic holds, but safe fallback
          }

          // Split the paragraph
          final parts = _splitParagraphAt(p, splitOffset);
          parts[0].cachedHeight =
              usedHeight; // Explicitly set height to what fits!
          parts[0].cachedWidth = availableWidth;

          pages.last.add(parts[0]);
          pages.add([]);
          currentHeight = 0;

          p = parts[1];
          p.isContinuation = true;
          // Continue loop with the rest of the paragraph
        }
      }
    }

    return pages;
  }

  static List<Paragraph> _splitParagraphAt(Paragraph p, int splitOffset) {
    List<TextRun> firstPartRuns = [];
    List<TextRun> secondPartRuns = [];
    int currentOffset = 0;

    for (var run in p.runs) {
      if (currentOffset + run.text.length <= splitOffset) {
        firstPartRuns.add(run.clone());
        currentOffset += run.text.length;
      } else if (currentOffset < splitOffset) {
        // Run needs to be split
        int localSplit = splitOffset - currentOffset;
        firstPartRuns.add(
          TextRun(
            text: run.text.substring(0, localSplit),
            attributes: run.attributes.clone(),
          ),
        );
        secondPartRuns.add(
          TextRun(
            text: run.text.substring(localSplit),
            attributes: run.attributes.clone(),
          ),
        );
        currentOffset += run.text.length;
      } else {
        secondPartRuns.add(run.clone());
        currentOffset += run.text.length;
      }
    }

    final p1 = Paragraph(
      runs: firstPartRuns,
      alignment: p.alignment,
      lineSpacing: p.lineSpacing,
      type: p.type,
      indent: p.indent,
      listIndex: p.listIndex,
      isContinuation: p.isContinuation,
    );

    final p2 = Paragraph(
      runs: secondPartRuns,
      alignment: p.alignment,
      lineSpacing: p.lineSpacing,
      type: p.type,
      indent: p.indent,
      listIndex: p.listIndex,
      isContinuation: true,
      originalIndex: p.originalIndex,
      offsetInOriginal: p.offsetInOriginal + splitOffset,
    );

    return [p1, p2];
  }
}
