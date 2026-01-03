import 'dart:collection';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show TextRange;

class SpellChecker {
  final HashSet<String> _dictionary = HashSet();
  final HashSet<String> _userDictionary = HashSet();
  final Map<int, List<String>> _dictionaryByLength = {};

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
        _dictionaryByLength.putIfAbsent(word.length, () => []).add(word);
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
              final lower = word.toLowerCase();
              _userDictionary.add(lower);
              _dictionaryByLength
                  .putIfAbsent(lower.length, () => [])
                  .add(lower);
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
      _dictionaryByLength
          .putIfAbsent(lowerWord.length, () => [])
          .add(lowerWord);
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
    // Optimization: If it's correctly spelled (or we have it), return empty?
    // User logic said: if (!isMisspelled(word)) return [];
    if (!isMisspelled(word)) return [];

    // Simple Levenshtein distance search optimized by length buckets
    final List<MapEntry<String, int>> candidates = [];
    final int wordLen = lowerWord.length;

    // Check only words involving length +/- 2
    for (int len = wordLen - 2; len <= wordLen + 2; len++) {
      if (len < 1) continue;
      final bucket = _dictionaryByLength[len];
      if (bucket != null) {
        for (final dictWord in bucket) {
          // Pass maxDist 2 to early exit
          final dist = _levenshtein(lowerWord, dictWord, 2);
          if (dist <= 2) {
            candidates.add(MapEntry(dictWord, dist));
          }
        }
      }
    }

    candidates.sort((a, b) => a.value.compareTo(b.value));
    return candidates.take(5).map((e) => e.key).toList();
  }

  int _levenshtein(String s, String t, int maxDist) {
    if (s == t) return 0;
    if ((s.length - t.length).abs() > maxDist) return maxDist + 1;

    // Use two rows instead of full matrix to save memory
    // current represents the 'previous' row (initially row 0)
    // next represents the 'current' row being calculated
    List<int> current = List<int>.generate(t.length + 1, (i) => i);
    List<int> next = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      next[0] = i + 1;
      int minRowDist = next[0]; // Track minimum distance in this row

      for (int j = 0; j < t.length; j++) {
        final cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;

        // Inline min calculation for performance
        final insert = next[j] + 1;
        final delete = current[j + 1] + 1;
        final sub = current[j] + cost;

        int val = insert;
        if (delete < val) val = delete;
        if (sub < val) val = sub;

        next[j + 1] = val;

        if (val < minRowDist) minRowDist = val;
      }

      // Early exit if the entire row exceeds maxDist
      if (minRowDist > maxDist) return maxDist + 1;

      // Swap arrays
      final temp = current;
      current = next;
      next = temp;
    }

    return current[t.length];
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
