import 'dart:io';

void main() async {
  final file = File('assets/words.txt');
  if (!await file.exists()) {
    print('assets/words.txt does not exist');
    return;
  }

  final content = await file.readAsString();
  final lines = content.split(RegExp(r'\r?\n'));
  final Set<String> words = lines.map((l) => l.trim().toLowerCase()).toSet();

  print("Dictionary size: ${words.length}");
  print("Contains 'f': ${words.contains('f')}");
  print("Contains 'tst': ${words.contains('tst')}");

  // Print some words starting with f to see what's there
  print("First 10 words starting with f:");
  print(words.where((w) => w.startsWith('f')).take(10).toList());
}
