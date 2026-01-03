import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants.dart';
import '../logic/spell_checker.dart';
import '../models/document.dart';
import '../logic/editor_controller.dart' show SearchResult;

class EditorPage extends StatefulWidget {
  final List<Paragraph> paragraphs;
  final EdgeInsets margins;
  final int pageNumber;
  final bool showPageNumber;
  final int? cursorParagraphIndex;
  final int? cursorOffset;
  final int? selectionAnchorParagraphIndex;
  final int? selectionAnchorOffset;
  final int pageParagraphOffset;
  final Function(int paragraphIndex, int offset, bool extend)? onTap;
  final Function(int paragraphIndex, int offset)? onDoubleTap;
  final Function(int paragraphIndex, int offset, Offset globalPosition)?
  onSecondaryTap;
  final ValueChanged<Offset>? onCaretOffsetUpdated;
  final SpellChecker? spellChecker;
  final List<SearchResult> searchResults;
  final int currentSearchIndex;
  final double zoomLevel;
  final EditorMode editorMode;
  final DocumentMetadata metadata;

  const EditorPage({
    super.key,
    required this.paragraphs,
    required this.margins,
    required this.pageNumber,
    this.showPageNumber = true,
    this.cursorParagraphIndex,
    this.cursorOffset,
    this.selectionAnchorParagraphIndex,
    this.selectionAnchorOffset,
    this.pageParagraphOffset = 0,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.onCaretOffsetUpdated,
    this.spellChecker,
    this.searchResults = const [],
    this.currentSearchIndex = -1,
    this.zoomLevel = 1.0,
    required this.editorMode,
    required this.metadata,
  });

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  Offset? _lastTapLocalPosition;

  double _pixelLock(double value, double dpr, {bool forceCeil = false}) {
    final scale = (widget.zoomLevel == 0 ? 1.0 : widget.zoomLevel) * dpr;
    if (forceCeil) {
      return (value * scale).ceilToDouble() / scale;
    }
    return (value * scale).roundToDouble() / scale;
  }

