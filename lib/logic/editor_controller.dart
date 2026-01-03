import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'spell_checker.dart';
import 'pdf_exporter.dart';
import 'docx_exporter.dart';
import 'markdown_exporter.dart';
import 'package:printing/printing.dart';
import '../models/document.dart';
import '../constants.dart';

class EditorStateSnapshot {
  final Document document;
  final int cursorParagraphIndex;
  final int cursorOffset;
  final int? selectionAnchorParagraphIndex;
  final int? selectionAnchorOffset;

  EditorStateSnapshot({
    required this.document,
    required this.cursorParagraphIndex,
    required this.cursorOffset,
    this.selectionAnchorParagraphIndex,
    this.selectionAnchorOffset,
  });
}

class SearchResult {
  final int paragraphIndex;
  final TextRange range;

  SearchResult(this.paragraphIndex, this.range);
}

class EditorController extends ChangeNotifier {
  Document _document;
  int _cursorParagraphIndex = 0;
  int _cursorOffset = 0;
  int? _selectionAnchorParagraphIndex;
  int? _selectionAnchorOffset;
  TextAttributes _activeAttributes = const TextAttributes();
  double? _preferredCursorX;
  String? _currentFilePath;
  bool _isDirty = false;
  EditorMode _currentMode = EditorMode.freestyle;
  String _selectedFreestyleFont = 'Arimo';

  // Search state
  final List<SearchResult> _searchResults = [];
  int _currentSearchIndex = -1;
  String _lastQuery = '';

  // History state
  final List<EditorStateSnapshot> _undoStack = [];
  final List<EditorStateSnapshot> _redoStack = [];
  bool _isTyping = false;
  Timer? _typingTimer;

  // Notification stream
  final _notificationController = StreamController<String>.broadcast();
  Stream<String> get notificationStream => _notificationController.stream;

  final SpellChecker _spellChecker = SpellChecker();
  int _documentVersion = 0;
  int get documentVersion => _documentVersion;

  void _onDocumentChanged() {
    _documentVersion++;
    _isDirty = true;
    notifyListeners();
  }

  EditorController({Document? document})
    : _document = document ?? Document.empty() {
    _updateActiveAttributes();
    _spellChecker.load().then((_) => notifyListeners());
  }

  // ... getters ...
  Document get document => _document;
  int get cursorParagraphIndex => _cursorParagraphIndex;
  int get cursorOffset => _cursorOffset;
  int? get selectionAnchorParagraphIndex => _selectionAnchorParagraphIndex;
  int? get selectionAnchorOffset => _selectionAnchorOffset;
  TextAttributes get activeAttributes => _activeAttributes;
  String? get currentFilePath => _currentFilePath;
  bool get isDirty => _isDirty;
  EditorMode get currentMode => _currentMode;
  String get selectedFreestyleFont => _selectedFreestyleFont;

  set selectedFreestyleFont(String font) {
    if (_selectedFreestyleFont != font) {
      _selectedFreestyleFont = font;
      if (_currentMode == EditorMode.freestyle) {
        _applyCurrentModeStyles();
      } else {
        notifyListeners();
      }
    }
  }

