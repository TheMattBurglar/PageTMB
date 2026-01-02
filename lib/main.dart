import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'app_theme.dart';
import 'constants.dart';
import 'widgets/editor_page.dart';
import 'widgets/find_replace_bar.dart';
import 'logic/editor_controller.dart';
import 'logic/paginator.dart';
import 'widgets/editor_toolbar.dart';
import 'models/document.dart';

void main() {
  runApp(const PageTMBApp());
}

class PageTMBApp extends StatelessWidget {
  const PageTMBApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PageTMB',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const MainEditorPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainEditorPage extends StatefulWidget {
  const MainEditorPage({super.key});

  @override
  State<MainEditorPage> createState() => _MainEditorPageState();
}

class _MainEditorPageState extends State<MainEditorPage> with TextInputClient {
  late EditorController _controller;
  final FocusNode _focusNode = FocusNode();
  TextInputConnection? _connection;
  TextEditingValue? _lastSentValue;
  TextRange _lastComposing = TextRange.empty;
  bool _isHandlingTextInput = false;

  final ScrollController _scrollController = ScrollController();
  int _lastSearchIndex = -1;
  int _lastCursorParagraphIndex = -1;
  int _lastCursorOffset = -1;

  bool _showFindBar = false;

  // Anti-Bounce State
  int _scrolledCursorP = -1;
  int _scrolledCursorOffset = -1;
  double _scrolledZoom = -1;

  // Pagination Cache & Zoom
  List<List<Paragraph>>? _cachedPages;
  int _lastPaginatedVersion = -1;
  EdgeInsets? _lastPaginatedMargins;
  double _zoomLevel = 1.3;

  // Virtualization State
  int _firstVisiblePage = 0;
  int _lastVisiblePage = 1;