  String _getFontForMode(EditorMode mode) {
    switch (mode) {
      case EditorMode.screenplay:
        return PageConstants.screenplayFont;
      case EditorMode.manuscript:
        return PageConstants.manuscriptFont;
      case EditorMode.essay:
        return PageConstants.essayFont;
      case EditorMode.freestyle:
        return PageConstants.freestyleFont;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final lockedTopMargin = _pixelLock(widget.margins.top, dpr);
    final lockedLeftMargin = _pixelLock(widget.margins.left, dpr);

    Offset? caretOffset;
    double caretHeight = 12.0;

    int? activeRelativeIdx;
    int activeLocalOffset = 0;

    if (widget.cursorParagraphIndex != null && widget.cursorOffset != null) {
      for (int i = 0; i < widget.paragraphs.length; i++) {
        final pp = widget.paragraphs[i];
        if (pp.originalIndex == widget.cursorParagraphIndex) {
          int pLen = 0;
          for (var r in pp.runs) {
            pLen += r.text.length;
          }
          final start = pp.offsetInOriginal;
          final end = start + pLen;

          if (widget.cursorOffset! >= start && widget.cursorOffset! <= end) {
            activeRelativeIdx = i;
            activeLocalOffset = widget.cursorOffset! - start;
            break;
          }
        }
      }
    }

    final lockedWidth = _pixelLock(
      PageConstants.pageWidth - widget.margins.left - widget.margins.right,
      dpr,
      forceCeil: true,
    );

    if (activeRelativeIdx != null) {
      final p = widget.paragraphs[activeRelativeIdx];

      double yOffset = 0;
      for (int i = 0; i < activeRelativeIdx; i++) {
        yOffset += _measureParagraphHeight(
          widget.paragraphs[i],
          lockedWidth,
          dpr,
        );
      }

      final structuralLeftOffset = p.structuralLeftOffset;
      final textPainter = p.buildPainter(
        maxWidth: lockedWidth - structuralLeftOffset,
        defaultFontFamily: _getFontForMode(widget.editorMode),
      );

      // Use a consistent height for the caret (font size) and center it
      double effectiveFontSize = 12.0;
      if (p.runs.isNotEmpty) {
        int offset = 0;
        for (var run in p.runs) {
          if (activeLocalOffset >= offset &&
              activeLocalOffset <= offset + run.text.length) {
            effectiveFontSize = run.attributes.fontSize ?? 12.0;
            break;
          }
          offset += run.text.length;
        }
      }

      caretHeight = effectiveFontSize;
      final double verticalCenteringOffset =
          (p.lineSpacing - 1.0) * effectiveFontSize / 2.0;

      final pos = textPainter.getOffsetForCaret(
        TextPosition(offset: activeLocalOffset),
        Rect.zero,
      );

      caretOffset = Offset(
        _pixelLock(pos.dx + lockedLeftMargin + structuralLeftOffset, dpr),
        _pixelLock(
          pos.dy + lockedTopMargin + yOffset + verticalCenteringOffset,
          dpr,
        ),
      );
    }

    if (caretOffset != null && widget.onCaretOffsetUpdated != null) {
      final offset = caretOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Check if mounted to avoid errors if widget disposed
        if (mounted) {
          widget.onCaretOffsetUpdated!(offset);
        }
      });
    }

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: SizedBox(
        width: PageConstants.pageWidth,
        height: PageConstants.pageHeight,
        child: GestureDetector(
          onTapDown: (details) {
            _lastTapLocalPosition = details.localPosition;
            if (widget.onTap != null) {
              final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
              _handleTap(details.localPosition, isShiftPressed);
            }
          },
          onDoubleTapDown: (details) {
            _lastTapLocalPosition = details.localPosition;
          },
          onDoubleTap: () {
            if (widget.onDoubleTap != null && _lastTapLocalPosition != null) {
              _handleDoubleTap(_lastTapLocalPosition!);
            }
          },
          onSecondaryTapDown: (details) {
            if (widget.onSecondaryTap != null) {
              _handleSecondaryTap(
                details.localPosition,
                details.globalPosition,
              );
            }
          },
          onPanStart: (details) {
            if (widget.onTap != null) {
              _handleTap(details.localPosition, false);
            }
          },
          onPanUpdate: (details) {
            if (widget.onTap != null) {
              _handleTap(details.localPosition, true);
            }
          },
          child: Container(
            width: PageConstants.pageWidth,
            height: PageConstants.pageHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              children: [
                // Paginated Content with Margins
                Padding(
                  padding: EdgeInsets.only(
                    top: lockedTopMargin,
                    left: lockedLeftMargin,
                    bottom: _pixelLock(widget.margins.bottom, dpr),
                    right: _pixelLock(widget.margins.right, dpr),
                  ),
                  child: OverflowBox(
                    maxHeight: double.infinity,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: lockedWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: widget.paragraphs.indexed.map((entry) {
                          final idx = entry.$1;
                          final p = entry.$2;

                          // Selection logic per paragraph
                          int? selStart;
                          int? selEnd;

                          if (widget.selectionAnchorParagraphIndex != null &&
                              widget.selectionAnchorOffset != null &&
                              widget.cursorParagraphIndex != null &&
                              widget.cursorOffset != null) {
                            final anchorGlobalIdx =
                                widget.selectionAnchorParagraphIndex!;
                            final cursorGlobalIdx =
                                widget.cursorParagraphIndex!;

                            final startP = anchorGlobalIdx < cursorGlobalIdx
                                ? anchorGlobalIdx
                                : cursorGlobalIdx;
                            final endP = anchorGlobalIdx > cursorGlobalIdx
                                ? anchorGlobalIdx
                                : cursorGlobalIdx;

                            final globalIdx =
                                p.originalIndex ??
                                (widget.pageParagraphOffset + idx);

                            if (globalIdx >= startP && globalIdx <= endP) {
                              int pLength = 0;
                              for (var r in p.runs) {
                                pLength += r.text.length;
                              }

                              // Calculate raw start/end offsets for this paragraph
                              int localStart = 0;
                              int localEnd = pLength;

                              if (globalIdx == startP) {
                                int anchor = (startP == anchorGlobalIdx)
                                    ? widget.selectionAnchorOffset!
                                    : widget.cursorOffset!;
                                localStart = anchor;
                              }

                              if (globalIdx == endP) {
                                int cursor = (endP == cursorGlobalIdx)
                                    ? widget.cursorOffset!
                                    : widget.selectionAnchorOffset!;
                                localEnd = cursor;
                              }

                              // Ensure start <= end for valid range
                              if (startP == endP) {
                                // Single paragraph selection: must handle swapped anchor/cursor
                                int a = widget.selectionAnchorOffset!;
                                int c = widget.cursorOffset!;
                                selStart = a < c ? a : c;
                                selEnd = a > c ? a : c;
                              } else {
                                // Multi-paragraph: localStart/localEnd are already correct relative to p bounds
                                selStart = localStart;
                                selEnd = localEnd;
                              }
                            }
                          }

                          bool connectsToNext = false;
                          if (p.type == ParagraphType.blockquote &&
                              idx < widget.paragraphs.length - 1) {
                            if (widget.paragraphs[idx + 1].type ==
                                ParagraphType.blockquote) {
                              connectsToNext = true;
                            }
                          }

                          return _buildParagraph(
                            p,
                            p.originalIndex ??
                                (widget.pageParagraphOffset + idx),
                            lockedWidth,
                            dpr,
                            selStart: selStart,
                            selEnd: selEnd,
                            connectsToNext: connectsToNext,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),

                // Caret
                if (caretOffset != null && widget.selectionAnchorOffset == null)
                  Positioned(
                    left: caretOffset.dx,
                    top: caretOffset.dy,
                    child: BlinkingCaret(height: caretHeight),
                  ),

                // Page Number
                if (widget.showPageNumber) _buildPageNumber(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleTap(Offset localPosition, bool extendSelection) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final lockedTopMargin = _pixelLock(widget.margins.top, dpr);
    final lockedLeftMargin = _pixelLock(widget.margins.left, dpr);
    final lockedWidth = _pixelLock(
      PageConstants.pageWidth - widget.margins.left - widget.margins.right,
      dpr,
      forceCeil: true,
    );
    double y = localPosition.dy - lockedTopMargin;
    if (y < 0) {
      widget.onTap!(widget.pageParagraphOffset, 0, extendSelection);
      return;
    }
    double currentY = 0;

    for (int i = 0; i < widget.paragraphs.length; i++) {
      final p = widget.paragraphs[i];
      final pHeight = _measureParagraphHeight(p, lockedWidth, dpr);

      if (y >= currentY && y < currentY + pHeight) {
        final structuralLeftOffset = p.structuralLeftOffset;
        final offset = _getOffsetForPosition(
          p,
          lockedWidth - structuralLeftOffset,
          Offset(
            localPosition.dx - lockedLeftMargin - structuralLeftOffset - 4.0,
            y - currentY,
          ),
        );
        final globalPIdx = p.originalIndex ?? (widget.pageParagraphOffset + i);
        final finalOffset = p.offsetInOriginal + offset;
        widget.onTap!(globalPIdx, finalOffset, extendSelection);
        return;
      }
      currentY += pHeight;
    }

    if (widget.paragraphs.isNotEmpty) {
      final lastP = widget.paragraphs.last;
      int lastOffset = 0;
      for (var r in lastP.runs) {
        lastOffset += r.text.length;
      }
      final globalPIdx =
          lastP.originalIndex ??
          (widget.pageParagraphOffset + widget.paragraphs.length - 1);
      final finalOffset = lastP.offsetInOriginal + lastOffset;
      widget.onTap!(globalPIdx, finalOffset, extendSelection);
    }
  }

  void _handleDoubleTap(Offset localPosition) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final lockedTopMargin = _pixelLock(widget.margins.top, dpr);
    final lockedLeftMargin = _pixelLock(widget.margins.left, dpr);
    final lockedWidth = _pixelLock(
      PageConstants.pageWidth - widget.margins.left - widget.margins.right,
      dpr,
      forceCeil: true,
    );
    double y = localPosition.dy - lockedTopMargin;
    if (y < 0) return;
    double currentY = 0;

    for (int i = 0; i < widget.paragraphs.length; i++) {
      final p = widget.paragraphs[i];
      final pHeight = _measureParagraphHeight(p, lockedWidth, dpr);

      if (y >= currentY && y < currentY + pHeight) {
        final structuralLeftOffset = p.structuralLeftOffset;
        final offset = _getOffsetForPosition(
          p,
          lockedWidth - structuralLeftOffset,
          Offset(
            localPosition.dx - lockedLeftMargin - structuralLeftOffset - 4.0,
            y - currentY,
          ),
        );
        final globalPIdx = p.originalIndex ?? (widget.pageParagraphOffset + i);
        final finalOffset = p.offsetInOriginal + offset;
        widget.onDoubleTap!(globalPIdx, finalOffset);
        return;
      }
      currentY += pHeight;
    }
  }

  void _handleSecondaryTap(Offset localPosition, Offset globalPosition) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final lockedTopMargin = _pixelLock(widget.margins.top, dpr);
    final lockedLeftMargin = _pixelLock(widget.margins.left, dpr);
    final lockedWidth = _pixelLock(
      PageConstants.pageWidth - widget.margins.left - widget.margins.right,
      dpr,
      forceCeil: true,
    );
    double y = localPosition.dy - lockedTopMargin;
    if (y < 0) return;
    double currentY = 0;

    for (int i = 0; i < widget.paragraphs.length; i++) {
      final p = widget.paragraphs[i];
      final pHeight = _measureParagraphHeight(p, lockedWidth, dpr);

      if (y >= currentY && y < currentY + pHeight) {
        final structuralLeftOffset = p.structuralLeftOffset;
        final offset = _getOffsetForPosition(
          p,
          lockedWidth - structuralLeftOffset,
          Offset(
            localPosition.dx - lockedLeftMargin - structuralLeftOffset - 4.0,
            y - currentY,
          ),
        );
        final globalPIdx = p.originalIndex ?? (widget.pageParagraphOffset + i);
        final finalOffset = p.offsetInOriginal + offset;
        widget.onSecondaryTap!(globalPIdx, finalOffset, globalPosition);
        return;
      }
      currentY += pHeight;
    }
    // Handle tap outside any paragraph (e.g. bottom of page)
    if (widget.paragraphs.isNotEmpty) {
      final lastP = widget.paragraphs.last;
      int lastOffset = 0;
      for (var r in lastP.runs) {
        lastOffset += r.text.length;
      }
      final globalPIdx =
          lastP.originalIndex ??
          (widget.pageParagraphOffset + widget.paragraphs.length - 1);
      final finalOffset = lastP.offsetInOriginal + lastOffset;
      widget.onSecondaryTap!(globalPIdx, finalOffset, globalPosition);
    }
  }

  double _measureParagraphHeight(
    Paragraph paragraph,
    double width,
    double dpr,
  ) {
    if (paragraph.cachedHeight != null && paragraph.cachedWidth == width) {
      return paragraph.cachedHeight!;
    }
    final structuralLeftOffset = paragraph.structuralLeftOffset;
    final textPainter = paragraph.buildPainter(
      maxWidth: width - structuralLeftOffset,
      defaultFontFamily: _getFontForMode(widget.editorMode),
    );
    final minLineHeight =
        (paragraph.runs.isNotEmpty
            ? (paragraph.runs.first.attributes.fontSize ?? 12.0)
            : 12.0) *
        paragraph.lineSpacing;
    final rawHeight = textPainter.height > minLineHeight
        ? textPainter.height
        : minLineHeight;
    return _pixelLock(rawHeight, dpr);
  }

  int _getOffsetForPosition(
    Paragraph paragraph,
    double width,
    Offset localOffset,
  ) {
    final textPainter = paragraph.buildPainter(
      maxWidth: width,
      defaultFontFamily: _getFontForMode(widget.editorMode),
    );
    return textPainter.getPositionForOffset(localOffset).offset;
  }

  TextAlign _getParagraphTextAlign(ParagraphAlignment alignment) {
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

  String? _getMarkerString(Paragraph p) {
    if (p.type == ParagraphType.bulletList) {
      if (p.indent == 0) {
        return "•";
      } else if (p.indent == 1) {
        return "◦";
      } else {
        return "▪";
      }
    } else if (p.type == ParagraphType.numberedList) {
      if (p.indent == 0) {
        return "${p.listIndex ?? 1}.";
      } else if (p.indent == 1) {
        int idx = (p.listIndex ?? 1) - 1;
        const letters = "abcdefghijklmnopqrstuvwxyz";
        if (idx >= 0 && idx < letters.length) {
          return "${letters[idx]}.";
        }
      } else {
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
        if (idx >= 0 && idx < romans.length) {
          return "${romans[idx]}.";
        }
      }
    }
    return null;
  }

  Widget _buildParagraph(
    Paragraph p,
    int globalPIdx,
    double width,
    double dpr, {
    int? selStart,
    int? selEnd,
    bool connectsToNext = false,
  }) {
    final List<InlineSpan> spans = [];
    int currentOffset = 0;

    final pMatches = widget.searchResults
        .where((r) => r.paragraphIndex == globalPIdx)
        .toList();

    for (var run in p.runs) {
      final runTextStyle = run.attributes.toTextStyle(
        height: p.lineSpacing,
        includeMonospaceBackground: p.type != ParagraphType.codeBlock,
        defaultFontFamily: _getFontForMode(widget.editorMode),
      );
      final runLen = run.text.length;
      final runEnd = currentOffset + runLen;

      final runHighlights = <HighlightSpan>[];
      for (var m in pMatches) {
        final mStart = m.range.start;
        final mEnd = m.range.end;
        if (mStart < runEnd && mEnd > currentOffset) {
          runHighlights.add(
            HighlightSpan(
              start: (mStart - currentOffset).clamp(0, runLen),
              end: (mEnd - currentOffset).clamp(0, runLen),
              isSearch: true,
              isActive: m == widget.searchResults[widget.currentSearchIndex],
            ),
          );
        }
      }

      spans.add(
        _buildStyledSpan(
          run.text,
          runTextStyle,
          selStart,
          selEnd,
          currentOffset,
          widget.spellChecker,
          runHighlights,
        ),
      );
      currentOffset += runLen;
    }

    final String? firstFontFamily = p.runs.isNotEmpty
        ? p.runs.first.attributes.fontFamily
        : _getFontForMode(widget.editorMode);
    Widget paragraphWidget = RichText(
      textAlign: _getParagraphTextAlign(p.alignment),
      text: TextSpan(
        children: spans,
        style: TextStyle(
          color: Colors.black,
          height: p.lineSpacing,
          fontFamily: firstFontFamily,
          fontSize: 12.0,
        ),
      ),
      strutStyle: StrutStyle(
        fontFamily: firstFontFamily,
        fontSize: p.runs.isNotEmpty
            ? p.runs.first.attributes.fontSize ?? 12.0
            : 12.0,
        height: p.lineSpacing,
        forceStrutHeight: true,
      ),
    );

    final bottomPadding = EdgeInsets.zero;

    if (p.type == ParagraphType.blockquote ||
        p.type == ParagraphType.codeBlock) {
      final bool isCode = p.type == ParagraphType.codeBlock;
      final decoration = BoxDecoration(
        color: isCode ? Colors.brown.withValues(alpha: 0.1) : null,
        border: Border(
          left: BorderSide(
            color: isCode ? Colors.brown.withValues(alpha: 0.5) : Colors.grey,
            width: 4.0,
          ),
        ),
      );

      if (connectsToNext) {
        paragraphWidget = Container(
          decoration: decoration,
          padding: const EdgeInsets.only(left: 16.0),
          child: Padding(padding: bottomPadding, child: paragraphWidget),
        );
      } else {
        paragraphWidget = Padding(
          padding: bottomPadding,
          child: Container(
            decoration: decoration,
            padding: const EdgeInsets.only(left: 16.0),
            child: paragraphWidget,
          ),
        );
      }
    } else if (p.type == ParagraphType.bulletList ||
        p.type == ParagraphType.numberedList) {
      final markerStr = p.isContinuation ? null : _getMarkerString(p);
      final String? firstFontFamily = p.runs.isNotEmpty
          ? p.runs.first.attributes.fontFamily
          : _getFontForMode(widget.editorMode);

      final markerStyle =
          (p.runs.isNotEmpty
                  ? p.runs.first.attributes.toTextStyle(
                      height: p.lineSpacing,
                      defaultFontFamily: _getFontForMode(widget.editorMode),
                    )
                  : TextStyle(
                      fontSize: 12.0,
                      fontFamily: _getFontForMode(widget.editorMode),
                    ))
              .copyWith(fontWeight: FontWeight.bold, color: Colors.black);

      final markerWidget = markerStr != null
          ? RichText(
              textAlign: TextAlign.end,
              text: TextSpan(
                text: markerStr,
                style: markerStyle.copyWith(
                  height: p.lineSpacing,
                  fontFamily: firstFontFamily,
                  fontSize: 12.0,
                ),
              ),
              strutStyle: StrutStyle(
                fontFamily: firstFontFamily,
                fontSize: p.runs.isNotEmpty
                    ? p.runs.first.attributes.fontSize ?? 12.0
                    : 12.0,
                height: p.lineSpacing,
                forceStrutHeight: true,
              ),
            )
          : const SizedBox.shrink();

      paragraphWidget = Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(width: 24.0 * p.indent),
          SizedBox(
            width: 32.0,
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: markerWidget,
            ),
          ),
          Expanded(child: paragraphWidget),
        ],
      );
    } else if (p.type == ParagraphType.horizontalRule) {
      final minLineHeight =
          (p.runs.isNotEmpty
              ? (p.runs.first.attributes.fontSize ?? 12.0)
              : 12.0) *
          p.lineSpacing;
      return SizedBox(
        height: minLineHeight,
        child: Center(
          child: Divider(
            color: Colors.grey.shade400,
            thickness: 1.0,
            height: 1.0,
            indent: 0,
            endIndent: 0,
          ),
        ),
      );
    }

    final pHeight = _measureParagraphHeight(p, width, dpr);

    return Padding(
      padding: bottomPadding,
      child: SizedBox(width: width, height: pHeight, child: paragraphWidget),
    );
  }

  InlineSpan _buildStyledSpan(
    String text,
    TextStyle baseStyle,
    int? selStart,
    int? selEnd,
    int spanStartOffset,
    SpellChecker? spellChecker, [
    List<HighlightSpan>? highlights,
  ]) {
    if (selStart == null || selEnd == null) {
      return TextSpan(
        children: _buildSpansWithHighlights(
          text,
          baseStyle,
          spellChecker,
          highlights ?? [],
        ),
      );
    }

    int spanEndOffset = spanStartOffset + text.length;
    if (spanEndOffset <= selStart || spanStartOffset >= selEnd) {
      return TextSpan(
        children: _buildSpansWithHighlights(
          text,
          baseStyle,
          spellChecker,
          highlights ?? [],
        ),
      );
    }

    List<HighlightSpan> sliceHighlights(int relativeStart, int relativeEnd) {
      if (highlights == null) return [];
      return highlights
          .where((h) => h.start < relativeEnd && h.end > relativeStart)
          .map(
            (h) => HighlightSpan(
              start: (h.start - relativeStart).clamp(
                0,
                relativeEnd - relativeStart,
              ),
              end: (h.end - relativeStart).clamp(
                0,
                relativeEnd - relativeStart,
              ),
              isSearch: h.isSearch,
              isActive: h.isActive,
            ),
          )
          .toList();
    }

    final List<InlineSpan> textParts = [];
    final textLength = text.length;

    final currentSpanSelStart = (selStart - spanStartOffset).clamp(
      0,
      textLength,
    );
    final currentSpanSelEnd = (selEnd - spanStartOffset).clamp(0, textLength);

    if (currentSpanSelStart > 0) {
      textParts.addAll(
        _buildSpansWithHighlights(
          text.substring(0, currentSpanSelStart),
          baseStyle,
          spellChecker,
          sliceHighlights(0, currentSpanSelStart),
        ),
      );
    }

    if (currentSpanSelEnd > currentSpanSelStart) {
      textParts.addAll(
        _buildSpansWithHighlights(
          text.substring(currentSpanSelStart, currentSpanSelEnd),
          baseStyle.copyWith(
            backgroundColor: Colors.blue.withValues(alpha: 0.3),
          ),
          null,
          sliceHighlights(currentSpanSelStart, currentSpanSelEnd),
        ),
      );
    }

    if (currentSpanSelEnd < textLength) {
      textParts.addAll(
        _buildSpansWithHighlights(
          text.substring(currentSpanSelEnd),
          baseStyle,
          spellChecker,
          sliceHighlights(currentSpanSelEnd, textLength),
        ),
      );
    }

    return TextSpan(children: textParts);
  }

  List<InlineSpan> _buildSpansWithHighlights(
    String text,
    TextStyle style,
    SpellChecker? spellChecker,
    List<HighlightSpan> highlights,
  ) {
    final List<HighlightSpan> allHighlights = [...highlights];

    if (spellChecker != null && spellChecker.isLoaded) {
      final spellRanges = spellChecker.findMisspelledWords(text);
      for (var r in spellRanges) {
        allHighlights.add(
          HighlightSpan(
            start: r.start,
            end: r.end,
            isSearch: false,
            isActive: false,
          ),
        );
      }
    }

    if (allHighlights.isEmpty) {
      return [TextSpan(text: text, style: style)];
    }

    final Set<int> boundaries = {0, text.length};
    for (var h in allHighlights) {
      boundaries.add(h.start.clamp(0, text.length));
      boundaries.add(h.end.clamp(0, text.length));
    }
    final sortedBoundaries = boundaries.toList()..sort();

    final List<InlineSpan> spans = [];

    for (int i = 0; i < sortedBoundaries.length - 1; i++) {
      final start = sortedBoundaries[i];
      final end = sortedBoundaries[i + 1];
      if (start >= end) continue;

      final segmentText = text.substring(start, end);
      var segmentStyle = style;

      bool isMisspelled = false;
      bool isSearchMatch = false;
      bool isActiveMatch = false;

      for (var h in allHighlights) {
        if (h.start <= start && h.end >= end) {
          if (h.isSearch) {
            isSearchMatch = true;
            if (h.isActive) isActiveMatch = true;
          } else {
            isMisspelled = true;
          }
        }
      }

      if (isSearchMatch) {
        segmentStyle = segmentStyle.copyWith(
          backgroundColor: isActiveMatch
              ? Colors.orange.withValues(alpha: 0.5)
              : Colors.yellow.withValues(alpha: 0.5),
        );
      }

      if (isMisspelled) {
        segmentStyle = segmentStyle.copyWith(
          decoration: TextDecoration.combine([
            if (segmentStyle.decoration != null) segmentStyle.decoration!,
            TextDecoration.underline,
          ]),
          decorationStyle: TextDecorationStyle.wavy,
          decorationColor: Colors.red,
        );
      }

      if (segmentText.contains('\t')) {
        final parts = segmentText.split('\t');
        final spaceTp = TextPainter(
          text: TextSpan(text: '    ', style: segmentStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final tabWidth = spaceTp.width;
        final h =
            (segmentStyle.fontSize ?? 12.0) * (segmentStyle.height ?? 1.0);

        for (int j = 0; j < parts.length; j++) {
          if (parts[j].isNotEmpty) {
            spans.add(TextSpan(text: parts[j], style: segmentStyle));
          }
          if (j < parts.length - 1) {
            spans.add(
              WidgetSpan(
                child: SizedBox(width: tabWidth, height: h),
                baseline: TextBaseline.alphabetic,
                alignment: PlaceholderAlignment.baseline,
              ),
            );
          }
        }
      } else {
        spans.add(TextSpan(text: segmentText, style: segmentStyle));
      }
    }
    return spans;
  }

  Widget _buildPageNumber(BuildContext context) {
    String pageText = "";
    String fontFamily = "Courier Prime";

    switch (widget.editorMode) {
      case EditorMode.screenplay:
        if (widget.pageNumber > 1) {
          pageText = "${widget.pageNumber}.";
        }
        fontFamily = "Courier Prime";
        break;
      case EditorMode.manuscript:
        final author = widget.metadata.author;
        pageText =
            "${author.isNotEmpty ? "$author / " : ""}${widget.pageNumber}";
        fontFamily = "Tinos";
        break;
      case EditorMode.essay:
        pageText = "${widget.pageNumber}";
        fontFamily = "Tinos";
        break;
      case EditorMode.freestyle:
        pageText = "${widget.pageNumber}";
        fontFamily = PageConstants.freestyleFont;
        break;
    }

    if (pageText.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 0.5 * 72.0, // 0.5" from top edge of page
      right: 0.5 * 72.0, // 0.5" from right edge of page
      child: Text(
        pageText,
        style: TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontFamily: fontFamily,
        ),
      ),
    );
  }
}

class BlinkingCaret extends StatefulWidget {
  final double height;
  const BlinkingCaret({super.key, required this.height});

  @override
  State<BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<BlinkingCaret> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          _visible = !_visible;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2.0,
      height: widget.height,
      color: _visible ? Colors.black : Colors.transparent,
    );
  }
}

class HighlightSpan {
  final int start;
  final int end;
  final bool isSearch;
  final bool isActive;

  HighlightSpan({
    required this.start,
    required this.end,
    required this.isSearch,
    required this.isActive,
  });
}