  set currentMode(EditorMode mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      _applyCurrentModeStyles();
    }
  }

  String get author => _document.metadata.author;
  set author(String value) {
    if (_document.metadata.author != value) {
      _document.metadata = DocumentMetadata(
        version: _document.metadata.version,
        editorModeIndex: _document.metadata.editorModeIndex,
        lastModified: DateTime.now(),
        author: value,
        title: _document.metadata.title,
      );
      _onDocumentChanged();
    }
  }

  String get title => _document.metadata.title;
  set title(String value) {
    if (_document.metadata.title != value) {
      _document.metadata = DocumentMetadata(
        version: _document.metadata.version,
        editorModeIndex: _document.metadata.editorModeIndex,
        lastModified: DateTime.now(),
        author: _document.metadata.author,
        title: value,
      );
      _onDocumentChanged();
    }
  }

  SpellChecker get spellChecker => _spellChecker;

  List<SearchResult> get searchResults => _searchResults;
  int get currentSearchIndex => _currentSearchIndex;

  // ... (addWordToDictionary and other methods remain) ...

  // Search Methods

  void find(String query) {
    _lastQuery = query;
    _searchResults.clear();
    _currentSearchIndex = -1;

    if (query.isEmpty) {
      notifyListeners();
      return;
    }

    final lowerQuery = query.toLowerCase();

    for (int i = 0; i < _document.paragraphs.length; i++) {
      final p = _document.paragraphs[i];
      final text = _getParagraphText(p).toLowerCase();
      int start = 0;
      while (true) {
        final index = text.indexOf(lowerQuery, start);
        if (index == -1) break;
        _searchResults.add(
          SearchResult(i, TextRange(start: index, end: index + query.length)),
        );
        start = index + 1;
      }
    }

    if (_searchResults.isNotEmpty) {
      _currentSearchIndex = 0;
      _jumpToSearchMatch(_currentSearchIndex);
    }

    notifyListeners();
  }

  void findNext(String query) {
    if (query != _lastQuery) {
      find(query);
      return;
    }
    if (_searchResults.isEmpty) return;

    _currentSearchIndex = (_currentSearchIndex + 1) % _searchResults.length;
    _jumpToSearchMatch(_currentSearchIndex);
    notifyListeners();
  }

  void findPrevious(String query) {
    if (query != _lastQuery) {
      find(query);
      return;
    }
    if (_searchResults.isEmpty) return;

    _currentSearchIndex =
        (_currentSearchIndex - 1 + _searchResults.length) %
        _searchResults.length;
    _jumpToSearchMatch(_currentSearchIndex);
    notifyListeners();
  }

  void _jumpToSearchMatch(int index) {
    if (index < 0 || index >= _searchResults.length) return;
    final match = _searchResults[index];
    setCursor(match.paragraphIndex, match.range.end, extendSelection: false);
    // Explicitly set selection to highlight the match
    _selectionAnchorParagraphIndex = match.paragraphIndex;
    _selectionAnchorOffset = match.range.start;
    // Set cursor to end
    _cursorOffset = match.range.end;
    notifyListeners();
  }

  void replaceCurrent(String query, String replacement) {
    if (_currentSearchIndex < 0 ||
        _currentSearchIndex >= _searchResults.length) {
      return;
    }

    final match = _searchResults[_currentSearchIndex];
    final p = _document.paragraphs[match.paragraphIndex];

    _replaceRangeInParagraph(
      p,
      match.range.start,
      match.range.end,
      replacement,
    );
    _onDocumentChanged();
    find(query);
  }

  void replaceAll(String query, String replacement) {
    if (query.isEmpty) return;

    _saveHistory(force: true);

    int startP = 0;
    int startO = 0;

    while (true) {
      int foundP = -1;
      int foundStart = -1;

      for (int i = startP; i < _document.paragraphs.length; i++) {
        final p = _document.paragraphs[i];
        final text = _getParagraphText(p);

        // Ensure starting offset is valid
        int offset = (i == startP) ? startO : 0;
        if (offset > text.length) {
          offset = text.length; // Or skip? text.indexOf handle invalid range?
          // Dart indexOf: start index must be non-negative. If > length, returns -1.
          // But if I pass startO > length, it might throw?
          // Documentation says 'start' default 0.
          // If start >= length, returns -1 (unless query empty).
        }

        final idx = text.indexOf(query, offset);
        if (idx != -1) {
          foundP = i;
          foundStart = idx;
          break;
        }
      }

      if (foundP == -1) break;

      final p = _document.paragraphs[foundP];
      final foundEnd = foundStart + query.length;

      _replaceRangeInParagraph(p, foundStart, foundEnd, replacement);

      startP = foundP;
      startO = foundStart + replacement.length;
    }

    _onDocumentChanged();
    _searchResults.clear();
    _currentSearchIndex = -1;
    _lastQuery = '';
  }

  void clearSearch() {
    _searchResults.clear();
    _currentSearchIndex = -1;
    _lastQuery = '';
    notifyListeners();
  }

  void _replaceRangeInParagraph(Paragraph p, int start, int end, String text) {
    // 1. Delete
    _deleteRangeInParagraph(p, start, end);

    // 2. Insert at 'start'
    // We need to find the run at 'start'
    int currentOffset = 0;
    int insertIndex = 0;
    TextRun? targetRun;
    int relativeOffset = 0;

    if (p.runs.isEmpty) {
      p.runs.add(TextRun(text: text, attributes: _activeAttributes));
      return;
    }

    // Logic to insert into runs
    // This is similar to insertText but explicitly for a paragraph and offset
    for (int i = 0; i < p.runs.length; i++) {
      if (start <= currentOffset + p.runs[i].text.length) {
        insertIndex = i;
        relativeOffset = start - currentOffset;
        targetRun = p.runs[i];
        break;
      }
      currentOffset += p.runs[i].text.length;
    }

    if (targetRun != null) {
      TextAttributes attrs = targetRun.attributes;
      // If we are appending to a run
      String before = targetRun.text.substring(0, relativeOffset);
      String after = targetRun.text.substring(relativeOffset);

      p.runs[insertIndex] = TextRun(
        text: before + text + after,
        attributes: attrs,
      );
      // This merges it into one run, which is fine.
      // If we wanted to preserve distinct usage of 'text' attributes we'd split.
      // But for replaceAll, inheriting surrounding style is usually minimal surprise.
      // Actually, typically replaceAll uses the style of the *replaced* text.
      // Since we deleted the replaced text, we are at the insertion point.
    }
  }

  Future<void> addWordToDictionary(String word) async {
    await _spellChecker.addToDictionary(word);
    notifyListeners();
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  bool get hasSelection =>
      _selectionAnchorParagraphIndex != null && _selectionAnchorOffset != null;

  void setCursor(
    int paragraphIndex,
    int offset, {
    bool extendSelection = false,
  }) {
    if (extendSelection) {
      _selectionAnchorParagraphIndex ??= _cursorParagraphIndex;
      _selectionAnchorOffset ??= _cursorOffset;
    } else {
      _selectionAnchorParagraphIndex = null;
      _selectionAnchorOffset = null;
    }

    _cursorParagraphIndex = paragraphIndex.clamp(
      0,
      _document.paragraphs.length - 1,
    );
    final paragraph = _document.paragraphs[_cursorParagraphIndex];
    int totalLength = 0;
    for (var r in paragraph.runs) {
      totalLength += r.text.length;
    }
    _cursorOffset = offset.clamp(0, totalLength);

    _preferredCursorX = null;
    _updateActiveAttributes();
    notifyListeners();
  }

  void _saveHistory({bool force = false}) {
    if (!force && _isTyping) return;

    _isTyping = false;
    _typingTimer?.cancel();

    _undoStack.add(
      EditorStateSnapshot(
        document: _document.clone(),
        cursorParagraphIndex: _cursorParagraphIndex,
        cursorOffset: _cursorOffset,
        selectionAnchorParagraphIndex: _selectionAnchorParagraphIndex,
        selectionAnchorOffset: _selectionAnchorOffset,
      ),
    );
    _redoStack.clear();

    if (_undoStack.length > 100) {
      _undoStack.removeAt(0);
    }
  }

  void _handleTypingAction(String text) {
    if (!_isTyping || text == ' ' || text == '\n') {
      _saveHistory(force: true);
      _isTyping = (text != '\n'); // Keep typing if not enter
    }

    // Reset typing timer - if user stops typing for 1s, next char will save history
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 1), () {
      _isTyping = false;
    });
  }

  void undo() {
    if (_undoStack.isEmpty) return;

    // Save current state to redo
    _redoStack.add(
      EditorStateSnapshot(
        document: _document.clone(),
        cursorParagraphIndex: _cursorParagraphIndex,
        cursorOffset: _cursorOffset,
        selectionAnchorParagraphIndex: _selectionAnchorParagraphIndex,
        selectionAnchorOffset: _selectionAnchorOffset,
      ),
    );

    final snapshot = _undoStack.removeLast();
    _document = snapshot.document;
    _cursorParagraphIndex = snapshot.cursorParagraphIndex;
    _cursorOffset = snapshot.cursorOffset;
    _selectionAnchorParagraphIndex = snapshot.selectionAnchorParagraphIndex;
    _selectionAnchorOffset = snapshot.selectionAnchorOffset;

    _isTyping = false;
    _updateActiveAttributes();
    _onDocumentChanged();
  }

  void redo() {
    if (_redoStack.isEmpty) return;

    // Save current state to undo
    _undoStack.add(
      EditorStateSnapshot(
        document: _document.clone(),
        cursorParagraphIndex: _cursorParagraphIndex,
        cursorOffset: _cursorOffset,
        selectionAnchorParagraphIndex: _selectionAnchorParagraphIndex,
        selectionAnchorOffset: _selectionAnchorOffset,
      ),
    );

    final snapshot = _redoStack.removeLast();
    _document = snapshot.document;
    _cursorParagraphIndex = snapshot.cursorParagraphIndex;
    _cursorOffset = snapshot.cursorOffset;
    _selectionAnchorParagraphIndex = snapshot.selectionAnchorParagraphIndex;
    _selectionAnchorOffset = snapshot.selectionAnchorOffset;

    _isTyping = false;
    _updateActiveAttributes();
    _onDocumentChanged();
  }

  void insertText(String text) {
    if (text.isEmpty) return;

    // Ignore non-printable control characters (except newline and tab)
    // DEL (\x7f) and other control codes often cause rendering issues
    final codeUnit = text.codeUnitAt(0);
    // Ignore non-printable control characters and Zero-Width Space (U+200B)
    if (codeUnit < 32 && text != '\n' && text != '\t') return;
    if (codeUnit == 127 || codeUnit == 0x200B) return;

    if (hasSelection) {
      _saveHistory(force: true);
      deleteSelection();
    } else {
      _handleTypingAction(text);
    }

    _insertTextInternal(text);
    _onDocumentChanged();
  }

  void _insertTextInternal(String text) {
    if (text == '\n') {
      _splitParagraph();
    } else {
      final paragraph = _document.paragraphs[_cursorParagraphIndex];

      int runIndex = 0;
      int currentRunOffset = 0;
      for (int i = 0; i < paragraph.runs.length; i++) {
        if (_cursorOffset <= currentRunOffset + paragraph.runs[i].text.length) {
          runIndex = i;
          break;
        }
        currentRunOffset += paragraph.runs[i].text.length;
        runIndex = i;
      }

      final run = paragraph.runs[runIndex];
      final relativeOffset = _cursorOffset - currentRunOffset;

      if (run.attributes == _activeAttributes) {
        paragraph.runs[runIndex] = TextRun(
          text:
              run.text.substring(0, relativeOffset) +
              text +
              run.text.substring(relativeOffset),
          attributes: run.attributes,
        );
      } else {
        if (relativeOffset == 0) {
          paragraph.runs.insert(
            runIndex,
            TextRun(text: text, attributes: _activeAttributes),
          );
        } else if (relativeOffset == run.text.length) {
          paragraph.runs.insert(
            runIndex + 1,
            TextRun(text: text, attributes: _activeAttributes),
          );
        } else {
          final before = run.text.substring(0, relativeOffset);
          final after = run.text.substring(relativeOffset);
          paragraph.runs[runIndex] = TextRun(
            text: before,
            attributes: run.attributes,
          );
          paragraph.runs.insert(
            runIndex + 1,
            TextRun(text: text, attributes: _activeAttributes),
          );
          paragraph.runs.insert(
            runIndex + 2,
            TextRun(text: after, attributes: run.attributes),
          );
        }
      }
      _cursorOffset += text.length;
    }
    _document.paragraphs[_cursorParagraphIndex].cachedHeight = null;
    _document.paragraphs[_cursorParagraphIndex].cachedWidth = null;
    _mergeAdjacentSimilarRuns(_document.paragraphs[_cursorParagraphIndex]);

    // We update active attributes first to sync with insertion state
    _updateActiveAttributes();

    // Then handle shortcuts which might CHANGE active attributes (e.g. inline code)
    // and we want that change to persist.
    _handleMarkdownShortcuts(text);
  }

  void replaceRange(int startGlobal, int endGlobal, String newText) {
    if (startGlobal == endGlobal && newText.isEmpty) return;

    _saveHistory(force: true);

    if (startGlobal < endGlobal) {
      final (sP, sO) = fromDocumentOffset(startGlobal);
      final (eP, eO) = fromDocumentOffset(endGlobal);
      _deleteRange(sP, sO, eP, eO);
    } else {
      final (insP, insO) = fromDocumentOffset(startGlobal);
      _cursorParagraphIndex = insP;
      _cursorOffset = insO;
    }

    if (newText.isNotEmpty) {
      _insertTextInternal(newText);
    }

    _onDocumentChanged();
  }

  void _splitParagraph() {
    final paragraph = _document.paragraphs[_cursorParagraphIndex];

    List<TextRun> currentRuns = [];
    List<TextRun> newRuns = [];

    int currentRunOffset = 0;
    bool splitDone = false;

    for (var run in paragraph.runs) {
      if (splitDone) {
        newRuns.add(run);
        continue;
      }

      int runLen = run.text.length;
      if (_cursorOffset >= currentRunOffset &&
          _cursorOffset <= currentRunOffset + runLen) {
        final relativeOffset = _cursorOffset - currentRunOffset;
        final beforeText = run.text.substring(0, relativeOffset);
        final afterText = run.text.substring(relativeOffset);

        if (beforeText.isNotEmpty || currentRuns.isEmpty) {
          currentRuns.add(
            TextRun(text: beforeText, attributes: run.attributes),
          );
        }
        if (afterText.isNotEmpty) {
          newRuns.add(TextRun(text: afterText, attributes: run.attributes));
        }
        splitDone = true;
      } else {
        currentRuns.add(run);
      }
      currentRunOffset += runLen;
    }

    paragraph.runs.clear();
    paragraph.runs.addAll(
      currentRuns.isNotEmpty
          ? currentRuns
          : [TextRun(text: '', attributes: _activeAttributes)],
    );
    _mergeAdjacentSimilarRuns(paragraph);

    // Fix for Sticky Headers:
    // If the previous line was a header (detected by large font size),
    // we want the NEW line to revert to standard body text (12pt, normal).
    if ((_activeAttributes.fontSize ?? 12.0) > 12.0) {
      _activeAttributes = _activeAttributes.copyWith(
        fontSize: 12.0,
        bold: false,
      );
    }

    final newParagraph = Paragraph(
      runs: newRuns.isNotEmpty
          ? newRuns
          : [TextRun(text: '', attributes: _activeAttributes)],
      alignment: paragraph.alignment,
      lineSpacing: paragraph.lineSpacing,
    );

    // Invalidate cache for the original paragraph (it was split)
    paragraph.cachedHeight = null;
    paragraph.cachedWidth = null;

    _document.paragraphs.insert(_cursorParagraphIndex + 1, newParagraph);
    _cursorParagraphIndex++;
    _cursorOffset = 0;
    _isDirty = true;
    notifyListeners();
  }

  void deleteText() {
    if (hasSelection) {
      _saveHistory(force: true);
      deleteSelection();
      notifyListeners();
      return;
    }

    _handleTypingAction('delete');

    if (_cursorOffset > 0) {
      final paragraph = _document.paragraphs[_cursorParagraphIndex];
      _deleteRangeInParagraph(paragraph, _cursorOffset - 1, _cursorOffset);
      _cursorOffset--;
    } else if (_cursorParagraphIndex > 0) {
      _mergeParagraphs();
    }
    _updateActiveAttributes();
    _onDocumentChanged();
  }

  void deleteForward() {
    if (hasSelection) {
      _saveHistory(force: true);
      deleteSelection();
      notifyListeners();
      return;
    }

    final paragraph = _document.paragraphs[_cursorParagraphIndex];
    int pLen = _getParagraphLength(paragraph);

    if (_cursorOffset < pLen) {
      _saveHistory(force: true);
      _deleteRangeInParagraph(paragraph, _cursorOffset, _cursorOffset + 1);
    } else if (_cursorParagraphIndex < _document.paragraphs.length - 1) {
      _saveHistory(force: true);
      // Merge next paragraph into this one
      final nextP = _document.paragraphs[_cursorParagraphIndex + 1];
      paragraph.runs.addAll(nextP.runs);
      _document.paragraphs.removeAt(_cursorParagraphIndex + 1);
    }
    _updateActiveAttributes();
    _onDocumentChanged();
  }

  void deleteSelection() {
    if (!hasSelection) return;

    final anchorP = _selectionAnchorParagraphIndex!;
    final anchorO = _selectionAnchorOffset!;
    final cursorP = _cursorParagraphIndex;
    final cursorO = _cursorOffset;

    final startP = (anchorP < cursorP)
        ? anchorP
        : ((anchorP > cursorP) ? cursorP : anchorP);
    final endP = (anchorP > cursorP)
        ? anchorP
        : ((anchorP < cursorP) ? cursorP : anchorP);

    int startO, endO;
    if (anchorP < cursorP) {
      startO = anchorO;
      endO = cursorO;
    } else if (anchorP > cursorP) {
      startO = cursorO;
      endO = anchorO;
    } else {
      startO = anchorO < cursorO ? anchorO : cursorO;
      endO = anchorO > cursorO ? anchorO : cursorO;
    }

    _deleteRange(startP, startO, endP, endO);
    _onDocumentChanged();
  }

  void _deleteRange(int startP, int startO, int endP, int endO) {
    if (startP == endP) {
      // Single paragraph deletion
      final p = _document.paragraphs[startP];
      _deleteRangeInParagraph(p, startO, endO);
      _cursorParagraphIndex = startP;
      _cursorOffset = startO;
    } else {
      // Multi-paragraph deletion
      final firstP = _document.paragraphs[startP];
      final lastP = _document.paragraphs[endP];

      // Keep everything before startO in firstP
      _deleteRangeInParagraph(firstP, startO, _getParagraphLength(firstP));

      // Keep everything after endO in lastP
      _deleteRangeInParagraph(lastP, 0, endO);

      // Merge lastP into firstP
      firstP.runs.addAll(lastP.runs);

      // Remove intermediate paragraphs
      _document.paragraphs.removeRange(startP + 1, endP + 1);

      _cursorParagraphIndex = startP;
      _cursorOffset = startO;
    }

    _selectionAnchorParagraphIndex = null;
    _selectionAnchorOffset = null;
    _updateActiveAttributes();
  }

  int _getParagraphLength(Paragraph p) {
    int len = 0;
    for (var r in p.runs) {
      len += r.text.length;
    }
    return len;
  }

  void _deleteRangeInParagraph(Paragraph p, int start, int end) {
    int currentOffset = 0;
    final List<TextRun> newRuns = [];

    for (var run in p.runs) {
      int runStart = currentOffset;
      int runEnd = currentOffset + run.text.length;

      if (runEnd <= start || runStart >= end) {
        // No overlap
        newRuns.add(run);
      } else {
        // Overlap
        String newText = "";
        if (runStart < start) {
          newText += run.text.substring(0, start - runStart);
        }
        if (runEnd > end) {
          newText += run.text.substring(end - runStart);
        }
        if (newText.isNotEmpty) {
          newRuns.add(TextRun(text: newText, attributes: run.attributes));
        }
      }
      currentOffset += run.text.length;
    }

    p.runs.clear();
    p.runs.addAll(newRuns);
    p.cachedHeight = null;
    p.cachedWidth = null;
    if (p.runs.isEmpty) {
      p.runs.add(TextRun(text: "", attributes: _activeAttributes));
    }
  }

  void _mergeParagraphs() {
    final prevParagraph = _document.paragraphs[_cursorParagraphIndex - 1];
    final currentParagraph = _document.paragraphs[_cursorParagraphIndex];

    int totalPrevLength = 0;
    for (var r in prevParagraph.runs) {
      totalPrevLength += r.text.length;
    }

    _cursorParagraphIndex--;
    _cursorOffset = totalPrevLength;

    prevParagraph.runs.addAll(currentParagraph.runs);
    prevParagraph.cachedHeight = null;
    prevParagraph.cachedWidth = null;
    _document.paragraphs.removeAt(_cursorParagraphIndex + 1);
  }

  void moveCursorLeft({bool extendSelection = false}) {
    if (extendSelection) {
      _selectionAnchorParagraphIndex ??= _cursorParagraphIndex;
      _selectionAnchorOffset ??= _cursorOffset;
    } else {
      _selectionAnchorParagraphIndex = null;
      _selectionAnchorOffset = null;
    }

    if (_cursorOffset > 0) {
      _cursorOffset--;
    } else if (_cursorParagraphIndex > 0) {
      _cursorParagraphIndex--;
      int totalLength = 0;
      for (var r in _document.paragraphs[_cursorParagraphIndex].runs) {
        totalLength += r.text.length;
      }
      _cursorOffset = totalLength;
    }
    _preferredCursorX = null;
    _updateActiveAttributes();
    notifyListeners();
  }

  void moveCursorRight({bool extendSelection = false}) {
    if (extendSelection) {
      _selectionAnchorParagraphIndex ??= _cursorParagraphIndex;
      _selectionAnchorOffset ??= _cursorOffset;
    } else {
      _selectionAnchorParagraphIndex = null;
      _selectionAnchorOffset = null;
    }

    final paragraph = _document.paragraphs[_cursorParagraphIndex];
    int totalLength = 0;
    for (var r in paragraph.runs) {
      totalLength += r.text.length;
    }

    if (_cursorOffset < totalLength) {
      _cursorOffset++;
    } else if (_cursorParagraphIndex < _document.paragraphs.length - 1) {
      _cursorParagraphIndex++;
      _cursorOffset = 0;
    }
    _preferredCursorX = null;
    _updateActiveAttributes();
    notifyListeners();
  }

  void moveCursorUp({
    bool extendSelection = false,
    required double layoutWidth,
  }) {
    if (extendSelection) {
      _selectionAnchorParagraphIndex ??= _cursorParagraphIndex;
      _selectionAnchorOffset ??= _cursorOffset;
    } else {
      _selectionAnchorParagraphIndex = null;
      _selectionAnchorOffset = null;
    }

    final p = _document.paragraphs[_cursorParagraphIndex];
    final tp = _getTextPainter(p);
    tp.layout(maxWidth: layoutWidth);

    final caretPos = tp.getOffsetForCaret(
      TextPosition(offset: _cursorOffset),
      Rect.zero,
    );
    final targetX = _preferredCursorX ?? caretPos.dx;

    // Is there a line above in the same paragraph?
    final lineMetrics = tp.computeLineMetrics();
    int currentLineIdx = -1;
    double currentLineTop = 0;
    for (int i = 0; i < lineMetrics.length; i++) {
      if (caretPos.dy >= currentLineTop &&
          caretPos.dy < currentLineTop + lineMetrics[i].height) {
        currentLineIdx = i;
        break;
      }
      currentLineTop += lineMetrics[i].height;
    }

    if (currentLineIdx > 0) {
      // Move to previous line in same paragraph
      final prevLineTop =
          currentLineTop - lineMetrics[currentLineIdx - 1].height;
      final newPos = tp.getPositionForOffset(
        Offset(
          targetX,
          prevLineTop + lineMetrics[currentLineIdx - 1].height / 2,
        ),
      );
      _cursorOffset = newPos.offset;
      _preferredCursorX = targetX;
    } else if (_cursorParagraphIndex > 0) {
      // Move to last line of previous paragraph
      _cursorParagraphIndex--;
      final prevP = _document.paragraphs[_cursorParagraphIndex];
      final prevTp = _getTextPainter(prevP);
      prevTp.layout(maxWidth: layoutWidth);
      final prevMetrics = prevTp.computeLineMetrics();
      if (prevMetrics.isNotEmpty) {
        final lastLineTop = prevTp.height - prevMetrics.last.height;
        final newPos = prevTp.getPositionForOffset(
          Offset(targetX, lastLineTop + prevMetrics.last.height / 2),
        );
        _cursorOffset = newPos.offset;
      } else {
        _cursorOffset = 0;
      }
      _preferredCursorX = targetX;
    }

    _updateActiveAttributes();
    notifyListeners();
  }

  void moveCursorDown({
    bool extendSelection = false,
    required double layoutWidth,
  }) {
    if (extendSelection) {
      _selectionAnchorParagraphIndex ??= _cursorParagraphIndex;
      _selectionAnchorOffset ??= _cursorOffset;
    } else {
      _selectionAnchorParagraphIndex = null;
      _selectionAnchorOffset = null;
    }

    final p = _document.paragraphs[_cursorParagraphIndex];
    final tp = _getTextPainter(p);
    tp.layout(maxWidth: layoutWidth);

    final caretPos = tp.getOffsetForCaret(
      TextPosition(offset: _cursorOffset),
      Rect.zero,
    );
    final targetX = _preferredCursorX ?? caretPos.dx;

    final lineMetrics = tp.computeLineMetrics();
    int currentLineIdx = -1;
    double currentLineTop = 0;
    for (int i = 0; i < lineMetrics.length; i++) {
      if (caretPos.dy >= currentLineTop &&
          caretPos.dy < currentLineTop + lineMetrics[i].height) {
        currentLineIdx = i;
        break;
      }
      currentLineTop += lineMetrics[i].height;
    }

    if (currentLineIdx != -1 && currentLineIdx < lineMetrics.length - 1) {
      // Move to next line in same paragraph
      final nextLineTop = currentLineTop + lineMetrics[currentLineIdx].height;
      final newPos = tp.getPositionForOffset(
        Offset(
          targetX,
          nextLineTop + lineMetrics[currentLineIdx + 1].height / 2,
        ),
      );
      _cursorOffset = newPos.offset;
      _preferredCursorX = targetX;
    } else if (_cursorParagraphIndex < _document.paragraphs.length - 1) {
      // Move to first line of next paragraph
      _cursorParagraphIndex++;
      final nextP = _document.paragraphs[_cursorParagraphIndex];
      final nextTp = _getTextPainter(nextP);
      nextTp.layout(maxWidth: layoutWidth);
      final nextMetrics = nextTp.computeLineMetrics();
      if (nextMetrics.isNotEmpty) {
        final newPos = nextTp.getPositionForOffset(
          Offset(targetX, nextMetrics.first.height / 2),
        );
        _cursorOffset = newPos.offset;
      } else {
        _cursorOffset = 0;
      }
      _preferredCursorX = targetX;
    }

    _updateActiveAttributes();
    notifyListeners();
  }

  TextPainter _getTextPainter(Paragraph p) {
    final List<InlineSpan> spans = [];
    final List<PlaceholderDimensions> dimensions = [];
    for (var run in p.runs) {
      spans.addAll(
        _buildSpansForText(
          run.text,
          run.attributes.toTextStyle(height: p.lineSpacing),
          dimensions,
        ),
      );
    }

    final tp = TextPainter(
      text: TextSpan(
        children: spans,
        style: const TextStyle(color: Colors.black),
      ),
      textDirection: TextDirection.ltr,
      textAlign: _getTextAlign(p.alignment),
    );

    if (dimensions.isNotEmpty) {
      tp.setPlaceholderDimensions(dimensions);
    }

    return tp;
  }

  List<InlineSpan> _buildSpansForText(
    String text,
    TextStyle style,
    List<PlaceholderDimensions> dimensions,
  ) {
    if (!text.contains('\t')) {
      return [TextSpan(text: text, style: style)];
    }

    final List<InlineSpan> spans = [];
    final parts = text.split('\t');

    // Calculate tab width based on 4 spaces of the current style
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
        spans.add(
          WidgetSpan(
            child: SizedBox(width: tabWidth),
            baseline: TextBaseline.alphabetic,
            alignment: PlaceholderAlignment.baseline,
          ),
        );
        dimensions.add(
          PlaceholderDimensions(
            size: Size(
              tabWidth,
              (style.fontSize ?? 12.0) * (style.height ?? 1.0),
            ),
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
          ),
        );
      }
    }
    return spans;
  }

  TextAlign _getTextAlign(ParagraphAlignment alignment) {
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

  void _updateActiveAttributes() {
    final paragraph = _document.paragraphs[_cursorParagraphIndex];
    if (paragraph.runs.isEmpty) {
      _activeAttributes = const TextAttributes();
      return;
    }

    if (_cursorOffset == 0) {
      _activeAttributes = paragraph.runs.first.attributes;
      return;
    }

    int currentRunOffset = 0;
    for (var run in paragraph.runs) {
      int runEnd = currentRunOffset + run.text.length;
      // If cursor is inside or specifically at the END of a non-empty run,
      // we prefer the run to the left for standard typing continuation.
      if (_cursorOffset > currentRunOffset && _cursorOffset <= runEnd) {
        _activeAttributes = run.attributes;
        return;
      }
      currentRunOffset = runEnd;
    }
    // If we're at the very end and didn't find a matching run,
    // we use the attributes of the last run to ensure font consistency.
    if (paragraph.runs.isNotEmpty) {
      _activeAttributes = paragraph.runs.last.attributes;
    } else {
      _activeAttributes = const TextAttributes();
    }
  }

  void toggleBold() {
    _saveHistory(force: true);
    if (hasSelection) {
      _applyStyleToSelection((attr) => attr.copyWith(bold: !attr.bold));
    } else {
      _activeAttributes = _activeAttributes.copyWith(
        bold: !_activeAttributes.bold,
      );
      _updateEmptyRunAtCursor();
    }
    _onDocumentChanged();
  }

  void toggleItalic() {
    _saveHistory(force: true);
    if (hasSelection) {
      _applyStyleToSelection((attr) => attr.copyWith(italic: !attr.italic));
    } else {
      _activeAttributes = _activeAttributes.copyWith(
        italic: !_activeAttributes.italic,
      );
      _updateEmptyRunAtCursor();
    }
    _onDocumentChanged();
  }

  void toggleUnderline() {
    _saveHistory(force: true);
    if (hasSelection) {
      _applyStyleToSelection(
        (attr) => attr.copyWith(underline: !attr.underline),
      );
    } else {
      _activeAttributes = _activeAttributes.copyWith(
        underline: !_activeAttributes.underline,
      );
      _updateEmptyRunAtCursor();
    }
    _onDocumentChanged();
  }

  void _updateEmptyRunAtCursor() {
    final paragraph = _document.paragraphs[_cursorParagraphIndex];
    int currentOffset = 0;
    for (int i = 0; i < paragraph.runs.length; i++) {
      final run = paragraph.runs[i];
      if (_cursorOffset == currentOffset && run.text.isEmpty) {
        paragraph.runs[i] = TextRun(text: '', attributes: _activeAttributes);
        return;
      }
      currentOffset += run.text.length;
    }
  }

  void _applyStyleToSelection(
    TextAttributes Function(TextAttributes) transform,
  ) {
    if (_selectionAnchorParagraphIndex == null ||
        _selectionAnchorOffset == null) {
      return;
    }

    final anchorP = _selectionAnchorParagraphIndex!;
    final anchorO = _selectionAnchorOffset!;
    final cursorP = _cursorParagraphIndex;
    final cursorO = _cursorOffset;

    // Determine bounds
    final startP = anchorP < cursorP ? anchorP : cursorP;
    final endP = anchorP > cursorP ? anchorP : cursorP;

    final startOffset = anchorP == startP
        ? (startP == endP ? (anchorO < cursorO ? anchorO : cursorO) : anchorO)
        : cursorO;
    final endOffset = anchorP == endP
        ? (startP == endP ? (anchorO > cursorO ? anchorO : cursorO) : anchorO)
        : cursorO;

    for (int i = startP; i <= endP; i++) {
      final p = _document.paragraphs[i];
      int pStart = (i == startP) ? startOffset : 0;
      int pEnd = (i == endP) ? endOffset : 0;
      if (i != endP) {
        int len = 0;
        for (var r in p.runs) {
          len += r.text.length;
        }
        pEnd = len;
      }

      final List<TextRun> newRuns = [];
      int currentOffset = 0;

      for (var run in p.runs) {
        int runLen = run.text.length;
        int runStart = currentOffset;
        int runEnd = currentOffset + runLen;

        // Intersection of selection in paragraph and current run
        int overlapStart = runStart > pStart ? runStart : pStart;
        int overlapEnd = runEnd < pEnd ? runEnd : pEnd;

        if (overlapStart < overlapEnd) {
          // Part of the run is selected
          if (overlapStart > runStart) {
            newRuns.add(
              TextRun(
                text: run.text.substring(0, overlapStart - runStart),
                attributes: run.attributes,
              ),
            );
          }
          newRuns.add(
            TextRun(
              text: run.text.substring(
                overlapStart - runStart,
                overlapEnd - runStart,
              ),
              attributes: transform(run.attributes),
            ),
          );
          if (overlapEnd < runEnd) {
            newRuns.add(
              TextRun(
                text: run.text.substring(overlapEnd - runStart),
                attributes: run.attributes,
              ),
            );
          }
        } else {
          newRuns.add(run);
        }
        currentOffset += runLen;
      }
      p.runs.clear();
      p.runs.addAll(newRuns);
      _mergeAdjacentSimilarRuns(p);
    }
  }

  void _mergeAdjacentSimilarRuns(Paragraph p) {
    if (p.runs.isEmpty) return;
    final List<TextRun> merged = [];
    merged.add(p.runs.first);

    for (int i = 1; i < p.runs.length; i++) {
      final last = merged.last;
      final current = p.runs[i];
      if (last.attributes == current.attributes) {
        merged[merged.length - 1] = TextRun(
          text: last.text + current.text,
          attributes: last.attributes,
        );
      } else {
        merged.add(current);
      }
    }
    p.runs.clear();
    p.runs.addAll(merged);
  }

  void setAlignment(ParagraphAlignment alignment) {
    _saveHistory(force: true);
    final p = _document.paragraphs[_cursorParagraphIndex];
    _document.paragraphs[_cursorParagraphIndex] = Paragraph(
      runs: p.runs,
      alignment: alignment,
      lineSpacing: p.lineSpacing,
    );
    _onDocumentChanged();
  }

  void applyModeDefaults({required double lineSpacing, String? fontFamily}) {
    _saveHistory(force: true);
    for (var i = 0; i < _document.paragraphs.length; i++) {
      final p = _document.paragraphs[i];
      _document.paragraphs[i] = Paragraph(
        runs: p.runs.map((run) {
          return TextRun(
            text: run.text,
            attributes: run.attributes.copyWith(
              fontFamily: fontFamily,
              fontSize:
                  run.attributes.fontSize != null &&
                      run.attributes.fontSize! > 12.0
                  ? run.attributes.fontSize
                  : 12.0,
            ),
          );
        }).toList(),
        alignment: p.alignment,
        lineSpacing: lineSpacing,
        type: p.type,
        indent: p.indent,
        listIndex: p.listIndex,
      );
    }
    _onDocumentChanged();
    _updateActiveAttributes();
  }

  void _applyCurrentModeStyles() {
    double lineSpacing = 1.0;
    String fontFamily = _selectedFreestyleFont;

    switch (_currentMode) {
      case EditorMode.screenplay:
        lineSpacing = 1.0;
        fontFamily = 'Courier Prime';
        break;
      case EditorMode.manuscript:
      case EditorMode.essay:
        lineSpacing = 2.0;
        fontFamily = 'Tinos';
        break;
      case EditorMode.freestyle:
        lineSpacing = 1.0;
        fontFamily = _selectedFreestyleFont;
        break;
    }

    applyModeDefaults(lineSpacing: lineSpacing, fontFamily: fontFamily);
  }

  void selectAll() {
    if (_document.paragraphs.isEmpty) return;

    _selectionAnchorParagraphIndex = 0;
    _selectionAnchorOffset = 0;

    _cursorParagraphIndex = _document.paragraphs.length - 1;
    final lastParagraph = _document.paragraphs.last;
    int totalLength = 0;
    for (var r in lastParagraph.runs) {
      totalLength += r.text.length;
    }
    _cursorOffset = totalLength;

    _updateActiveAttributes();
    notifyListeners();
  }

  bool isPositionSelected(int paragraphIndex, int offset) {
    if (!hasSelection) return false;

    final anchorP = _selectionAnchorParagraphIndex!;
    final anchorO = _selectionAnchorOffset!;
    final cursorP = _cursorParagraphIndex;
    final cursorO = _cursorOffset;

    final startP = (anchorP < cursorP)
        ? anchorP
        : ((anchorP > cursorP) ? cursorP : anchorP);
    final endP = (anchorP > cursorP)
        ? anchorP
        : ((anchorP < cursorP) ? cursorP : anchorP);

    if (paragraphIndex < startP || paragraphIndex > endP) return false;

    if (paragraphIndex > startP && paragraphIndex < endP) return true;

    if (startP == endP) {
      final startO = anchorO < cursorO ? anchorO : cursorO;
      final endO = anchorO > cursorO ? anchorO : cursorO;
      return offset >= startO && offset <= endO;
    }

    if (paragraphIndex == startP) {
      final startO = (startP == anchorP) ? anchorO : cursorO;
      return offset >= startO;
    }

    if (paragraphIndex == endP) {
      final endO = (endP == anchorP) ? anchorO : cursorO;
      return offset <= endO;
    }

    return false;
  }

  Future<void> copySelection() async {
    final text = await getSelectedText();
    if (text != null) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }

  Future<void> cutSelection() async {
    if (!hasSelection) return;
    await copySelection();
    _saveHistory(force: true);
    deleteSelection();
    _isDirty = true;
    notifyListeners();
  }

  Future<void> pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      _saveHistory(force: true);
      final text = data.text!;

      // Split by newline and insert
      final lines = text.split('\n');
      for (int i = 0; i < lines.length; i++) {
        _insertTextNoHistory(lines[i]);
        if (i < lines.length - 1) {
          _insertTextNoHistory('\n');
        }
      }
      _onDocumentChanged();
    }
  }

  void _insertTextNoHistory(String text) {
    if (text.isEmpty) return;

    final codeUnit = text.codeUnitAt(0);
    if (codeUnit < 32 && text != '\n' && text != '\t') return;
    if (codeUnit == 127) return;

    if (text == '\n') {
      // Check for Markdown shortcuts (e.g. '---' -> HR)
      final p = _document.paragraphs[_cursorParagraphIndex];
      final pText = _getParagraphText(p);

      if (pText.trim() == '---' && p.type == ParagraphType.normal) {
        // Convert to Horizontal Rule
        p.runs.clear();
        p.type = ParagraphType.horizontalRule;

        // Remove selection/cursor state relative to old paragraph content just in case
        // (Runs are cleared, so offset 0 is correct)

        // Insert new empty paragraph below to continue typing
        final newP = Paragraph(
          runs: [],
          type: ParagraphType.normal,
          alignment: ParagraphAlignment.left,
          lineSpacing: p.lineSpacing,
        );
        _document.paragraphs.insert(_cursorParagraphIndex + 1, newP);

        // Move cursor to new line
        _cursorParagraphIndex++;
        _cursorOffset = 0;

        _isDirty = true;
        notifyListeners();
        return;
      }

      _splitParagraph();
    } else {
      final paragraph = _document.paragraphs[_cursorParagraphIndex];

      int runIndex = 0;
      int currentRunOffset = 0;
      for (int i = 0; i < paragraph.runs.length; i++) {
        if (_cursorOffset <= currentRunOffset + paragraph.runs[i].text.length) {
          runIndex = i;
          break;
        }
        currentRunOffset += paragraph.runs[i].text.length;
        runIndex = i;
      }

      final run = paragraph.runs[runIndex];
      final relativeOffset = _cursorOffset - currentRunOffset;

      if (run.attributes == _activeAttributes) {
        paragraph.runs[runIndex] = TextRun(
          text:
              run.text.substring(0, relativeOffset) +
              text +
              run.text.substring(relativeOffset),
          attributes: run.attributes,
        );
      } else {
        if (relativeOffset == 0) {
          paragraph.runs.insert(
            runIndex,
            TextRun(text: text, attributes: _activeAttributes),
          );
        } else if (relativeOffset == run.text.length) {
          paragraph.runs.insert(
            runIndex + 1,
            TextRun(text: text, attributes: _activeAttributes),
          );
        } else {
          final before = run.text.substring(0, relativeOffset);
          final after = run.text.substring(relativeOffset);
          paragraph.runs[runIndex] = TextRun(
            text: before,
            attributes: run.attributes,
          );
          paragraph.runs.insert(
            runIndex + 1,
            TextRun(text: text, attributes: _activeAttributes),
          );
          paragraph.runs.insert(
            runIndex + 2,
            TextRun(text: after, attributes: run.attributes),
          );
        }
      }
      _cursorOffset += text.length;
    }
  }

  void moveToStart({bool extendSelection = false}) {
    setCursor(0, 0, extendSelection: extendSelection);
    notifyListeners();
  }

  void moveToEnd({bool extendSelection = false}) {
    if (_document.paragraphs.isEmpty) return;
    final lastIdx = _document.paragraphs.length - 1;
    final lastP = _document.paragraphs[lastIdx];

    int length = 0;
    for (var r in lastP.runs) {
      length += r.text.length;
    }
    setCursor(lastIdx, length, extendSelection: extendSelection);
    notifyListeners();
  }

  void selectWordAt(int paragraphIndex, int offset) {
    if (paragraphIndex < 0 || paragraphIndex >= _document.paragraphs.length) {
      return;
    }

    final p = _document.paragraphs[paragraphIndex];
    final fullText = _getParagraphText(p);

    if (fullText.isEmpty) {
      setCursor(paragraphIndex, 0);
      return;
    }

    // Clamp offset
    int safeOffset = offset.clamp(0, fullText.length);

    int start = safeOffset;
    int end = safeOffset;

    // Expand left
    while (start > 0 && _isWordChar(fullText[start - 1])) {
      start--;
    }
    // Expand right
    while (end < fullText.length && _isWordChar(fullText[end])) {
      end++;
    }

    // If we didn't expand at all (e.g. clicked on whitespace), just set cursor
    if (start == end) {
      setCursor(paragraphIndex, safeOffset);
    } else {
      _selectionAnchorParagraphIndex = paragraphIndex;
      _selectionAnchorOffset = start;
      _cursorParagraphIndex = paragraphIndex;
      _cursorOffset = end;
      _updateActiveAttributes();
      notifyListeners();
    }
  }

  bool _isWordChar(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 48 && code <= 57) || // 0-9
        (code >= 65 && code <= 90) || // A-Z
        (code >= 97 && code <= 122) || // a-z
        char == '_';
  }

  String _getParagraphText(Paragraph p) {
    return p.runs.map((r) => r.text).join("");
  }

  Future<String?> getSelectedText() async {
    if (!hasSelection) return null;

    final anchorP = _selectionAnchorParagraphIndex!;
    final anchorO = _selectionAnchorOffset!;
    final cursorP = _cursorParagraphIndex;
    final cursorO = _cursorOffset;

    final startP = (anchorP < cursorP)
        ? anchorP
        : ((anchorP > cursorP) ? cursorP : anchorP);
    final endP = (anchorP > cursorP)
        ? anchorP
        : ((anchorP < cursorP) ? cursorP : anchorP);

    int startO, endO;
    if (anchorP < cursorP) {
      startO = anchorO;
      endO = cursorO;
    } else if (anchorP > cursorP) {
      startO = cursorO;
      endO = anchorO;
    } else {
      startO = anchorO < cursorO ? anchorO : cursorO;
      endO = anchorO > cursorO ? anchorO : cursorO;
    }

    StringBuffer sb = StringBuffer();
    for (int i = startP; i <= endP; i++) {
      final p = _document.paragraphs[i];
      int s = (i == startP) ? startO : 0;
      int e = (i == endP) ? endO : _getParagraphLength(p);

      int currentOffset = 0;
      for (var run in p.runs) {
        int runStart = currentOffset;
        int runEnd = currentOffset + run.text.length;

        if (!(runEnd <= s || runStart >= e)) {
          int overlapStart = (runStart > s) ? runStart : s;
          int overlapEnd = (runEnd < e) ? runEnd : e;
          sb.write(
            run.text.substring(overlapStart - runStart, overlapEnd - runStart),
          );
        }
        currentOffset += run.text.length;
      }
      if (i < endP) sb.write('\n');
    }
    return sb.toString();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _notificationController.close();
    super.dispose();
  }

  // File I/O Methods
  Future<void> newFile() async {
    _document = Document.empty();
    _cursorParagraphIndex = 0;
    _cursorOffset = 0;
    _selectionAnchorParagraphIndex = null;
    _selectionAnchorOffset = null;
    _currentFilePath = null;
    _onDocumentChanged();
    _documentVersion = 0; // Reset version for new file
  }

  Future<void> openFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ptmb', 'txt', 'md'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final path = file.path;

        if (path.endsWith('.ptmb')) {
          final jsonString = await file.readAsString();
          final jsonMap = jsonDecode(jsonString);
          _document = Document.fromJson(jsonMap);
          _currentMode = EditorMode.values[_document.metadata.editorModeIndex];
          _currentFilePath = path;
        } else if (path.endsWith('.txt')) {
          final text = await file.readAsString();
          _document = await compute(parseTextToDocument, text);
          _currentFilePath = null;
          // Apply current mode defaults to imported text
          _applyCurrentModeStyles();
        } else if (path.endsWith('.md')) {
          final text = await file.readAsString();
          _document = await compute(parseMarkdownToDocument, text);
          _currentFilePath = null;
          // Apply current mode defaults to imported markdown
          _applyCurrentModeStyles();
        }

        _cursorParagraphIndex = 0;
        // ... (rest of method)

        // ... (existing saveFile methods)

        // ... (existing parseTextToDocument)

        _cursorOffset = 0;
        _selectionAnchorParagraphIndex = null;
        _selectionAnchorOffset = null;
        _undoStack.clear();
        _redoStack.clear();
        _updateActiveAttributes();
        _onDocumentChanged();
      }
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
  }

  Future<void> saveFile() async {
    if (_currentFilePath != null) {
      await _saveToPath(_currentFilePath!);
    } else {
      await saveFileAs();
    }
  }

  Future<void> saveFileAs() async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Document',
        fileName: 'document.ptmb',
        allowedExtensions: ['ptmb'],
        type: FileType.custom,
      );

      if (result != null) {
        String path = result;
        if (!path.endsWith('.ptmb')) {
          path += '.ptmb';
        }
        await _saveToPath(path);
      }
    } catch (e) {
      debugPrint('Error saving file: $e');
    }
  }

  Future<void> _saveToPath(String path) async {
    final file = File(path);
    // Update metadata before saving
    _document.metadata = DocumentMetadata(
      editorModeIndex: _currentMode.index,
      lastModified: DateTime.now(),
      version: "1.0",
    );
    final jsonMap = _document.toJson();
    final jsonString = jsonEncode(jsonMap);
    await file.writeAsString(jsonString);
    _currentFilePath = path;
    _isDirty = false;
    _notificationController.add('Saved');
    notifyListeners();
  }

  Future<void> exportToPdf(EdgeInsets margins, String modeName) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export PDF',
        fileName: 'document.pdf',
        allowedExtensions: ['pdf'],
        type: FileType.custom,
      );

      if (result != null) {
        String path = result;
        if (!path.endsWith('.pdf')) {
          path += '.pdf';
        }

        final pdfBytes = await PdfExporter.generatePdf(
          _document,
          margins,
          modeName,
        );
        final file = File(path);
        await file.writeAsBytes(pdfBytes);
      }
    } catch (e) {
      debugPrint('Error exporting PDF: $e');
    }
  }

  Future<void> exportToDocx(
    EdgeInsets margins,
    String defaultFontFamily,
  ) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export DOCX',
        fileName: 'document.docx',
        allowedExtensions: ['docx'],
        type: FileType.custom,
      );

      if (result != null) {
        String path = result;
        if (!path.endsWith('.docx')) {
          path += '.docx';
        }

        final docxBytes = await DocxExporter.generateDocx(
          _document,
          margins,
          defaultFontFamily,
        );
        final file = File(path);
        await file.writeAsBytes(docxBytes);
      }
    } catch (e) {
      debugPrint('Error exporting DOCX: $e');
    }
  }

  Future<void> exportToMarkdown() async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Markdown',
        fileName: 'document.md',
        allowedExtensions: ['md'],
        type: FileType.custom,
      );

      if (result != null) {
        String path = result;
        if (!path.endsWith('.md')) {
          path += '.md';
        }

        final mdString = MarkdownExporter.generateMarkdown(_document);
        final file = File(path);
        await file.writeAsString(mdString);
      }
    } catch (e) {
      debugPrint('Error exporting Markdown: $e');
    }
  }

  Future<void> printDocument(EdgeInsets margins, String modeName) async {
    try {
      final pdfBytes = await PdfExporter.generatePdf(
        _document,
        margins,
        modeName,
      );
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: _currentFilePath != null
            ? _currentFilePath!.split(Platform.pathSeparator).last
            : 'document.pdf',
      );
    } catch (e) {
      debugPrint('Error printing document: $e');
    }
  }

  void _handleMarkdownShortcuts(String insertedText) {
    if (insertedText == ' ') {
      _checkBlockShortcuts();
    }
    _checkInlineShortcuts(insertedText);
  }

  void _checkBlockShortcuts() {
    final paragraph = _document.paragraphs[_cursorParagraphIndex];
    final fullText = paragraph.runs.map((r) => r.text).join();

    // Detect leading whitespace and calculate indent
    final whitespaceMatch = RegExp(r'^([ \t]+)').firstMatch(fullText);
    final whitespace = whitespaceMatch?.group(1) ?? '';
    final textAfterWhitespace = fullText.substring(whitespace.length);

    // Count tabs or groups of 4 spaces as indent levels
    // Simple heuristic: 1 tab = 1 indent, 4 spaces = 1 indent
    int indent = 0;
    if (whitespace.isNotEmpty) {
      int tabCount = whitespace.split('\t').length - 1;
      int spaceCount = whitespace.split(' ').length - 1;
      indent = tabCount + (spaceCount ~/ 4);
    }

    // Blockquote
    if (textAfterWhitespace.startsWith('> ')) {
      _saveHistory(force: true);
      paragraph.type = ParagraphType.blockquote;
      _removePrefix(whitespace.length + 2);
    }
    // Bullet list
    else if (textAfterWhitespace.startsWith('* ') ||
        textAfterWhitespace.startsWith('- ')) {
      _saveHistory(force: true);
      paragraph.type = ParagraphType.bulletList;
      paragraph.indent = indent;
      _removePrefix(whitespace.length + 2);
    }
    // Header (# to ######)
    else if (textAfterWhitespace.startsWith('#')) {
      final headerMatch = RegExp(r'^(#{1,6}) ').firstMatch(textAfterWhitespace);
      if (headerMatch != null) {
        _saveHistory(force: true);
        final level = headerMatch.group(1)!.length;

        // Determine font size based on level
        double fontSize;
        switch (level) {
          case 1:
            fontSize = 24.0;
            break; // H1
          case 2:
            fontSize = 20.0;
            break; // H2
          case 3:
            fontSize = 18.0;
            break; // H3
          case 4:
            fontSize = 16.0;
            break; // H4
          case 5:
            fontSize = 14.0;
            break; // H5
          case 6:
            fontSize = 12.0;
            break; // H6
          default:
            fontSize = 20.0;
        }

        // Apply style to the ENTIRE paragraph
        _activeAttributes = _activeAttributes.copyWith(
          fontSize: fontSize,
          bold: true,
        );

        // We need to update existing runs in this paragraph to match
        for (var i = 0; i < paragraph.runs.length; i++) {
          paragraph.runs[i] = TextRun(
            text: paragraph.runs[i].text,
            attributes: paragraph.runs[i].attributes.copyWith(
              fontSize: fontSize,
              bold: true,
            ),
          );
        }

        // Remove the prefix
        _removePrefix(whitespace.length + level + 1); // +1 for space
      }
      // Fall through to Numbered list if not header (though they are mutually exclusive by prefix)
    }
    // Numbered list
    else {
      final match = RegExp(r'^(\d+)\. ').firstMatch(textAfterWhitespace);
      if (match != null) {
        _saveHistory(force: true);
        paragraph.type = ParagraphType.numberedList;
        paragraph.listIndex = int.parse(match.group(1)!);
        paragraph.indent = indent;
        _removePrefix(whitespace.length + match.group(0)!.length);
      }
    }
  }

  void _removePrefix(int length) {
    final paragraph = _document.paragraphs[_cursorParagraphIndex];
    _deleteRangeInParagraph(paragraph, 0, length);
    _cursorOffset = (_cursorOffset - length).clamp(0, 999999);
  }

  void _checkInlineShortcuts(String insertedText) {
    // Basic inline markdown support (**bold**, *italic*, `code`)
    if (insertedText != '*' && insertedText != '_' && insertedText != '`') {
      return;
    }

    final paragraph = _document.paragraphs[_cursorParagraphIndex];
    final fullText = paragraph.runs.map((r) => r.text).join();
    final textBeforeCursor = fullText.substring(0, _cursorOffset);

    // Code (`...`)
    if (textBeforeCursor.endsWith('`') && textBeforeCursor.length > 1) {
      // Check for matching opening backtick
      final startIndex = textBeforeCursor.lastIndexOf(
        '`',
        textBeforeCursor.length - 2,
      );

      if (startIndex != -1 && startIndex < textBeforeCursor.length - 1) {
        _saveHistory(force: true);

        // Content between backticks
        final content = textBeforeCursor.substring(
          startIndex + 1,
          textBeforeCursor.length - 1,
        );

        // 1. Delete the full range [startIndex, _cursorOffset] which includes backticks
        _deleteRangeInParagraph(paragraph, startIndex, _cursorOffset);
        _cursorOffset = startIndex;

        // 2. Insert content with monospace font
        final oldAttrs = _activeAttributes;
        _activeAttributes = oldAttrs.copyWith(fontFamily: 'Courier Prime');

        _insertTextNoHistory(content);

        // 3. Restore attributes for subsequent typing
        // Note: insertTextNoHistory usually advances cursor.
        // We restore active attributes to original.
        _activeAttributes = oldAttrs;

        _isDirty = true;
        notifyListeners();
        return;
      }
    }

    // Bold (**)
    if (textBeforeCursor.endsWith('**') && textBeforeCursor.length > 2) {
      final startIndex = textBeforeCursor.lastIndexOf(
        '**',
        textBeforeCursor.length - 3,
      );
      if (startIndex != -1 && startIndex < textBeforeCursor.length - 2) {
        _applyInlineStyle(startIndex, _cursorOffset, bold: true);
      }
    }
    // Italic (*)
    else if (textBeforeCursor.endsWith('*') && textBeforeCursor.length > 1) {
      // Avoid triggering on first * of **
      if (textBeforeCursor.length >= 2 &&
          textBeforeCursor[textBeforeCursor.length - 2] == '*') {
        return;
      }

      final startIndex = textBeforeCursor.lastIndexOf(
        '*',
        textBeforeCursor.length - 2,
      );
      if (startIndex != -1 && startIndex < textBeforeCursor.length - 1) {
        // Ensure no adjacent asterisks to avoid messing up Bold
        if (startIndex > 0 && textBeforeCursor[startIndex - 1] == '*') return;
        if (startIndex < textBeforeCursor.length - 1 &&
            textBeforeCursor[startIndex + 1] == '*') {
          return;
        }

        _applyInlineStyle(startIndex, _cursorOffset, italic: true);
      }
    }
  }

  void _applyInlineStyle(int start, int end, {bool? bold, bool? italic}) {
    _saveHistory(force: true);

    int delimiterLength = bold == true ? 2 : 1;
    final paragraph = _document.paragraphs[_cursorParagraphIndex];

    // Remove closing delimiter first (so start index remains stable)
    _deleteRangeInParagraph(paragraph, end - delimiterLength, end);
    // Remove opening delimiter
    _deleteRangeInParagraph(paragraph, start, start + delimiterLength);

    // Apply style to the text
    _selectionAnchorParagraphIndex = _cursorParagraphIndex;
    _selectionAnchorOffset = start;
    _cursorOffset = start + (end - start - (delimiterLength * 2));

    _applyStyleToSelection(
      (attr) =>
          attr.copyWith(bold: bold ?? attr.bold, italic: italic ?? attr.italic),
    );

    // Clear selection and set cursor
    _selectionAnchorParagraphIndex = null;
    _selectionAnchorOffset = null;
    // Cursor is already at the end of the styled text

    _activeAttributes = _activeAttributes.copyWith(
      bold: bold == true ? false : _activeAttributes.bold,
      italic: italic == true ? false : _activeAttributes.italic,
    );
  }

  int getDocumentOffset(int pIdx, int offset) {
    int global = 0;
    for (int i = 0; i < pIdx; i++) {
      global += _document.paragraphs[i].text.length + 1; // +1 for newline
    }
    return global + offset;
  }

  (int, int) fromDocumentOffset(int global) {
    int current = 0;
    for (int i = 0; i < _document.paragraphs.length; i++) {
      final text = _document.paragraphs[i].text;
      if (global <= current + text.length) {
        return (i, global - current);
      }
      current += text.length + 1;
    }
    return (
      _document.paragraphs.length - 1,
      _document.paragraphs.last.text.length,
    );
  }

  String getFullText() {
    return _document.paragraphs.map((p) => p.text).join('\n');
  }
}

