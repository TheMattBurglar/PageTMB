import 'dart:collection';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show TextRange;

class SpellChecker {
  final HashSet<String> _dictionary = HashSet();
  final HashSet<String> _userDictionary = HashSet();
  bool _isLoaded = false;
  File? _userDictFile;

  bool get isLoaded => _isLoaded;

  /// Loads the dictionary from the asset bundle and user storage.
  Future<void> load() async {
    try {
      // 1. Load bundled dictionary
      final String content = await rootBundle.loadString('assets/words.txt');
      final List<String> lines = content.split('\n');
      for (final line in lines) {
        final word = line.trim().toLowerCase();
        if (word.isEmpty) continue;

        // Filter out single letters except 'a' and 'i'
        if (word.length == 1 && word != 'a' && word != 'i') continue;

        // Filter out specific noise words like 'tst'
        if (word == 'tst') continue;

        _dictionary.add(word);
      }

      // 2. Load user dictionary
      try {
        final directory = await getApplicationDocumentsDirectory();
        _userDictFile = File('${directory.path}/user_dictionary.txt');
        if (await _userDictFile!.exists()) {
          final userContent = await _userDictFile!.readAsString();
          final userLines = userContent.split('\n');
          for (final line in userLines) {
            final word = line.trim();
            if (word.isNotEmpty) {
              _userDictionary.add(word.toLowerCase());
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading user dictionary: $e');
      }

      _isLoaded = true;
    } catch (e) {
      debugPrint('Error loading dictionary: $e');
      _isLoaded = true;
    }
  }

  /// Adds a word to the user dictionary and persists it.
  Future<void> addToDictionary(String word) async {
    final lowerWord = word.trim().toLowerCase();
    if (lowerWord.isEmpty) return;

    if (!_userDictionary.contains(lowerWord) &&
        !_dictionary.contains(lowerWord)) {
      _userDictionary.add(lowerWord);
      await _persistUserDictionary();
    }
  }

  Future<void> _persistUserDictionary() async {
    if (_userDictFile == null) return;
    try {
      await _userDictFile!.writeAsString(_userDictionary.join('\n'));
    } catch (e) {
      debugPrint('Error saving user dictionary: $e');
    }
  }

  /// Checks if a single word is spelled correctly.
  bool isMisspelled(String word) {
    if (!_isLoaded) return false;
    if (word.isEmpty) return false;
    if (double.tryParse(word) != null) return false;

    final lowerWord = word.toLowerCase();

    // Check exact match
    if (_dictionary.contains(lowerWord) ||
        _userDictionary.contains(lowerWord)) {
      return false;
    }

    // Check possessive forms (e.g., "Edrick's" -> "Edrick")
    if (lowerWord.endsWith("'s")) {
      final base = lowerWord.substring(0, lowerWord.length - 2);
      if (_dictionary.contains(base) || _userDictionary.contains(base)) {
        return false;
      }
    }

    // Check plural possessive forms (e.g., "James'" -> "James")
    if (lowerWord.endsWith("'")) {
      final base = lowerWord.substring(0, lowerWord.length - 1);
      if (_dictionary.contains(base) || _userDictionary.contains(base)) {
        return false;
      }
    }

    return true;
  }

  /// Returns a list of suggested corrections for a misspelled word.
  List<String> getSuggestions(String word) {
    if (!_isLoaded || word.isEmpty) return [];

    final lowerWord = word.toLowerCase();
    if (!isMisspelled(word)) return [];

    // Simple Levenshtein distance search
    final List<MapEntry<String, int>> candidates = [];
    final int wordLen = lowerWord.length;
    final allWords = _dictionary.union(_userDictionary);

    for (final dictWord in allWords) {
      if ((dictWord.length - wordLen).abs() > 2) continue;

      final dist = _levenshtein(lowerWord, dictWord);
      if (dist <= 2) {
        candidates.add(MapEntry(dictWord, dist));
      }
    }

    candidates.sort((a, b) => a.value.compareTo(b.value));
    return candidates.take(5).map((e) => e.key).toList();
  }

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.filled(t.length + 1, 0);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < t.length + 1; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = [
          v1[j] + 1,
          v0[j + 1] + 1,
          v0[j] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
      for (int j = 0; j < t.length + 1; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  /// Finds all misspelled words in the given text range.
  List<TextRange> findMisspelledWords(String text) {
    if (!_isLoaded) return [];

    final List<TextRange> misspelledRanges = [];
    final RegExp wordRegExp = RegExp(r"\b[\w']+\b");

    final matches = wordRegExp.allMatches(text);

    for (final match in matches) {
      final String word = match.group(0)!;
      if (word.contains(RegExp(r'\d'))) continue;

      if (isMisspelled(word)) {
        misspelledRanges.add(TextRange(start: match.start, end: match.end));
      }
    }

    return misspelledRanges;
  }
}
