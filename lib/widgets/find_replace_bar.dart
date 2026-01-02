import 'package:flutter/material.dart';

class FindReplaceBar extends StatefulWidget {
  final VoidCallback onClose;
  final Function(String query) onFind;
  final Function(String query) onFindNext;
  final Function(String query) onFindPrevious;
  final Function(String query, String replacement) onReplace;
  final Function(String query, String replacement) onReplaceAll;
  final int currentMatchIndex;
  final int totalMatches;

  const FindReplaceBar({
    super.key,
    required this.onClose,
    required this.onFind,
    required this.onFindNext,
    required this.onFindPrevious,
    required this.onReplace,
    required this.onReplaceAll,
    required this.currentMatchIndex,
    required this.totalMatches,
  });

  @override
  State<FindReplaceBar> createState() => _FindReplaceBarState();
}

class _FindReplaceBarState extends State<FindReplaceBar> {
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  final FocusNode _findFocusNode = FocusNode();
  bool _isReplaceExpanded = false;

  @override
  void initState() {
    super.initState();
    // Request focus when the widget is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _findFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    _findFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isReplaceExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  onPressed: () {
                    setState(() {
                      _isReplaceExpanded = !_isReplaceExpanded;
                    });
                  },
                  tooltip: _isReplaceExpanded ? 'Hide Replace' : 'Show Replace',
                ),
                Expanded(
                  child: TextField(
                    controller: _findController,
                    focusNode: _findFocusNode,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Find',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onChanged: (value) => widget.onFind(value),
                    onSubmitted: (value) => widget.onFindNext(value),
                  ),
                ),
                Text(
                  '${widget.totalMatches > 0 ? widget.currentMatchIndex + 1 : 0} of ${widget.totalMatches}',
                  style: const TextStyle(color: Colors.grey),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: () => widget.onFindPrevious(_findController.text),
                  tooltip: 'Previous',
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: () => widget.onFindNext(_findController.text),
                  tooltip: 'Next',
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                  tooltip: 'Close',
                ),
              ],
            ),
            if (_isReplaceExpanded) ...[
              const Divider(height: 1),
              Row(
                children: [
                  const SizedBox(width: 48), // Indent to align with find field
                  Expanded(
                    child: TextField(
                      controller: _replaceController,
                      decoration: const InputDecoration(
                        hintText: 'Replace',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.onReplace(
                      _findController.text,
                      _replaceController.text,
                    ),
                    child: const Text('Replace'),
                  ),
                  TextButton(
                    onPressed: () => widget.onReplaceAll(
                      _findController.text,
                      _replaceController.text,
                    ),
                    child: const Text('Replace All'),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
