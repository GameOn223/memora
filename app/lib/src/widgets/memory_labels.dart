import 'package:intl/intl.dart';
import 'package:memora_core/memora_core.dart';

/// Title for a memory, with a plain fallback before understanding exists.
String memoryTitle(Memory memory) {
  final summary = memory.summary?.trim();
  if (summary != null && summary.isNotEmpty) return summary;
  return switch (memory.source) {
    MemorySource.gallery => 'Image from your gallery',
    MemorySource.tile => 'Saved with the Memora tile',
    MemorySource.share => 'Shared to Memora',
  };
}

/// `utility_bill` becomes `utility bill`.
String humanizeKey(String key) => key.replaceAll('_', ' ').trim();

/// `due_date` becomes `Due date`.
String sentenceCase(String key) {
  final words = humanizeKey(key);
  if (words.isEmpty) return words;
  return words[0].toUpperCase() + words.substring(1);
}

/// Date group label: `Today`, `Yesterday`, or `12 September 2026`.
String dayLabel(DateTime date, DateTime now) {
  final local = date.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  if (day == DateTime(now.year, now.month, now.day)) return 'Today';
  if (day == DateTime(now.year, now.month, now.day - 1)) return 'Yesterday';
  return DateFormat('d MMMM y').format(local);
}

/// `3 images`, `1 image`.
String imageCount(int n) => n == 1 ? '1 image' : '$n images';

/// `1 memory`, `8 memories`.
String memoryCount(int n) => n == 1 ? '1 memory' : '$n memories';

/// `1st`, `2nd`, `3rd`, `11th`.
String ordinal(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

/// `HH:mm` for minutes after midnight.
String clockTime(int minutesAfterMidnight) {
  final h = (minutesAfterMidnight ~/ 60) % 24;
  final m = minutesAfterMidnight % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// `412 KB`, `3.1 MB`.
String byteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) {
    final mb = bytes / (1024 * 1024);
    return mb >= 100 ? '${mb.round()} MB' : '${mb.toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// `NVIDIA and Groq`, `NVIDIA, Groq and OpenAI`.
String joinNames(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.single;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}
