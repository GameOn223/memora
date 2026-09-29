import 'package:meta/meta.dart';

import '../../ai/capabilities.dart';
import '../../model/retrieval.dart';
import '../../ports/platform.dart';
import '../../ports/stores.dart';
import '../../text/amounts.dart';
import '../../text/dates.dart';
import '../aggregation.dart';

/// What a tool may touch while it runs. Tools read memories and write only
/// result sets. See docs/architecture.md, section 8.3.
@immutable
class ToolContext {
  const ToolContext({
    required this.conversationId,
    required this.now,
    required this.conversations,
    required this.ids,
    this.messageId,
  });

  final String conversationId;
  final DateTime now;
  final ConversationStore conversations;
  final IdGenerator ids;

  /// Id of the assistant message being written, when it is known.
  final String? messageId;
}

sealed class ToolResult {
  const ToolResult();
}

/// A tool ran. [json] goes back to the model, the rest feeds the trace, the
/// sources under the answer and the presentation.
final class ToolSuccess extends ToolResult {
  const ToolSuccess(
    this.json, {
    this.traceSummary = '',
    this.memoryIds = const [],
    this.resultSetId,
    this.scores = const {},
    this.sources = const {},
    this.aggregate,
  });

  final Map<String, Object?> json;

  /// Short result description for "How this was found", such as
  /// `8 candidates`.
  final String traceSummary;

  /// Memories this call returned, in order. Citations are checked against
  /// them.
  final List<String> memoryIds;
  final String? resultSetId;

  /// Relevance from 0 to 1 per memory, when the tool ranked results.
  final Map<String, double> scores;

  /// Words for the source caption, such as `entity` or `semantic`.
  final Set<String> sources;
  final AggregateOutcome? aggregate;
}

/// The model gave arguments a tool could not use. The message goes back to
/// the model so it can correct itself.
final class ToolError extends ToolResult {
  const ToolError(this.message);

  final String message;
}

/// Thrown by argument readers and turned into a [ToolError].
class ToolArgumentException implements Exception {
  const ToolArgumentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads and checks the arguments a model sent, with messages it can act on.
class ToolArgs {
  const ToolArgs(this.raw);

  final Map<String, Object?> raw;

  /// The longest string any argument may be.
  static const maxTextLength = 200;

  String? string(String name, {int maxLength = maxTextLength}) {
    final value = raw[name];
    if (value == null) return null;
    if (value is! String) {
      throw ToolArgumentException('$name must be a string');
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > maxLength) {
      throw ToolArgumentException(
        '$name must be at most $maxLength characters',
      );
    }
    return trimmed;
  }

  String requiredString(String name, {int maxLength = maxTextLength}) {
    final value = string(name, maxLength: maxLength);
    if (value == null) throw ToolArgumentException('$name is required');
    return value;
  }

  double? number(String name) {
    final value = raw[name];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed =
          double.tryParse(value.replaceAll(',', '').trim()) ??
          parseAmountExpression(value)?.value;
      if (parsed != null) return parsed;
    }
    throw ToolArgumentException('$name must be a number');
  }

  /// A result count, capped at [RetrievalQuery.maxLimit].
  int limit({String name = 'limit', int fallback = 20}) {
    final value = raw[name];
    if (value == null) return fallback;
    int? parsed;
    if (value is int) {
      parsed = value;
    } else if (value is num && value == value.roundToDouble()) {
      parsed = value.toInt();
    } else if (value is String) {
      parsed = int.tryParse(value.trim());
    }
    if (parsed == null) {
      throw ToolArgumentException('$name must be a whole number');
    }
    return parsed.clamp(1, RetrievalQuery.maxLimit);
  }

  DateTime? date(String name) {
    final value = raw[name];
    if (value == null) return null;
    final parsed = value is String ? parseIsoDate(value) : null;
    if (parsed == null) {
      throw ToolArgumentException('$name must be a date in YYYY-MM-DD format');
    }
    return parsed;
  }

