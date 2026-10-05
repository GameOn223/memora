import 'dart:convert';

import 'package:memora_core/memora_core.dart';

import '../shared/json_extract.dart';
import '../shared/json_read.dart';
import '../shared/transcript.dart';

/// Prompts for a Gemma model running on this phone, and the reader for
/// whatever it writes back.
///
/// Gemma's instruction tuning has no system role, so the system text sits at
/// the top of the first user turn, which is what the model card asks for.
/// Turns are wrapped in `<start_of_turn>` and `<end_of_turn>`, and the
/// prompt ends with an open model turn so generation starts straight away.
///
/// The shape follows the cloud adapters: the same system prompt, the same
/// transcript in order, the same tool definitions. Only the encoding is
/// different, since there is no JSON API here, just one string in and tokens
/// out.
abstract final class LocalLlmPrompt {
  static const startUser = '<start_of_turn>user';
  static const startModel = '<start_of_turn>model';
  static const endTurn = '<end_of_turn>';

  /// How much of one tool result goes into the prompt. A search result set
  /// is already compact cards, but a long one would crowd out the question
  /// on a 4,096 token context.
  static const toolResultLimit = 1200;

  /// The whole chat prompt: system text, tool definitions, the transcript,
  /// then an open model turn.
  static String chat(ChatRequest request) {
    // Gemma expects a user turn first, and the system text rides on it.
    final entries = fromFirstUserEntry(
      withoutOrphanToolResults(request.entries),
    );
    final preamble = [
      if (request.system.isNotEmpty) request.system,
      if (request.tools.isNotEmpty) tools(request.tools),
    ].join('\n\n');

    final out = StringBuffer();
    var first = true;
    void turn(String role, String text) {
      out.writeln(role);
      if (first && preamble.isNotEmpty) {
        out
          ..writeln(preamble)
          ..writeln();
        first = false;
      }
      out
        ..write(text)
        ..writeln(endTurn);
    }

    for (final entry in entries) {
      switch (entry) {
        case UserEntry(:final text):
          turn(startUser, text);
        case AssistantEntry(:final text, :final toolCalls):
          turn(
            startModel,
            toolCalls.isEmpty
                ? text
                : [for (final call in toolCalls) encodeCall(call)].join('\n'),
          );
        case ToolResultEntry(:final toolName, :final content):
          turn(startUser, 'Result from $toolName:\n${_clip(content)}');
      }
    }
    // An empty transcript would otherwise lose the system text.
    if (first && preamble.isNotEmpty) turn(startUser, '');
    out.writeln(startModel);
    return out.toString();
  }

  /// The vision prompt: instructions and the line that goes with the image.
  /// The image itself is passed to the runtime beside this text.
  static String vision({required String instructions, required String text}) =>
      '$startUser\n$instructions\n\n$text$endTurn\n$startModel\n';

  /// Tool definitions in one compact block.
  ///
  /// Full JSON schemas are what a cloud model gets, and they are too long
  /// here: eleven schemas would fill the context a small model has for the
  /// question. Each tool becomes a signature line instead, with `?` marking
  /// an optional argument.
  static String tools(List<ToolDefinition> definitions) {
    final lines = [
      'You can look things up with these tools:',
      for (final tool in definitions)
        '- ${signature(tool)}: ${_oneLine(tool.description)}',
      '',
      'To use one, reply with this and nothing else:',
      '{"tool": "<name>", "arguments": {}}',
      '',
      'Search before you answer anything factual. Once a result holds the '
          'answer, reply in plain words instead of calling another tool.',
    ];
    return lines.join('\n');
  }

  /// `search_by_entity(value: string, type?: string)`.
  static String signature(ToolDefinition tool) {
    final properties = asObject(tool.parameters['properties']) ?? const {};
    final required = asList(tool.parameters['required']).whereType<String>();
    final parts = [
      for (final entry in properties.entries)
        '${entry.key}${required.contains(entry.key) ? '' : '?'}: '
            '${_type(entry.value)}',
    ];
    return '${tool.name}(${parts.join(', ')})';
  }

  /// A tool call written the way the prompt asks for it, so the model sees
  /// its own earlier calls in the same form.
  static String encodeCall(ToolCall call) =>
      jsonEncode({'tool': call.name, 'arguments': call.arguments});

  static String _type(Object? schema) {
    final type = asObject(schema)?['type'];
    if (type is List) return type.whereType<String>().join(' or ');
    return type is String ? type : 'string';
  }

  static String _oneLine(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _clip(String text) => text.length <= toolResultLimit
      ? text
      : '${text.substring(0, toolResultLimit)}…';
}

/// The tool call in [text], or null when there is no usable one.
///
/// A small model writes a call as prose around JSON, in a fenced block, or
/// with the keys in whatever order it remembers, so the reader is lenient
/// about all of that. It is strict about one thing: the name has to be a
/// tool that was offered. A call to something invented cannot be run, and
/// treating it as "no call" is what sends the turn back to search.
ToolCall? parseLocalToolCall(
  String text,
  Set<String> allowed, {
  required String id,
}) {
  final json = extractJsonObject(text);
  if (json == null) return null;
  final name = asString(json['tool'] ?? json['name'] ?? json['tool_name']);
  if (name == null || !allowed.contains(name.trim())) return null;
  final raw =
      json['arguments'] ?? json['args'] ?? json['parameters'] ?? json['input'];
  return ToolCall(id: id, name: name.trim(), arguments: decodeArguments(raw));
}
