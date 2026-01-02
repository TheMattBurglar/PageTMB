import 'package:flutter/material.dart';
import '../models/document.dart';
import '../logic/editor_controller.dart';

class EditorToolbar extends StatelessWidget {
  final EditorController controller;
  final double zoomLevel;
  final ValueChanged<double> onZoomChanged;

  const EditorToolbar({
    super.key,
    required this.controller,
    required this.zoomLevel,
    required this.onZoomChanged,
  });

  @override
  Widget build(BuildContext context) {
    final activeAttributes = controller.activeAttributes;
    final currentParagraph =
        controller.document.paragraphs[controller.cursorParagraphIndex];

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 8),
            _ToolbarButton(
              icon: Icons.undo,
              isSelected: false,
              onPressed: controller.canUndo ? () => controller.undo() : null,
              tooltip: 'Undo (Ctrl+Z)',
            ),
            _ToolbarButton(
              icon: Icons.redo,
              isSelected: false,
              onPressed: controller.canRedo ? () => controller.redo() : null,
              tooltip: 'Redo (Ctrl+Y)',
            ),
            const VerticalDivider(indent: 12, endIndent: 12),
            _ToolbarButton(
              icon: Icons.format_bold,
              isSelected: activeAttributes.bold,
              onPressed: () => controller.toggleBold(),
              tooltip: 'Bold (Ctrl+B)',
            ),
            _ToolbarButton(
              icon: Icons.format_italic,
              isSelected: activeAttributes.italic,
              onPressed: () => controller.toggleItalic(),
              tooltip: 'Italic (Ctrl+I)',
            ),
            _ToolbarButton(
              icon: Icons.format_underlined,
              isSelected: activeAttributes.underline,
              onPressed: () => controller.toggleUnderline(),
              tooltip: 'Underline (Ctrl+U)',
            ),
            const VerticalDivider(indent: 12, endIndent: 12),
            _ToolbarButton(
              icon: Icons.format_align_left,
              isSelected: currentParagraph.alignment == ParagraphAlignment.left,
              onPressed: () => controller.setAlignment(ParagraphAlignment.left),
              tooltip: 'Align Left',
            ),
            _ToolbarButton(
              icon: Icons.format_align_center,
              isSelected:
                  currentParagraph.alignment == ParagraphAlignment.center,
              onPressed: () =>
                  controller.setAlignment(ParagraphAlignment.center),
              tooltip: 'Align Center',
            ),
            _ToolbarButton(
              icon: Icons.format_align_right,
              isSelected:
                  currentParagraph.alignment == ParagraphAlignment.right,
              onPressed: () =>
                  controller.setAlignment(ParagraphAlignment.right),
              tooltip: 'Align Right',
            ),
            _ToolbarButton(
              icon: Icons.format_align_justify,
              isSelected:
                  currentParagraph.alignment == ParagraphAlignment.justify,
              onPressed: () =>
                  controller.setAlignment(ParagraphAlignment.justify),
              tooltip: 'Justify',
            ),
            const VerticalDivider(indent: 12, endIndent: 12),
            // Zoom Controls
            _ToolbarButton(
              icon: Icons.zoom_out,
              isSelected: false,
              onPressed: zoomLevel > 1.0
                  ? () => onZoomChanged((zoomLevel - 0.1).clamp(1.0, 3.0))
                  : null,
              tooltip: 'Zoom Out',
            ),
            SizedBox(
              width: 50,
              child: Text(
                '${(zoomLevel * 100).toInt()}%',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _ToolbarButton(
              icon: Icons.zoom_in,
              isSelected: false,
              onPressed: zoomLevel < 3.0
                  ? () => onZoomChanged(zoomLevel + 0.1)
                  : null,
              tooltip: 'Zoom In',
            ),
            _ToolbarButton(
              icon: Icons.settings_backup_restore,
              isSelected: false,
              onPressed: zoomLevel != 1.0 ? () => onZoomChanged(1.0) : null,
              tooltip: 'Reset Zoom',
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onPressed;
  final String tooltip;

  const _ToolbarButton({
    required this.icon,
    required this.isSelected,
    this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      color: isSelected ? Theme.of(context).colorScheme.primary : null,
      onPressed: onPressed,
      tooltip: tooltip,
      style: isSelected
          ? IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            )
          : null,
    );
  }
}
