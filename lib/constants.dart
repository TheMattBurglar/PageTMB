import 'package:flutter/painting.dart';

class PageConstants {
  // US Letter size in points (72 points per inch)
  static const double pageWidth = 8.5 * 72.0;
  static const double pageHeight = 11.0 * 72.0;

  // Margins (Top, Bottom, Left, Right) in points
  static const EdgeInsets screenplayMargins = EdgeInsets.fromLTRB(
    1.5 * 72.0, // Left
    1.0 * 72.0, // Top
    1.0 * 72.0, // Right
    1.0 * 72.0, // Bottom
  );

  static const EdgeInsets manuscriptMargins = EdgeInsets.all(1.0 * 72.0);
  static const EdgeInsets essayMargins = EdgeInsets.all(1.0 * 72.0);
  static const EdgeInsets freestyleMargins = EdgeInsets.all(1.0 * 72.0);

  // Fonts
  static const String screenplayFont = 'Courier Prime';
  static const String manuscriptFont = 'Tinos';
  static const String essayFont = 'Tinos';
  static const String freestyleFont = 'Arimo'; // Default for freestyle

  static const List<String> allAvailableFonts = [
    'Arimo',
    'Carlito',
    'Courier Prime',
    'EB Garamond',
    'Playfair Display',
    'Tinos',
  ];
}

enum EditorMode { manuscript, screenplay, essay, freestyle }
