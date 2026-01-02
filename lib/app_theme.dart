import 'package:flutter/material.dart';
import 'constants.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blueGrey,
        brightness: Brightness.light,
      ),
      fontFamily: PageConstants.freestyleFont,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 12.0),
        bodyMedium: TextStyle(fontSize: 12.0),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blueGrey,
        brightness: Brightness.dark,
      ),
      fontFamily: PageConstants.freestyleFont,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 12.0),
        bodyMedium: TextStyle(fontSize: 12.0),
      ),
    );
  }
}
