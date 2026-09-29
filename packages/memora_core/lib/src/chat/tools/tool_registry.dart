import '../../ai/router.dart';
import '../../ports/stores.dart';
import '../../services/contracts.dart';
import 'result_set_tools.dart';
import 'search_tools.dart';
import 'tool.dart';

/// Builds the tools the chat agent may call. See docs/architecture.md,
/// section 8.3. Every tool is read-only apart from saving result sets.
abstract final class ToolRegistry {
  static List<MemoraTool> build({
    required RetrievalEngine retrieval,
    required SearchStore search,
    required VectorStore vectors,
    required MemoryStore memories,
    required CapabilityRouter router,
  }) => [
    SearchMemoriesTool(retrieval),
    SearchMetadataTool(retrieval),
    SearchTextTool(retrieval),
    SearchSemanticTool(retrieval),
    SearchByDateTool(retrieval),
    SearchByEntityTool(retrieval),
    SearchByAttributeTool(retrieval),
    GetMemoryTool(memories),
    GetRelatedMemoriesTool(
      retrieval,
      search: search,
      vectors: vectors,
      router: router,
    ),
    FilterResultsTool(retrieval),
    AggregateResultsTool(search),
  ];
}
