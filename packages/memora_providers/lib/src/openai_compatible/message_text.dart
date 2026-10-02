import '../shared/json_read.dart';

/// Text of a message `content` given as a string or a list of parts.
String messageText(Object? content) {
  if (content is String) return content;
  final buffer = StringBuffer();
  for (final part in asList(content)) {
    final text = asString(asObject(part)?['text']);
    if (text != null) buffer.write(text);
  }
  return buffer.toString();
}