// Top-level function for background isolate execution
Document parseTextToDocument(String text) {
  // Basic text importer: splits by newlines into paragraphs
  // Preserves empty lines as empty paragraphs
  final lines = text.split('\n');
  final paragraphs = lines.map((line) {
    // Replace tabs with 4 spaces for basic alignment preservation
    // Strip Zero-Width Space (U+200B) and Carriage Return
    final sanitizedLine = line
        .replaceAll('\t', '    ')
        .replaceAll('\r', '')
        .replaceAll('\u200b', '');
    return Paragraph(
      runs: [
        TextRun(
          text: sanitizedLine,
          attributes: const TextAttributes(), // Default style
        ),
      ],
      // Explicitly set line spacing to 1.0 to match editor defaults
      lineSpacing: 1.0,
    );
  }).toList();

  if (paragraphs.isEmpty) {
    return Document.empty();
  }
  return Document(paragraphs: paragraphs);
}

Document parseMarkdownToDocument(String text) {
  final sanitizedText = text.replaceAll('\r', '');
  final lines = sanitizedText.split('\n');
  final mdDocument = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );

  final paragraphs = <Paragraph>[];
  List<String> currentBlock = [];
  bool isInCodeBlock = false;

  for (final line in lines) {
    if (line.trim().startsWith('```')) {
      isInCodeBlock = !isInCodeBlock;
    }

    if (line.isEmpty && !isInCodeBlock) {
      if (currentBlock.isNotEmpty) {
        _convertNodesToParagraphs(
          mdDocument.parseLines(currentBlock),
          paragraphs,
        );
        currentBlock = [];
      }
      paragraphs.add(
        Paragraph(
          runs: [TextRun(text: '', attributes: const TextAttributes())],
          type: ParagraphType.normal,
          lineSpacing: 1.0,
        ),
      );
    } else {
      currentBlock.add(line);
    }
  }

  if (currentBlock.isNotEmpty) {
    _convertNodesToParagraphs(mdDocument.parseLines(currentBlock), paragraphs);
  }

  if (paragraphs.isEmpty) return Document.empty();
  return Document(paragraphs: paragraphs);
}

