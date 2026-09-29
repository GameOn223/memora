import 'package:memora_core/memora_core.dart';
import 'package:memora_providers/src/shared/transcript.dart';
import 'package:test/test.dart';

const _call = ToolCall(id: 'c1', name: 'search_memories', arguments: {});
const _assistant = AssistantEntry(text: 'Earlier answer.');
const _calling = AssistantEntry(toolCalls: [_call]);
const _result = ToolResultEntry(
  callId: 'c1',
  toolName: 'search_memories',
  content: '{}',
);
const _user = UserEntry('Which bill was highest?');

void main() {
  group('fromFirstUserEntry', () {
    test('drops whatever comes before the first user turn', () {
      expect(fromFirstUserEntry(const [_assistant, _user]), [_user]);
      expect(fromFirstUserEntry(const [_calling, _result, _user]), [_user]);
    });

    test('leaves a transcript that already starts with a user turn', () {
      const entries = [_user, _calling, _result];
      expect(fromFirstUserEntry(entries), same(entries));
    });

    test('keeps everything when there is no user turn at all', () {
      const entries = [_calling, _result];
      expect(fromFirstUserEntry(entries), same(entries));
    });
  });

  group('withoutOrphanToolResults', () {
    test('drops leading tool results that lost their call', () {
      expect(withoutOrphanToolResults(const [_result, _user]), [_user]);
    });

    test('keeps a tool result that follows its call', () {
      const entries = [_calling, _result, _user];
      expect(withoutOrphanToolResults(entries), same(entries));
    });

    test('keeps everything when only tool results are left', () {
      const entries = [_result];
      expect(withoutOrphanToolResults(entries), same(entries));
    });
  });
}
