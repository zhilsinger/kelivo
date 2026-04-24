import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../core/providers/memory_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/chat/chat_orchestrator_service.dart';
import '../../../core/services/mcp/mcp_tool_service.dart';
import '../../../core/services/search/search_tool_service.dart';
import 'tool_approval_service.dart';

class ToolHandlerService {
  ToolHandlerService({
    required this.contextProvider,
    required this.chatOrchestratorService,
  });

  final BuildContext contextProvider;
  final ChatOrchestratorService chatOrchestratorService;

  static Map<String, dynamic> sanitizeToolParametersForProvider(
    Map<String, dynamic> schema,
    ProviderKind kind,
  ) {
    Map<String, dynamic> clone = _deepCloneMap(schema);
    clone = _sanitizeNode(clone, kind) as Map<String, dynamic>;
    return clone;
  }

  static dynamic _sanitizeNode(dynamic node, ProviderKind kind) {
    if (node is List) {
      return node.map((e) => _sanitizeNode(e, kind)).toList();
    }
    if (node is! Map) return node;

    final m = Map<String, dynamic>.from(node);
    m.remove(r'$schema');

    if (m.containsKey('const')) {
      final v = m['const'];
      if (v is String || v is num || v is bool) {
        m['enum'] = [v];
      }
      m.remove('const');
    }

    for (final key in [
      'anyOf',
      'oneOf',
      'allOf',
      'any_of',
      'one_of',
      'all_of',
    ]) {
      if (m[key] is List && (m[key] as List).isNotEmpty) {
        final first = (m[key] as List).first;
        final flattened = _sanitizeNode(first, kind);
        m.remove(key);
        if (flattened is Map<String, dynamic>) {
          m
            ..remove('type')
            ..remove('properties')
            ..remove('items');
          m.addAll(flattened);
        }
      }
    }

    final t = m['type'];
    if (t is List && t.isNotEmpty) m['type'] = t.first.toString();

    final items = m['items'];
    if (items is List && items.isNotEmpty) m['items'] = items.first;
    if (m['items'] is Map) m['items'] = _sanitizeNode(m['items'], kind);

    if (m['properties'] is Map) {
      final props = Map<String, dynamic>.from(m['properties']);
      final norm = <String, dynamic>{};
      props.forEach((k, v) {
        norm[k] = _sanitizeNode(v, kind);
      });
      m['properties'] = norm;
    }

    Set<String> allowed;
    switch (kind) {
      case ProviderKind.google:
        allowed = {
          'type',
          'description',
          'properties',
          'required',
          'items',
          'enum',
        };
        break;
      case ProviderKind.openai:
      case ProviderKind.claude:
        allowed = {
          'type',
          'description',
          'properties',
          'required',
          'items',
          'enum',
        };
        break;
    }
    m.removeWhere((k, v) => !allowed.contains(k));
    return m;
  }

  static Map<String, dynamic> _deepCloneMap(Map<String, dynamic> input) {
    return jsonDecode(jsonEncode(input)) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> buildToolDefinitions(
    SettingsProvider settings,
    Assistant? assistant,
    String providerKey,
    String modelId,
    bool hasBuiltInSearch, {
    required bool Function(String providerKey, String modelId) isToolModel,
  }) {
    final List<Map<String, dynamic>> toolDefs = <Map<String, dynamic>>[];
    final supportsTools = isToolModel(providerKey, modelId);

    if (settings.searchEnabled && !hasBuiltInSearch && supportsTools) {
      toolDefs.add(SearchToolService.getToolDefinition());
    }

    if (assistant?.enableMemory == true && supportsTools) {
      toolDefs.addAll(_buildMemoryToolDefinitions());
    }

    final mcpTools = _buildMcpToolDefinitions(
      settings: settings,
      assistant: assistant,
      providerKey: providerKey,
      supportsTools: supportsTools,
    );
    toolDefs.addAll(mcpTools);

    // Orchestration: spawn_subtask tool
    if (supportsTools && settings.orchestrationEnabled) {
      toolDefs.addAll(_buildOrchestrationToolDefinitions());
    }

    return toolDefs;
  }

  List<Map<String, dynamic>> _buildMemoryToolDefinitions() {
    return [
      {
        'type': 'function',
        'function': {
          'name': 'create_memory',
          'description': 'create a memory record',
          'parameters': {
            'type': 'object',
            'properties': {
              'content': {
                'type': 'string',
                'description': 'The content of the memory record',
              },
            },
            'required': ['content'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'edit_memory',
          'description': 'update a memory record',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'integer',
                'description': 'The id of the memory record',
              },
              'content': {
                'type': 'string',
                'description': 'The content of the memory record',
              },
            },
            'required': ['id', 'content'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'delete_memory',
          'description': 'delete a memory record',
          'parameters': {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'integer',
                'description': 'The id of the memory record',
              },
            },
            'required': ['id'],
          },
        },
      },
    ];
  }