  /// A list of short strings. A single string is accepted too, since models
  /// often send one.
  List<String> strings(String name, {int maxItems = 20, int maxLength = 80}) {
    final value = raw[name];
    if (value == null) return const [];
    if (value is String) {
      final one = string(name, maxLength: maxLength);
      return one == null ? const [] : [one];
    }
    if (value is! List) {
      throw ToolArgumentException('$name must be a list of strings');
    }
    final result = <String>[];
    for (final item in value) {
      if (item is! String) {
        throw ToolArgumentException('$name must be a list of strings');
      }
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.length > maxLength) {
        throw ToolArgumentException(
          'each $name must be at most $maxLength characters',
        );
      }
      result.add(trimmed);
      if (result.length == maxItems) break;
    }
    return result;
  }

  String oneOf(String name, List<String> allowed, {String? fallback}) {
    final value = string(name);
    if (value == null) {
      if (fallback != null) return fallback;
      throw ToolArgumentException('$name is required');
    }
    final lower = value.toLowerCase();
    if (!allowed.contains(lower)) {
      throw ToolArgumentException('$name must be one of ${allowed.join(', ')}');
    }
    return lower;
  }

  /// A taken-date range built from `date_from` and `date_to`, both
  /// inclusive.
  DateRange? dateRange({String from = 'date_from', String to = 'date_to'}) {
    final start = date(from);
    final end = date(to);
    if (start != null && end != null && start.isAfter(end)) {
      throw ToolArgumentException('$from must be on or before $to');
    }
    if (start == null && end == null) return null;
    return DateRange(
      start: start,
      end: end == null ? null : DateTime(end.year, end.month, end.day + 1),
    );
  }

  String? currency() {
    final raw = string('currency', maxLength: 12);
    if (raw == null) return null;
    final code = normalizeCurrency(raw);
    if (code == null) {
      throw ToolArgumentException(
        'currency must be a three letter code such as INR',
      );
    }
    return code;
  }

  /// An `amount_min` / `amount_max` / `currency` filter, or null when none
  /// of them were given.
  AttributeFilter? amountFilter() {
    final min = number('amount_min');
    final max = number('amount_max');
    final code = currency();
    if (min != null && max != null && min > max) {
      throw ToolArgumentException(
        'amount_min must not be greater than amount_max',
      );
    }
    if (min == null && max == null && code == null) return null;
    return AttributeFilter(type: 'amount', min: min, max: max, currency: code);
  }

  EntityFilter? entityFilter() {
    final value = string('entity', maxLength: 80);
    if (value == null) return null;
    return EntityFilter(value: value, type: string('entity_type'));
  }
}

/// One read-only tool the chat model can call.
abstract class MemoraTool {
  const MemoraTool();

  String get name;

  String get description;

  /// JSON schema for the arguments.
  Map<String, Object?> get parameters;

  ToolDefinition get definition => ToolDefinition(
    name: name,
    description: description,
    parameters: parameters,
  );

  /// Runs the tool. Bad arguments and anything that goes wrong underneath
  /// come back as a [ToolError] the model can act on, never as an exception
  /// that would end the turn. See docs/architecture.md, section 8.3.
  Future<ToolResult> run(Map<String, Object?> args, ToolContext context) async {
    try {
      return await execute(ToolArgs(args), context);
    } on ToolArgumentException catch (e) {
      return ToolError(e.message);
    } on Object catch (e) {
      return ToolError('$name could not run: ${_short(e)}');
    }
  }

  static String _short(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  @protected
  Future<ToolResult> execute(ToolArgs args, ToolContext context);
}

/// Argument schemas shared by the tools.
abstract final class ToolSchemas {
  static Map<String, Object?> object(
    Map<String, Object?> properties, {
    List<String> required = const [],
  }) => {
    'type': 'object',
    'properties': properties,
    if (required.isNotEmpty) 'required': required,
  };

  static const text = {
    'type': 'string',
    'description': 'Words to match in the memory text and meaning.',
  };

  static const categories = {
    'type': 'array',
    'items': {'type': 'string'},
    'description':
        'Categories to keep, such as utility_bill, receipt, invoice, '
        'booking, ticket, product, comparison, place, map, chat, article, '
        'document or code.',
  };

  static const entity = {
    'type': 'string',
    'description': 'A company, person, place or product named in the image.',
  };

  static const entityType = {
    'type': 'string',
    'description': 'Entity type such as company, person or place.',
  };

  static const amountMin = {
    'type': 'number',
    'description': 'Smallest amount to keep.',
  };

  static const amountMax = {
    'type': 'number',
    'description': 'Largest amount to keep.',
  };

  static const currency = {
    'type': 'string',
    'description': 'ISO 4217 code such as INR or USD.',
  };

  static const dateFrom = {
    'type': 'string',
    'description': 'Earliest date the image was taken, as YYYY-MM-DD.',
  };

  static const dateTo = {
    'type': 'string',
    'description': 'Latest date the image was taken, as YYYY-MM-DD.',
  };

  static const limit = {
    'type': 'integer',
    'description': 'How many memories to return, at most 50.',
  };

  static const resultSetId = {
    'type': 'string',
    'description':
        'Which earlier result set to use. Leave it out for the most recent '
        'one.',
  };
}

/// `an amount`, `a due date`.
String articleFor(String word) =>
    RegExp('^[aeiou]').hasMatch(word) ? 'an $word' : 'a $word';

/// `amount` stays `amount`, `due_date` reads as `due date`.
String attributeLabel(String type) => type.replaceAll('_', ' ');