  @override
  void initState() {
    super.initState();
    _controller = EditorController();
    _controller.addListener(_onControllerUpdate);
    // Initialize with mode defaults
    _controller.applyModeDefaults(
      lineSpacing: _getLineSpacing(),
      fontFamily: _getFontFamily(),
    );

    _scrollController.addListener(_onScroll);
    _focusNode.addListener(_handleFocusChange);

    // Initial calculation (post-frame to get viewport height if needed,
    // but better to start with safe defaults or try immediately)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateVisiblePages();
    });
  }

  void _onScroll() {
    _updateVisiblePages();
  }

  void _updateVisiblePages() {
    if (!_scrollController.hasClients) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final scrollOffset = _scrollController.offset;
    final scaledPageHeight = (PageConstants.pageHeight + 20.0) * _zoomLevel;

    final first = (scrollOffset / scaledPageHeight).floor();
    final last = ((scrollOffset + viewportHeight) / scaledPageHeight).ceil();

    if (first != _firstVisiblePage || last != _lastVisiblePage) {
      if (mounted) {
        setState(() {
          _firstVisiblePage = first;
          _lastVisiblePage = last;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _scrollController.dispose();
    _connection?.close();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      _openKeyboard();
    } else {
      _closeKeyboard();
    }
  }

  void _openKeyboard({bool force = false}) {
    if (_connection == null || !_connection!.attached || force) {
      if (force) {
        _connection?.close();
        _connection = null; // Mark as null so we definitely re-attach
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_focusNode.hasFocus) return;

        // Re-check connection in case it was attached in the meantime
        if (_connection == null || !_connection!.attached) {
          _connection = TextInput.attach(
            this,
            const TextInputConfiguration(
              inputType: TextInputType.multiline,
              inputAction: TextInputAction.newline,
              enableSuggestions: true,
              autocorrect: true,
            ),
          );
          _connection!.show();
          _lastSentValue = null;
          _updateTextInputState();
        }
      });
    }
  }

  void _closeKeyboard() {
    _connection?.close();
    _connection = null;
    _lastSentValue = null;
  }

  void _updateTextInputState({TextRange? composing}) {
    if (_connection != null && _connection!.attached) {
      final text = _controller.getFullText();
      final offset = _controller.getDocumentOffset(
        _controller.cursorParagraphIndex,
        _controller.cursorOffset,
      );

      TextSelection selection;
      if (_controller.hasSelection) {
        final anchor = _controller.getDocumentOffset(
          _controller.selectionAnchorParagraphIndex!,
          _controller.selectionAnchorOffset!,
        );
        selection = TextSelection(baseOffset: anchor, extentOffset: offset);
      } else {
        selection = TextSelection.collapsed(offset: offset);
      }

      final newValue = TextEditingValue(
        text: text,
        selection: selection,
        composing: composing ?? _lastComposing,
      );

      // Only sync if significantly different to avoid flickering/feedback loops
      if (_lastSentValue == null ||
          _lastSentValue!.text != newValue.text ||
          _lastSentValue!.selection != newValue.selection ||
          _lastSentValue!.composing != newValue.composing) {
        _lastSentValue = newValue;
        _connection!.setEditingState(newValue);
      }
    }
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    _isHandlingTextInput = true;
    try {
      _lastComposing = value.composing;
      final oldText = _controller.getFullText();

      if (value.text == oldText) {
        // Selection change only
        final (pIdx, offset) = _controller.fromDocumentOffset(
          value.selection.baseOffset,
        );
        _controller.setCursor(pIdx, offset);
        _lastSentValue = value;
        return;
      }

      // Basic diffing to handle simple edits without losing formatting
      int commonPrefix = 0;
      while (commonPrefix < oldText.length &&
          commonPrefix < value.text.length &&
          oldText[commonPrefix] == value.text[commonPrefix]) {
        commonPrefix++;
      }

      int commonSuffix = 0;
      while (commonSuffix < oldText.length - commonPrefix &&
          commonSuffix < value.text.length - commonPrefix &&
          oldText[oldText.length - 1 - commonSuffix] ==
              value.text[value.text.length - 1 - commonSuffix]) {
        commonSuffix++;
      }

      final deletedCount = oldText.length - commonPrefix - commonSuffix;
      final insertedText = value.text.substring(
        commonPrefix,
        value.text.length - commonSuffix,
      );

      if (deletedCount > 0 || insertedText.isNotEmpty) {
        _controller.replaceRange(
          commonPrefix,
          commonPrefix + deletedCount,
          insertedText,
        );
      }

      // Finally sync cursor position from value
      final (pFinal, offsetFinal) = _controller.fromDocumentOffset(
        value.selection.baseOffset,
      );
      _controller.setCursor(pFinal, offsetFinal);

      _lastSentValue = value;
      _updateTextInputState(composing: value.composing);
    } finally {
      _isHandlingTextInput = false;
    }
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline || action == TextInputAction.done) {
      _controller.insertText('\n');
    }
  }

  @override
  void connectionClosed() {
    _connection = null;
    _lastSentValue = null;
  }

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue? get currentTextEditingValue {
    final text = _controller.getFullText();
    final offset = _controller.getDocumentOffset(
      _controller.cursorParagraphIndex,
      _controller.cursorOffset,
    );
    TextSelection selection;
    if (_controller.hasSelection) {
      final anchor = _controller.getDocumentOffset(
        _controller.selectionAnchorParagraphIndex!,
        _controller.selectionAnchorOffset!,
      );
      selection = TextSelection(baseOffset: anchor, extentOffset: offset);
    } else {
      selection = TextSelection.collapsed(offset: offset);
    }
    return TextEditingValue(text: text, selection: selection);
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}
  @override
  void showToolbar() {}
  @override
  void insertContent(KeyboardInsertedContent content) {}
  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  void _onControllerUpdate() {
    setState(() {});
    if (!_isHandlingTextInput) {
      _updateTextInputState(composing: TextRange.empty);
    }

    bool cursorChanged =
        _controller.cursorParagraphIndex != _lastCursorParagraphIndex ||
        _controller.cursorOffset != _lastCursorOffset;

    if (cursorChanged || _controller.currentSearchIndex != _lastSearchIndex) {
      _lastSearchIndex = _controller.currentSearchIndex;
      _lastCursorParagraphIndex = _controller.cursorParagraphIndex;
      _lastCursorOffset = _controller.cursorOffset;

      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCursor());
    }
  }

  void _scrollToCursor() {
    if (!_scrollController.hasClients) return;

    final cursorP = _controller.cursorParagraphIndex;
    final margins = _getMargins();
    final pages =
        _cachedPages ?? Paginator.paginate(_controller.document, margins);

    int pageIndex = -1;
    int pIndexInPage = -1;
    List<Paragraph> paragraphsInPage = [];

    for (int i = 0; i < pages.length; i++) {
      final paragraphs = pages[i];
      for (int j = 0; j < paragraphs.length; j++) {
        final p = paragraphs[j];
        if (p.originalIndex == cursorP) {
          int pLen = 0;
          for (var r in p.runs) {
            pLen += r.text.length;
          }
          final start = p.offsetInOriginal;
          final end = start + pLen;
          if (_controller.cursorOffset >= start &&
              _controller.cursorOffset <= end) {
            pageIndex = i;
            pIndexInPage = j;
            paragraphsInPage = paragraphs;
            break;
          }
        }
      }
      if (pageIndex != -1) break;
    }

    if (pageIndex != -1) {
      // Prevent conflict: If page is visible, rely on precise _handleCaretUpdate instead of heuristic
      if (pageIndex >= _firstVisiblePage - 1 &&
          pageIndex <= _lastVisiblePage + 1) {
        return;
      }

      final scaledPageHeight = (PageConstants.pageHeight + 20.0) * _zoomLevel;
      final pageTop =
          (pageIndex * (PageConstants.pageHeight + 20.0) + 20.0) * _zoomLevel;

      double targetY = pageTop;

      // Heuristic to estimate cursor Y within the document
      if (pIndexInPage != -1 && paragraphsInPage.isNotEmpty) {
        // Approx Y offset within page based on paragraph index
        double ratio = pIndexInPage / paragraphsInPage.length;
        targetY += ratio * scaledPageHeight;
      }

      final double currentScroll = _scrollController.offset;
      final double viewportHeight =
          _scrollController.position.viewportDimension;
      const double padding = 80.0; // Buffer to keep cursor away from edges

      double requiredScroll = currentScroll;

      if (targetY < currentScroll + padding ||
          targetY > currentScroll + viewportHeight - padding) {
        // Cursor is near edge or off-screen: Snap to center
        requiredScroll = targetY - (viewportHeight / 2);
      } else {
        // Cursor is comfortably visible, do nothing
        return;
      }

      // Clamp scroll value
      if (requiredScroll < 0) requiredScroll = 0;
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (requiredScroll > maxScroll) requiredScroll = maxScroll;

      // Only animate if the change is significant
      if ((requiredScroll - currentScroll).abs() > 5.0) {
        _scrollController.animateTo(
          requiredScroll,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _handleCaretUpdate(Offset localOffset, int pageIndex) {
    if (!_scrollController.hasClients || _cachedPages == null) return;

    // Fix for "Bounce Back" on Scroll:
    // Only auto-scroll if the cursor logically moved or zoom changed.
    // If the user is just scrolling, the virtualizer will rebuild pages,
    // triggering this callback with the SAME cursor position.
    // We must ignore those to prevent fighting the user's scroll.
    if (_controller.cursorParagraphIndex == _scrolledCursorP &&
        _controller.cursorOffset == _scrolledCursorOffset &&
        _zoomLevel == _scrolledZoom) {
      return;
    }
    _scrolledCursorP = _controller.cursorParagraphIndex;
    _scrolledCursorOffset = _controller.cursorOffset;
    _scrolledZoom = _zoomLevel;

    final double scaledPageHeight =
        (PageConstants.pageHeight + 20.0) * _zoomLevel;
    final double pageTop = (pageIndex * scaledPageHeight) + (20.0 * _zoomLevel);

    // Safety Force: Ensure local offset is within the page bounds.
    // If layout overflowed or glitched, this prevents scrolling into the void.
    // We clamp to slightly less than full height to be safe.
    final double clampedLocalY = localOffset.dy.clamp(0.0, scaledPageHeight);
    final double globalY = pageTop + clampedLocalY;

    final double currentScroll = _scrollController.offset;
    final double viewportHeight = _scrollController.position.viewportDimension;
    const double padding = 80.0;

    double requiredScroll = currentScroll;

    // "Push" logic: Keep cursor in the middle 60% of screen.
    // Minimizes large jumps which can disorient virtualization.
    if (globalY < currentScroll + padding) {
      // Hit top edge: Position cursor at 20% down
      requiredScroll = globalY - (viewportHeight * 0.2);
    } else if (globalY > currentScroll + viewportHeight - padding) {
      // Hit bottom edge: Position cursor at 80% down
      requiredScroll = globalY - (viewportHeight * 0.8);
    } else {
      return;
    }

    // Manual Clamp against document structure to avoid overscrolling into blank space
    // if controller state is slightly stale.
    final double totalHeight = _cachedPages!.length * scaledPageHeight;
    final double theoreticalMax = totalHeight - viewportHeight;

    if (requiredScroll < 0) requiredScroll = 0;

    // Prefer theoretical limit if it prevents "disappearance",
    // but respect controller max if valid.
    final double controllerMax = _scrollController.position.maxScrollExtent;

    double limit = controllerMax;
    if (theoreticalMax > 0 && theoreticalMax < controllerMax) {
      // If theory says content is smaller than controller thinks, trust theory to avoid blank.
      limit = theoreticalMax;
    }

    if (requiredScroll > limit) requiredScroll = limit;

    if ((requiredScroll - currentScroll).abs() > 5.0) {
      _scrollController.animateTo(
        requiredScroll,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _setMode(EditorMode mode) {
    _controller.currentMode = mode;
  }

  void _setFont(String font) {
    _controller.selectedFreestyleFont = font;
  }

  double _getLineSpacing() {
    return (_controller.currentMode == EditorMode.manuscript ||
            _controller.currentMode == EditorMode.essay)
        ? 2.0
        : 1.0;
  }

  String _getFontFamily() {
    switch (_controller.currentMode) {
      case EditorMode.screenplay:
        return PageConstants.screenplayFont;
      case EditorMode.manuscript:
        return PageConstants.manuscriptFont;
      case EditorMode.essay:
        return PageConstants.essayFont;
      case EditorMode.freestyle:
        return _controller.selectedFreestyleFont;
    }
  }

  String _getModeName(EditorMode mode) {
    switch (mode) {
      case EditorMode.manuscript:
        return 'Manuscript';
      case EditorMode.screenplay:
        return 'Screenplay';
      case EditorMode.essay:
        return 'Essay';
      case EditorMode.freestyle:
        return 'Freestyle';
    }
  }

  void _showDocumentInfoDialog() {
    final titleController = TextEditingController(text: _controller.title);
    final authorController = TextEditingController(text: _controller.author);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Document Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Enter document title',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: authorController,
              decoration: const InputDecoration(
                labelText: 'Author',
                hintText: 'Enter author name',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _controller.title = titleController.text;
              _controller.author = authorController.text;
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  EdgeInsets _getMargins() {
    switch (_controller.currentMode) {
      case EditorMode.screenplay:
        return PageConstants.screenplayMargins;
      case EditorMode.manuscript:
        return PageConstants.manuscriptMargins;
      case EditorMode.essay:
        return PageConstants.essayMargins;
      case EditorMode.freestyle:
        return PageConstants.freestyleMargins;
    }
  }

  @override
  Widget build(BuildContext context) {
    final margins = _getMargins();
    if (_cachedPages == null ||
        _lastPaginatedVersion != _controller.documentVersion ||
        _lastPaginatedMargins != margins) {
      _cachedPages = Paginator.paginate(_controller.document, margins);
      _lastPaginatedVersion = _controller.documentVersion;
      _lastPaginatedMargins = margins;
    }
    final pages = _cachedPages!;

    int paragraphOffset = 0;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          setState(() {
            _showFindBar = !_showFindBar;
            if (!_showFindBar) {
              _controller.clearSearch();
              _focusNode.requestFocus();
            }
          });
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_showFindBar) {
            setState(() {
              _showFindBar = false;
              _controller.clearSearch();
              _focusNode.requestFocus();
            });
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () {
          _controller.printDocument(
            _getMargins(),
            _getModeName(_controller.currentMode),
          );
        },
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('PageTMB - ${_getModeName(_controller.currentMode)}'),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.description_outlined), // File Icon
              tooltip: 'File',
              onSelected: (value) {
                switch (value) {
                  case 'new':
                    _controller.newFile();
                    break;
                  case 'open':
                    _controller.openFile();
                    break;
                  case 'save':
                    _controller.saveFile();
                    break;
                  case 'save_as':
                    _controller.saveFileAs();
                    break;
                  case 'export_pdf':
                    _controller.exportToPdf(
                      _getMargins(),
                      _getModeName(_controller.currentMode),
                    );
                    break;
                  case 'export_docx':
                    _controller.exportToDocx(_getMargins(), _getFontFamily());
                    break;
                  case 'export_markdown':
                    _controller.exportToMarkdown();
                    break;
                  case 'print':
                    _controller.printDocument(
                      _getMargins(),
                      _getModeName(_controller.currentMode),
                    );
                    break;
                  case 'doc_info':
                    _showDocumentInfoDialog();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'print',
                  child: ListTile(
                    leading: Icon(Icons.print),
                    title: Text('Print...'),
                    trailing: Text(
                      'Ctrl+P',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'new',
                  child: ListTile(
                    leading: Icon(Icons.note_add),
                    title: Text('New'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'open',
                  child: ListTile(
                    leading: Icon(Icons.folder_open),
                    title: Text('Open...'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'save',
                  child: ListTile(
                    leading: Icon(Icons.save),
                    title: Text('Save'),
                    trailing: Text(
                      'Ctrl+S',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ),
                const PopupMenuItem(
                  value: 'save_as',
                  child: ListTile(
                    leading: Icon(Icons.save_as),
                    title: Text('Save As...'),
                    trailing: Text(
                      'Ctrl+Shift+S',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ),
                const PopupMenuItem(
                  value: 'export_pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf),
                    title: Text('Export to PDF...'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'export_docx',
                  child: ListTile(
                    leading: Icon(Icons.description),
                    title: Text('Export to DOCX...'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'export_markdown',
                  child: ListTile(
                    leading: Icon(Icons.code),
                    title: Text('Export to Markdown...'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'doc_info',
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Document Info...'),
                  ),
                ),
              ],
            ),
            PopupMenuButton<EditorMode>(
              onSelected: _setMode,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: EditorMode.freestyle,
                  child: Text('Freestyle'),
                ),
                const PopupMenuItem(
                  value: EditorMode.manuscript,
                  child: Text('Manuscript'),
                ),
                const PopupMenuItem(
                  value: EditorMode.screenplay,
                  child: Text('Screenplay'),
                ),
                const PopupMenuItem(
                  value: EditorMode.essay,
                  child: Text('Essay'),
                ),
              ],
              icon: const Icon(Icons.mode_edit),
              tooltip: 'Switch Mode',
            ),
            PopupMenuButton<String>(
              enabled: _controller.currentMode == EditorMode.freestyle,
              onSelected: _setFont,
              itemBuilder: (context) => PageConstants.allAvailableFonts
                  .map(
                    (font) => PopupMenuItem(
                      value: font,
                      child: Text(font, style: TextStyle(fontFamily: font)),
                    ),
                  )
                  .toList(),
              icon: Icon(
                Icons.font_download,
                color: _controller.currentMode == EditorMode.freestyle
                    ? Colors.black
                    : Colors.grey,
              ),
              tooltip: 'Change Font',
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                EditorToolbar(
                  controller: _controller,
                  zoomLevel: _zoomLevel,
                  onZoomChanged: (val) {
                    setState(() {
                      _zoomLevel = val;
                      _updateVisiblePages();
                    });
                  },
                ),
                Expanded(
                  child: Focus(
                    focusNode: _focusNode,
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent || event is KeyRepeatEvent) {
                        final isControlPressed =
                            HardwareKeyboard.instance.isControlPressed ||
                            HardwareKeyboard.instance.isMetaPressed;
                        final isShiftPressed =
                            HardwareKeyboard.instance.isShiftPressed;

                        // Handle Shortcuts (Ctrl + ...)
                        if (isControlPressed) {
                          if (event.logicalKey == LogicalKeyboardKey.keyB) {
                            _controller.toggleBold();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.keyI) {
                            _controller.toggleItalic();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.keyU) {
                            _controller.toggleUnderline();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.keyA) {
                            _controller.selectAll();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.keyZ) {
                            if (isShiftPressed) {
                              _controller.redo();
                            } else {
                              _controller.undo();
                            }
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.keyY) {
                            _controller.redo();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.keyX) {
                            _controller.cutSelection();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.keyC) {
                            _controller.copySelection();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.keyV) {
                            _controller.pasteFromClipboard();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.keyS) {
                            if (isShiftPressed) {
                              _controller.saveFileAs();
                            } else {
                              _controller.saveFile();
                            }
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.keyO) {
                            _controller.openFile();
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.home) {
                            _controller.moveToStart(
                              extendSelection: isShiftPressed,
                            );
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _scrollToCursor();
                            });
                            return KeyEventResult.handled;
                          } else if (event.logicalKey ==
                              LogicalKeyboardKey.end) {
                            _controller.moveToEnd(
                              extendSelection: isShiftPressed,
                            );
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _scrollToCursor();
                            });
                            return KeyEventResult.handled;
                          }
                        }

                        final margins = _getMargins();
                        final layoutWidth =
                            PageConstants.pageWidth -
                            margins.left -
                            margins.right;

                        if (event.logicalKey == LogicalKeyboardKey.backspace) {
                          _controller.deleteText();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.delete) {
                          _controller.deleteForward();
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowLeft) {
                          _controller.moveCursorLeft(
                            extendSelection: isShiftPressed,
                          );
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowRight) {
                          _controller.moveCursorRight(
                            extendSelection: isShiftPressed,
                          );
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowUp) {
                          _controller.moveCursorUp(
                            extendSelection: isShiftPressed,
                            layoutWidth: layoutWidth,
                          );
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.arrowDown) {
                          _controller.moveCursorDown(
                            extendSelection: isShiftPressed,
                            layoutWidth: layoutWidth,
                          );
                          return KeyEventResult.handled;
                        } else if (event.logicalKey == LogicalKeyboardKey.tab) {
                          _controller.insertText('\t');
                          return KeyEventResult.handled;
                        } else if (event.logicalKey ==
                            LogicalKeyboardKey.enter) {
                          _controller.insertText('\n');
                          return KeyEventResult.handled;
                        } else if (event.character != null &&
                            !isControlPressed &&
                            event.logicalKey != LogicalKeyboardKey.escape) {
                          _controller.insertText(event.character!);
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      child: Listener(
                        onPointerSignal: (pointerSignal) {
                          if (pointerSignal is PointerScrollEvent) {
                            if (HardwareKeyboard.instance.isControlPressed) {
                              setState(() {
                                if (pointerSignal.scrollDelta.dy < 0) {
                                  _zoomLevel = (_zoomLevel + 0.1).clamp(
                                    1.0,
                                    3.0,
                                  );
                                } else {
                                  _zoomLevel = (_zoomLevel - 0.1).clamp(
                                    1.0,
                                    3.0,
                                  );
                                }
                              });
                            }
                          }
                        },
                        child: MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(textScaler: TextScaler.noScaling),
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            child: Center(
                              child: SizedBox(
                                width:
                                    (PageConstants.pageWidth * _zoomLevel / 2)
                                        .roundToDouble() *
                                    2,
                                height:
                                    (((pages.length *
                                                    (PageConstants.pageHeight +
                                                        20.0)) *
                                                _zoomLevel) /
                                            2)
                                        .roundToDouble() *
                                    2,
                                child: Transform.scale(
                                  scale: _zoomLevel,
                                  alignment: Alignment.topCenter,
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: SizedBox(
                                      width: PageConstants.pageWidth,
                                      child: Column(
                                        children: pages.indexed.map((entry) {
                                          final index = entry.$1;
                                          final paragraphs = entry.$2;
                                          final currentPageParagraphOffset =
                                              paragraphOffset;
                                          paragraphOffset += paragraphs.length;

                                          // Virtualization Logic
                                          final bool isVisible =
                                              index >= _firstVisiblePage - 1 &&
                                              index <= _lastVisiblePage + 1;

                                          if (!isVisible) {
                                            return const SizedBox(
                                              height:
                                                  PageConstants.pageHeight +
                                                  20.0,
                                              width: PageConstants.pageWidth,
                                            );
                                          }

                                          return Column(
                                            children: [
                                              const SizedBox(height: 20.0),
                                              SizedBox(
                                                width: PageConstants.pageWidth,
                                                height:
                                                    PageConstants.pageHeight,
                                                child: EditorPage(
                                                  pageNumber: index + 1,
                                                  margins: margins,
                                                  paragraphs: paragraphs,
                                                  cursorParagraphIndex:
                                                      _controller
                                                          .cursorParagraphIndex,
                                                  cursorOffset:
                                                      _controller.cursorOffset,
                                                  selectionAnchorParagraphIndex:
                                                      _controller
                                                          .selectionAnchorParagraphIndex,
                                                  selectionAnchorOffset:
                                                      _controller
                                                          .selectionAnchorOffset,
                                                  pageParagraphOffset:
                                                      currentPageParagraphOffset,
                                                  zoomLevel: _zoomLevel,
                                                  editorMode:
                                                      _controller.currentMode,
                                                  metadata: _controller
                                                      .document
                                                      .metadata,
                                                  onCaretOffsetUpdated:
                                                      (offset) =>
                                                          _handleCaretUpdate(
                                                            offset,
                                                            index,
                                                          ),
                                                  onTap:
                                                      (pIdx, offset, extend) {
                                                        _controller.setCursor(
                                                          pIdx,
                                                          offset,
                                                          extendSelection:
                                                              extend,
                                                        );
                                                        _focusNode
                                                            .requestFocus();
                                                        _openKeyboard(
                                                          force: true,
                                                        );
                                                      },
                                                  onDoubleTap: (pIdx, offset) {
                                                    _controller.selectWordAt(
                                                      pIdx,
                                                      offset,
                                                    );
                                                    _focusNode.requestFocus();
                                                    _openKeyboard(force: true);
                                                  },
                                                  onSecondaryTap:
                                                      (
                                                        pIdx,
                                                        offset,
                                                        globalPosition,
                                                      ) {
                                                        if (!_controller
                                                            .isPositionSelected(
                                                              pIdx,
                                                              offset,
                                                            )) {
                                                          _controller
                                                              .selectWordAt(
                                                                pIdx,
                                                                offset,
                                                              );
                                                        }
                                                        _showContextMenu(
                                                          context,
                                                          globalPosition,
                                                        );
                                                        _focusNode
                                                            .requestFocus();
                                                      },
                                                  spellChecker:
                                                      _controller.spellChecker,
                                                  searchResults:
                                                      _controller.searchResults,
                                                  currentSearchIndex:
                                                      _controller
                                                          .currentSearchIndex,
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_showFindBar)
              Positioned(
                top: 20,
                right: 20,
                width: 400,
                child: FindReplaceBar(
                  onClose: () {
                    setState(() {
                      _showFindBar = false;
                      _controller.clearSearch();
                      _focusNode.requestFocus();
                    });
                  },
                  onFind: (query) => _controller.find(query),
                  onFindNext: (query) => _controller.findNext(query),
                  onFindPrevious: (query) => _controller.findPrevious(query),
                  onReplace: (query, replacement) =>
                      _controller.replaceCurrent(query, replacement),
                  onReplaceAll: (query, replacement) =>
                      _controller.replaceAll(query, replacement),
                  currentMatchIndex: _controller.currentSearchIndex,
                  totalMatches: _controller.searchResults.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final selectedTextNullable = await _controller.getSelectedText();
    final selectedText = (selectedTextNullable ?? '').trim();
    final bool isMisspelled =
        selectedText.isNotEmpty &&
        !selectedText.contains(' ') &&
        _controller.spellChecker.isMisspelled(selectedText);

    final List<PopupMenuItem> items = [];

    if (isMisspelled) {
      final suggestions = _controller.spellChecker.getSuggestions(selectedText);
      for (final suggestion in suggestions) {
        items.add(
          PopupMenuItem(
            onTap: () {
              _controller.insertText(suggestion);
              _focusNode.requestFocus();
            },
            child: Text(
              suggestion,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }

      if (suggestions.isEmpty) {
        items.add(
          const PopupMenuItem(
            enabled: false,
            child: Text(
              'No suggestions found',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        );
      }

      items.add(
        const PopupMenuItem(enabled: false, height: 1, child: Divider()),
      );

      items.add(
        PopupMenuItem(
          onTap: () {
            _controller.addWordToDictionary(selectedText);
            _focusNode.requestFocus();
          },
          child: const Row(
            children: [
              Icon(Icons.add_circle_outline, size: 20),
              SizedBox(width: 8),
              Text('Add to Dictionary'),
            ],
          ),
        ),
      );

      items.add(
        const PopupMenuItem(enabled: false, height: 1, child: Divider()),
      );
    }

    items.addAll([
      PopupMenuItem(
        onTap: () => _controller.cutSelection(),
        child: const Row(
          children: [
            Icon(Icons.content_cut, size: 20),
            SizedBox(width: 8),
            Text('Cut'),
          ],
        ),
      ),
      PopupMenuItem(
        onTap: () => _controller.copySelection(),
        child: const Row(
          children: [
            Icon(Icons.content_copy, size: 20),
            SizedBox(width: 8),
            Text('Copy'),
          ],
        ),
      ),
      PopupMenuItem(
        onTap: () => _controller.pasteFromClipboard(),
        child: const Row(
          children: [
            Icon(Icons.content_paste, size: 20),
            SizedBox(width: 8),
            Text('Paste'),
          ],
        ),
      ),
    ]);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      items: items,
    );
  }
}