  List<Map<String, dynamic>> _buildOrchestrationToolDefinitions() {
    return [
      {
        'type': 'function',
        'function': {
          'name': 'spawn_subtask',
          'description':
              'Spawn a new child conversation with a specific task instruction. '
              'The spawned conversation will process independently and report back '
              'its results. Use this to delegate work that can be done in parallel '
              'or independently. The sub-task runs immediately and the result is '
              'posted back into this conversation.',
          'parameters': {
            'type': 'object',
            'properties': {
              'task_instruction': {
                'type': 'string',
                'description':
                    'Detailed instructions for what the sub-task should accomplish. '
                    'Be specific about the expected output format.',
              },
              'title': {
                'type': 'string',
                'description':
                    'Optional title for the sub-conversation (defaults to a truncated version of the instruction).',
              },
            },
            'required': ['task_instruction'],
          },
        },
      },
    ];
  }

  List<Map<String, dynamic>> _buildMcpToolDefinitions({
    required SettingsProvider settings,
    required Assistant? assistant,
    required String providerKey,
    required bool supportsTools,
  }) {
    if (!supportsTools) return [];

    final mcp = contextProvider.read<McpProvider>();
    final toolSvc = contextProvider.read<McpToolService>();
    final tools = toolSvc.listAvailableToolsForAssistant(
      mcp,
      contextProvider.read<AssistantProvider>(),
      assistant?.id,
    );

    if (tools.isEmpty) return [];

    final providerCfg = settings.getProviderConfig(providerKey);
    final providerKind = ProviderConfig.classify(
      providerCfg.id,
      explicitType: providerCfg.providerType,
    );

    return tools.map((t) {
      Map<String, dynamic> baseSchema;
      if (t.schema != null && t.schema!.isNotEmpty) {
        baseSchema = Map<String, dynamic>.from(t.schema!);
      } else {
        final props = <String, dynamic>{
          for (final p in t.params) p.name: {'type': (p.type ?? 'string')},
        };
        final required = [
          for (final p in t.params.where((e) => e.required)) p.name,
        ];
        baseSchema = {
          'type': 'object',
          'properties': props,
          if (required.isNotEmpty) 'required': required,
        };
      }
      final sanitized = sanitizeToolParametersForProvider(
        baseSchema,
        providerKind,
      );
      return {
        'type': 'function',
        'function': {
          'name': t.name,
          if ((t.description ?? '').isNotEmpty) 'description': t.description,
          'parameters': sanitized,
        },
      };
    }).toList();
  }