void _convertNodesToParagraphs(
  List<md.Node> nodes,
  List<Paragraph> paragraphs,
) {
  for (final node in nodes) {
    if (node is md.Element) {
      _convertElementToParagraphs(node, paragraphs);
    } else if (node is md.Text) {
      final sanitizedNodeText = node.text.trim();
      if (sanitizedNodeText.isNotEmpty) {
        bool isCentered = false;
        String text = node.text.replaceAll('\u200b', '');

        if (text.trim().startsWith('<center>') &&
            text.trim().endsWith('</center>')) {
          isCentered = true;
          String trimmedText = text.trim();
          String remaining = trimmedText.substring(8, trimmedText.length - 9);
          text = remaining;
        }

        paragraphs.add(
          Paragraph(
            runs: [TextRun(text: text, attributes: const TextAttributes())],
            type: ParagraphType.normal,
            alignment: isCentered
                ? ParagraphAlignment.center
                : ParagraphAlignment.left,
          ),
        );
      }
    }
  }
}

void _convertElementToParagraphs(
  md.Element element,
  List<Paragraph> paragraphs, {
  int indentLevel = 0,
}) {
  // Check for <center> tag if it's not the primary element but wraps the content
  bool isCentered = element.tag == 'center';

  // 1. Determine Paragraph Type and Attributes based on tag
  ParagraphType type = ParagraphType.normal;
  double? fontSize;
  bool isBold = false;

  final runs = <TextRun>[];

  switch (element.tag) {
    case 'center':
      // Collect children paragraphs first
      final blockChildren =
          element.children?.whereType<md.Element>().toList() ?? [];
      if (blockChildren.isNotEmpty) {
        for (var child in blockChildren) {
          final childParagraphs = <Paragraph>[];
          _convertElementToParagraphs(
            child,
            childParagraphs,
            indentLevel: indentLevel,
          );
          for (var childP in childParagraphs) {
            paragraphs.add(
              Paragraph(
                runs: childP.runs,
                type: childP.type,
                alignment: ParagraphAlignment.center,
                lineSpacing: childP.lineSpacing,
                indent: childP.indent,
              ),
            );
          }
        }
        return;
      }
      break;
    case 'pre':
      // Code Block
      final codeElement = element.children?.firstWhere(
        (c) => c is md.Element && c.tag == 'code',
        orElse: () => md.Text(''),
      );
      if (codeElement != null && codeElement is md.Element) {
        final codeRuns = <TextRun>[];
        _collectRuns(
          codeElement,
          codeRuns,
          TextAttributes(fontSize: fontSize, bold: isBold, monospace: true),
        );

        // Trim trailing newline if present to avoid extra line in editor
        if (codeRuns.isNotEmpty) {
          final lastRun = codeRuns.last;
          if (lastRun.text.endsWith('\n')) {
            codeRuns[codeRuns.length - 1] = TextRun(
              text: lastRun.text.substring(0, lastRun.text.length - 1),
              attributes: lastRun.attributes,
            );
          }
        }

        paragraphs.add(
          Paragraph(
            runs: codeRuns,
            type: ParagraphType.codeBlock,
            lineSpacing: 1.0,
            indent: indentLevel,
          ),
        );
        return;
      }
      break;
    case 'h1':
      fontSize = 32.0;
      isBold = true;
      break;
    case 'h2':
      fontSize = 26.0;
      isBold = true;
      break;
    case 'h3':
      fontSize = 20.0;
      isBold = true;
      break;
    case 'h4':
      fontSize = 16.0;
      isBold = true;
      break;
    case 'h5':
      fontSize = 14.0;
      isBold = true;
      break;
    case 'h6':
      fontSize = 13.0;
      isBold = true;
      break;
    case 'blockquote':
      type = ParagraphType.blockquote;
      break;
    case 'hr':
      paragraphs.add(
        Paragraph(
          runs: [TextRun(text: '', attributes: const TextAttributes())],
          type: ParagraphType.horizontalRule,
          lineSpacing: 1.0,
        ),
      );
      return;
    case 'ul':
    case 'ol':
      final listType = element.tag == 'ol'
          ? ParagraphType.numberedList
          : ParagraphType.bulletList;

      int listCounter = 1;

      for (final child in element.children!) {
        if (child is md.Element && child.tag == 'li') {
          final runs = <TextRun>[];
          if (child.children != null) {
            for (final liNode in child.children!) {
              if (liNode is md.Element &&
                  (liNode.tag == 'ul' || liNode.tag == 'ol')) {
                continue;
              }
              _collectRuns(liNode, runs, TextAttributes());
            }
          }

          if (runs.isNotEmpty) {
            paragraphs.add(
              Paragraph(
                runs: runs,
                type: listType,
                lineSpacing: 1.0,
                indent: indentLevel,
                listIndex: listType == ParagraphType.numberedList
                    ? listCounter
                    : null,
              ),
            );
            if (listType == ParagraphType.numberedList) listCounter++;
          } else if (child.children?.isEmpty ?? true) {
            paragraphs.add(
              Paragraph(
                runs: [TextRun(text: '', attributes: const TextAttributes())],
                type: listType,
                lineSpacing: 1.0,
                indent: indentLevel,
                listIndex: listType == ParagraphType.numberedList
                    ? listCounter
                    : null,
              ),
            );
            if (listType == ParagraphType.numberedList) listCounter++;
          }

          if (child.children != null) {
            for (final liNode in child.children!) {
              if (liNode is md.Element &&
                  (liNode.tag == 'ul' || liNode.tag == 'ol')) {
                _convertElementToParagraphs(
                  liNode,
                  paragraphs,
                  indentLevel: indentLevel + 1,
                );
              }
            }
          }
        }
      }
      return;
    case 'p':
      break;
    default:
      break;
  }

  _collectRuns(element, runs, TextAttributes(fontSize: fontSize, bold: isBold));

  if (runs.isNotEmpty || type == ParagraphType.codeBlock) {
    if (type == ParagraphType.blockquote) {
      bool hasBlockChildren =
          element.children?.any(
            (c) =>
                c is md.Element &&
                (c.tag == 'p' || c.tag == 'ul' || c.tag == 'h1'),
          ) ??
          false;

      if (hasBlockChildren) {
        final blockChildren = element.children!
            .whereType<md.Element>()
            .toList();
        for (int i = 0; i < blockChildren.length; i++) {
          final child = blockChildren[i];
          final childParagraphs = <Paragraph>[];
          _convertElementToParagraphs(child, childParagraphs);
          for (var p in childParagraphs) {
            paragraphs.add(
              Paragraph(
                runs: p.runs,
                type: ParagraphType.blockquote,
                alignment: p.alignment,
                lineSpacing: p.lineSpacing,
                indent: indentLevel,
              ),
            );
          }
          if (i < blockChildren.length - 1) {
            paragraphs.add(
              Paragraph(
                runs: [TextRun(text: '', attributes: const TextAttributes())],
                type: ParagraphType.blockquote,
                lineSpacing: 1.0,
                indent: indentLevel,
              ),
            );
          }
        }
        return;
      }
    }
  }

  // Robust <center> detection
  String combined = runs.map((r) => r.text).join('').trim();
  if (isCentered ||
      (combined.startsWith('<center>') && combined.endsWith('</center>'))) {
    isCentered = true;
    if (combined.startsWith('<center>') && runs.isNotEmpty) {
      String firstText = runs.first.text.trimLeft();
      if (firstText.startsWith('<center>')) {
        String remaining = firstText.replaceFirst('<center>', '');
        runs[0] = TextRun(text: remaining, attributes: runs.first.attributes);
      }
      String lastText = runs.last.text.trimRight();
      if (lastText.endsWith('</center>')) {
        String remaining = lastText.substring(0, lastText.length - 9);
        runs[runs.length - 1] = TextRun(
          text: remaining,
          attributes: runs.last.attributes,
        );
      }
    }
  }

  paragraphs.add(
    Paragraph(
      runs: runs,
      type: type,
      lineSpacing: 1.0,
      indent: indentLevel,
      alignment: isCentered
          ? ParagraphAlignment.center
          : ParagraphAlignment.left,
    ),
  );
}