  Future<String> Function(String, Map<String, dynamic>)? buildToolCallHandler(
    SettingsProvider settings,
    Assistant? assistant, {
    ToolApprovalService? approvalService,
  }) {
    final mcp = contextProvider.read<McpProvider>();
    final toolSvc = contextProvider.read<McpToolService>();
    final assistantProvider = contextProvider.read<AssistantProvider>();

    return (name, args) async {
      try {
        // Search tool
        if (name == SearchToolService.toolName && settings.searchEnabled) {
          final q = (args['query'] ?? '').toString();
          return await SearchToolService.executeSearch(q, settings);
        }

        // Memory tools
        final memoryResult = await _handleMemoryToolCall(name, args, assistant);
        if (memoryResult != null) {
          return memoryResult;
        }

        // Orchestration: spawn_subtask
        if (name == 'spawn_subtask' && settings.orchestrationEnabled) {
          return await _handleSpawnSubtask(args, assistant, settings);
        }

        // Approval gate for MCP tools
        if (approvalService != null && mcp.toolNeedsApproval(name)) {
          final toolCallId =
              '${name}_${DateTime.now().microsecondsSinceEpoch}';
          final result = await approvalService.requestApproval(
            toolCallId: toolCallId,
            toolName: name,
            arguments: args,
          );
          if (!result.approved) {
            return jsonEncode({
              'type': 'tool_error',
              'error': 'approval_denied',
              'message':
                  result.denyReason ?? 'User denied the tool call',
              'tool': name,
            });
          }
        }

        // MCP tools
        final text = await toolSvc.callToolTextForAssistant(
          mcp,
          assistantProvider,
          assistantId: assistant?.id,
          toolName: name,
          arguments: args,
        );
        return text;
      } catch (e) {
        return jsonEncode({
          'type': 'tool_error',
          'error': 'execution_error',
          'message': e.toString(),
          'tool': name,
          'instruction':
              'The tool execution failed unexpectedly. You may try again with different parameters or inform the user about the issue.',
        });
      }
    };
  }

  Future<String?> _handleMemoryToolCall(
    String name,
    Map<String, dynamic> args,
    Assistant? assistant,
  ) async {
    if (assistant?.enableMemory != true) return null;

    try {
      final mp = contextProvider.read<MemoryProvider>();

      if (name == 'create_memory') {
        final content = (args['content'] ?? '').toString();
        if (content.isEmpty) return '';
        final m = await mp.add(assistantId: assistant!.id, content: content);
        return m.content;
      } else if (name == 'edit_memory') {
        final id = (args['id'] as num?)?.toInt() ?? -1;
        final content = (args['content'] ?? '').toString();
        if (id <= 0 || content.isEmpty) return '';
        final m = await mp.update(id: id, content: content);
        return m?.content ?? '';
      } else if (name == 'delete_memory') {
        final id = (args['id'] as num?)?.toInt() ?? -1;
        if (id <= 0) return '';
        final ok = await mp.delete(id: id);
        return ok ? 'deleted' : '';
      }
    } catch (_) {}

    return null;
  }

  Future<String> _handleSpawnSubtask(
    Map<String, dynamic> args,
    Assistant? assistant,
    SettingsProvider settings,
  ) async {
    final taskInstruction = (args['task_instruction'] ?? '').toString();
    final title = (args['title'] ?? '').toString();

    if (taskInstruction.isEmpty) {
      return jsonEncode({
        'type': 'tool_error',
        'error': 'Missing required parameter: task_instruction',
      });
    }

    final currentConvoId =
        contextProvider.read<ChatService>().currentConversationId;

    if (currentConvoId == null) {
      return jsonEncode({
        'type': 'tool_error',
        'error': 'No active conversation to spawn from',
      });
    }

    final result = await chatOrchestratorService.spawnSubtask(
      parentConversationId: currentConvoId,
      taskInstruction: taskInstruction,
      title: title.isNotEmpty ? title : null,
      assistantId: assistant?.id,
      assistant: assistant,
      settings: settings,
    );

    if (!result.success || result.conversation == null) {
      return jsonEncode({
        'type': 'tool_error',
        'error': result.errorMessage ?? 'Failed to spawn subtask',
      });
    }

    return jsonEncode({
      'type': 'subtask_created',
      'subtask_id': result.conversation!.id,
      'subtask_title': result.conversation!.title,
      'status': 'completed',
      'message':
          'Sub-task executed successfully. The result has been reported back to this conversation.',
    });
  }
}