void _collectRuns(
  md.Node node,
  List<TextRun> runs,
  TextAttributes currentAttrs,
) {
  if (node is md.Text) {
    final sanitizedText = node.text.replaceAll('\u200b', '');
    runs.add(TextRun(text: sanitizedText, attributes: currentAttrs));
  } else if (node is md.Element) {
    if (node.tag == 'input') {
      final isChecked = node.attributes['checked'] == 'true';
      runs.add(
        TextRun(text: isChecked ? '[x] ' : '[ ] ', attributes: currentAttrs),
      );
    }

    TextAttributes newAttrs = currentAttrs;
    if (node.tag == 'strong' || node.tag == 'b') {
      newAttrs = currentAttrs.copyWith(bold: true);
    } else if (node.tag == 'em' || node.tag == 'i') {
      newAttrs = currentAttrs.copyWith(italic: true);
    } else if (node.tag == 'code') {
      newAttrs = currentAttrs.copyWith(monospace: true);
    } else if (node.tag == 'a') {
      final url = node.attributes['href'];
      newAttrs = currentAttrs.copyWith(linkUrl: url);
    } else if (node.tag == 'center') {
      // Inline centering is odd, but let's handle it if it occurs
    }

    if (node.children != null) {
      for (var child in node.children!) {
        _collectRuns(child, runs, newAttrs);
      }
    }
  }
}
