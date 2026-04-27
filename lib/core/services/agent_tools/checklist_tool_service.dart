import '../../models/agent_checklist.dart';
import '../../models/agent_checklist_item.dart';
import '../../models/agent_actor.dart';
import '../agent_work/checklist_service.dart';
import '../agent_work/checklist_verification_service.dart';

/// Tool definitions for agent checklist operations exposed to LLMs.
///
/// The agent never calls `complete_checklist_item` directly.
/// Instead it calls `submit_check_result`, and the system's
/// double-verification state machine handles completion.
class ChecklistToolService {
  final ChecklistService _checklistService;
  final ChecklistVerificationService _verificationService;

  ChecklistToolService({
    required ChecklistService checklistService,
    required ChecklistVerificationService verificationService,
  })  : _checklistService = checklistService,
        _verificationService = verificationService;

  /// Check if a tool call name belongs to the checklist domain.
  bool isChecklistTool(String name) {
    switch (name) {
      case 'create_checklist':
      case 'add_checklist_item':
      case 'update_checklist_item':
      case 'list_checklists':
      case 'list_checklist_items':
      case 'submit_check_result':
      case 'block_checklist_item':
      case 'get_checklist_item_status':
        return true;
      default:
        return false;
    }
  }

  /// Build the tool definitions for the checklist domain.
  List<Map<String, dynamic>> buildToolDefinitions() {
    return [
      _createChecklistDef(),
      _addItemDef(),
      _updateItemDef(),
      _listChecklistsDef(),
      _listItemsDef(),
      _submitCheckResultDef(),
      _blockItemDef(),
      _getItemStatusDef(),
    ];
  }

  /// Route a tool call to the appropriate handler.
  Future<String> call({
    required AgentActor actor,
    required String name,
    required Map<String, dynamic> args,
  }) async {
    switch (name) {
      case 'create_checklist':
        return _handleCreateChecklist(actor, args);
      case 'add_checklist_item':
        return _handleAddItem(actor, args);
      case 'update_checklist_item':
        return _handleUpdateItem(actor, args);
      case 'list_checklists':
        return _handleListChecklists(actor);
      case 'list_checklist_items':
        return _handleListItems(args);
      case 'submit_check_result':
        return _handleSubmitCheckResult(actor, args);
      case 'block_checklist_item':
        return _handleBlockItem(actor, args);
      case 'get_checklist_item_status':
        return _handleGetItemStatus(args);
      default:
        return 'Unknown checklist tool: $name';
    }
  }

  // ─── Tool definitions ────────────────────────────────────────────

  Map<String, dynamic> _createChecklistDef() => {
        'type': 'function',
        'function': {
          'name': 'create_checklist',
          'description':
              'Create a new checklist to track multi-step tasks. '
              'The checklist can be private, shared, or team-visible.',
          'parameters': {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'description': 'Title of the checklist',
              },
              'description': {
                'type': 'string',
                'description': 'Optional description of what this checklist covers',
              },
              'visibility': {
                'type': 'string',
                'enum': ['private', 'shared', 'team'],
                'description':
                    'Who can see this checklist. private=only me, shared=specific agents, team=entire team',
              },
              'validation_policy': {
                'type': 'string',
                'enum': [
                  'same_agent_allowed',
                  'different_agent_required',
                  'leader_must_approve',
                  'user_must_approve'
                ],
                'description':
                    'How items are verified. same_agent_allowed means the same '
                    'agent can verify their own work.',
              },
              'required_passes': {
                'type': 'integer',
                'description':
                    'Number of consecutive clean verification passes required '
                    'to complete an item (default 2)',
              },
            },
            'required': ['title'],
          },
        },
      };

  Map<String, dynamic> _addItemDef() => {
        'type': 'function',
        'function': {
          'name': 'add_checklist_item',
          'description':
              'Add a new item to a checklist. Items are ordered by index.',
          'parameters': {
            'type': 'object',
            'properties': {
              'checklist_id': {
                'type': 'string',
                'description': 'ID of the parent checklist',
              },
              'title': {
                'type': 'string',
                'description': 'Title of the item',
              },
              'instructions': {
                'type': 'string',
                'description': 'Detailed instructions for completing this item',
              },
              'acceptance_criteria': {
                'type': 'string',
                'description': 'Criteria that must be met for this item to pass',
              },
              'order_index': {
                'type': 'integer',
                'description': 'Position in the checklist (0-based)',
              },
              'dependency_item_ids': {
                'type': 'array',
                'items': {'type': 'string'},
                'description':
                    'IDs of items that must be completed before this one can start',
              },
              'assigned_agent_id': {
                'type': 'string',
                'description': 'ID of the assistant assigned to this item',
              },
            },
            'required': ['checklist_id', 'title', 'order_index'],
          },
        },
      };

  Map<String, dynamic> _updateItemDef() => {
        'type': 'function',
        'function': {
          'name': 'update_checklist_item',
          'description':
              'Update an existing checklist item (title, instructions, '
              'acceptance criteria, or assignment). Does NOT change completion status.',
          'parameters': {
            'type': 'object',
            'properties': {
              'item_id': {
                'type': 'string',
                'description': 'ID of the item to update',
              },
              'title': {
                'type': 'string',
                'description': 'New title (optional)',
              },
              'instructions': {
                'type': 'string',
                'description': 'Updated instructions (optional)',
              },
              'acceptance_criteria': {
                'type': 'string',
                'description': 'Updated acceptance criteria (optional)',
              },
              'assigned_agent_id': {
                'type': 'string',
                'description':
                    'Reassign to a different assistant (optional, pass null to unassign)',
              },
            },
            'required': ['item_id'],
          },
        },
      };

  Map<String, dynamic> _listChecklistsDef() => {
        'type': 'function',
        'function': {
          'name': 'list_checklists',
          'description':
              'List all checklists available to you (owned + shared)',
          'parameters': {
            'type': 'object',
            'properties': {},
          },
        },
      };

  Map<String, dynamic> _listItemsDef() => {
        'type': 'function',
        'function': {
          'name': 'list_checklist_items',
          'description':
              'List all items in a checklist with their current status',
          'parameters': {
            'type': 'object',
            'properties': {
              'checklist_id': {
                'type': 'string',
                'description': 'ID of the checklist to list items for',
              },
            },
            'required': ['checklist_id'],
          },
        },
      };

  Map<String, dynamic> _submitCheckResultDef() => {
        'type': 'function',
        'function': {
          'name': 'submit_check_result',
          'description':
              'Submit a verification result for a checklist item. '
              'You CANNOT mark items as completed directly. Instead, submit '
              'verification results, and the system will determine when the '
              'required number of consecutive clean passes has been met. '
              'A confidence of 100 will auto-complete the item (use sparingly).',
          'parameters': {
            'type': 'object',
            'properties': {
              'checklist_id': {
                'type': 'string',
                'description': 'ID of the parent checklist',
              },
              'item_id': {
                'type': 'string',
                'description': 'ID of the item being verified',
              },
              'passed': {
                'type': 'boolean',
                'description': 'Whether this verification pass succeeded',
              },
              'confidence': {
                'type': 'integer',
                'description':
                    'Confidence percentage (0-100). 100 = absolutely certain, '
                    'will auto-complete the item.',
              },
              'summary': {
                'type': 'string',
                'description': 'Summary of what was verified',
              },
              'issues_found': {
                'type': 'array',
                'items': {'type': 'string'},
                'description':
                    'List of issues found during verification (if passed=false)',
              },
              'evidence_refs': {
                'type': 'array',
                'items': {'type': 'string'},
                'description':
                    'References to evidence supporting this verification '
                    '(e.g., message IDs, file paths, URLs)',
              },
            },
            'required': ['checklist_id', 'item_id', 'passed'],
          },
        },
      };

  Map<String, dynamic> _blockItemDef() => {
        'type': 'function',
        'function': {
          'name': 'block_checklist_item',
          'description':
              'Mark a checklist item as blocked. Use when a dependency or '
              'external factor prevents progress. Always explain the blocker.',
          'parameters': {
            'type': 'object',
            'properties': {
              'item_id': {
                'type': 'string',
                'description': 'ID of the item to block',
              },
              'reason': {
                'type': 'string',
                'description': 'Detailed explanation of why this item is blocked',
              },
            },
            'required': ['item_id', 'reason'],
          },
        },
      };

  Map<String, dynamic> _getItemStatusDef() => {
        'type': 'function',
        'function': {
          'name': 'get_checklist_item_status',
          'description':
              'Get the current status and verification history of a checklist item',
          'parameters': {
            'type': 'object',
            'properties': {
              'item_id': {
                'type': 'string',
                'description': 'ID of the item to check',
              },
            },
            'required': ['item_id'],
          },
        },
      };

  // ─── Tool handlers ───────────────────────────────────────────────

  Future<String> _handleCreateChecklist(
      AgentActor actor, Map<String, dynamic> args) async {
    final title = args['title'] as String;
    final description = (args['description'] as String?) ?? '';
    final visibilityStr = (args['visibility'] as String?) ?? 'private';
    final visibility = ChecklistVisibility.values.firstWhere(
      (v) => v.name == visibilityStr,
      orElse: () => ChecklistVisibility.private,
    );
    final policyStr =
        (args['validation_policy'] as String?) ?? 'same_agent_allowed';
    final policy = DoubleCheckMode.values.firstWhere(
      (v) => v.name == policyStr,
      orElse: () => DoubleCheckMode.sameAgentAllowed,
    );
    final passes = (args['required_passes'] as num?)?.toInt() ?? 2;

    final checklist = await _checklistService.createChecklist(
      title: title,
      owner: actor,
      description: description,
      visibility: visibility,
      validationPolicy: policy,
      requiredConsecutivePasses: passes,
    );

    return 'Created checklist "${checklist.title}" (id: ${checklist.id}) '
        'with $passes-pass verification, visibility: ${visibility.name}';
  }

  Future<String> _handleAddItem(
      AgentActor actor, Map<String, dynamic> args) async {
    final checklistId = args['checklist_id'] as String;
    final title = args['title'] as String;
    final instructions = (args['instructions'] as String?) ?? '';
    final criteria = (args['acceptance_criteria'] as String?) ?? '';
    final orderIndex = (args['order_index'] as num).toInt();
    final deps = (args['dependency_item_ids'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final assigned = args['assigned_agent_id'] as String?;

    final item = await _checklistService.addItem(
      checklistId: checklistId,
      title: title,
      instructions: instructions,
      acceptanceCriteria: criteria,
      orderIndex: orderIndex,
      dependencyItemIds: deps,
      assignedAssistantId: assigned,
    );

    return 'Added item "${item.title}" (id: ${item.id}) '
        'at position $orderIndex in checklist $checklistId';
  }

  Future<String> _handleUpdateItem(
      AgentActor actor, Map<String, dynamic> args) async {
    final itemId = args['item_id'] as String;
    final item = await _checklistService.getItem(itemId);
    if (item == null) return 'Item $itemId not found';

    final updated = item.copyWith(
      title: args['title'] as String?,
      instructions: args['instructions'] as String?,
      acceptanceCriteria: args['acceptance_criteria'] as String?,
      assignedAssistantId: args['assigned_agent_id'] as String?,
      clearAssignment: args['assigned_agent_id'] == null,
      updatedAt: DateTime.now(),
    );
    updated.bumpRevision();
    await _checklistService.updateItem(updated);

    return 'Updated item "${updated.title}" (id: ${updated.id})';
  }

  Future<String> _handleListChecklists(AgentActor actor) async {
    final mine = await _checklistService.getMyChecklists(actor);
    final shared = await _checklistService.getSharedChecklists(actor);

    if (mine.isEmpty && shared.isEmpty) {
      return 'No checklists found. Create one with create_checklist.';
    }

    final sb = StringBuffer();
    if (mine.isNotEmpty) {
      sb.writeln('Your checklists:');
      for (final c in mine) {
        final items = await _checklistService.getItems(c.id);
        final completed =
            items.where((i) => i.status == ChecklistItemStatus.completed).length;
        sb.writeln(
            '- ${c.title} (id: ${c.id}, ${completed}/${items.length} complete, '
            'visibility: ${c.visibility.name})');
      }
    }
    if (shared.isNotEmpty) {
      if (mine.isNotEmpty) sb.writeln();
      sb.writeln('Shared with you:');
      for (final c in shared) {
        final items = await _checklistService.getItems(c.id);
        final completed =
            items.where((i) => i.status == ChecklistItemStatus.completed).length;
        sb.writeln(
            '- ${c.title} (id: ${c.id}, ${completed}/${items.length} complete)');
      }
    }
    return sb.toString().trim();
  }

  Future<String> _handleListItems(Map<String, dynamic> args) async {
    final checklistId = args['checklist_id'] as String;
    final checklist = await _checklistService.getChecklist(checklistId);
    if (checklist == null) return 'Checklist $checklistId not found';

    final items = await _checklistService.getItems(checklistId);
    if (items.isEmpty) return 'No items in checklist "${checklist.title}"';

    final sb = StringBuffer();
    sb.writeln('Checklist: ${checklist.title} (id: $checklistId)');
    sb.writeln('Policy: ${checklist.validationPolicy.name}, '
        '${checklist.requiredConsecutivePasses} passes required');
    sb.writeln();
    for (final item in items) {
      final statusIcon = _statusIcon(item.status);
      sb.writeln('$statusIcon ${item.title} (id: ${item.id}, status: ${item.status.name})');
      if (item.dependencyItemIds.isNotEmpty) {
        sb.writeln('  Depends on: ${item.dependencyItemIds.join(', ')}');
      }
    }
    return sb.toString().trim();
  }

  Future<String> _handleSubmitCheckResult(
      AgentActor actor, Map<String, dynamic> args) async {
    final checklistId = args['checklist_id'] as String;
    final itemId = args['item_id'] as String;
    final passed = args['passed'] as bool;
    final confidence = (args['confidence'] as num?)?.toInt() ?? 0;
    final summary = (args['summary'] as String?) ?? '';
    final issues = (args['issues_found'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final evidence = (args['evidence_refs'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    // Check dependencies first
    final item = await _checklistService.getItem(itemId);
    if (item != null) {
      final depCheck = await _verificationService.checkDependencies(item);
      if (!depCheck.allMet) {
        return 'Cannot verify item "${item.title}": dependencies not met. '
            '${depCheck.blockers.join('; ')}';
      }
    }

    // Try auto-complete if 100% confidence
    if (passed && confidence >= 100) {
      final autoCompleted = await _verificationService.tryAutoComplete(
        checklistId: checklistId,
        itemId: itemId,
        actor: actor,
        confidencePercent: confidence,
        summary: summary,
      );
      if (autoCompleted) {
        return 'Item $itemId auto-completed with 100% confidence.';
      }
    }

    final outcome = await _verificationService.submitCheckResult(
      checklistId: checklistId,
      itemId: itemId,
      actor: actor,
      passed: passed,
      confidencePercent: confidence,
      summary: summary,
      issuesFound: issues,
      evidenceRefs: evidence,
    );

    if (!outcome.accepted) {
      return 'Verification rejected: ${outcome.reason}';
    }

    if (outcome.itemCompleted) {
      return 'Item $itemId COMPLETED! ${outcome.streak}/${outcome.streak} consecutive passes.';
    }

    if (outcome.passed) {
      final remaining = (await _checklistService.getItem(itemId))
              ?.requiredConsecutivePasses ??
          2;
      return 'Item $itemId passed verification (${outcome.streak}/$remaining passes). '
          '${remaining - outcome.streak} more pass(es) needed.';
    }

    return 'Item $itemId FAILED verification. Issues: ${issues.join(', ')}';
  }

  Future<String> _handleBlockItem(
      AgentActor actor, Map<String, dynamic> args) async {
    final itemId = args['item_id'] as String;
    final reason = args['reason'] as String;

    final item = await _checklistService.getItem(itemId);
    if (item == null) return 'Item $itemId not found';

    await _verificationService.blockItem(item: item, reason: reason);
    return 'Item "${item.title}" (id: $itemId) marked as blocked. Reason: $reason';
  }

  Future<String> _handleGetItemStatus(Map<String, dynamic> args) async {
    final itemId = args['item_id'] as String;
    final item = await _checklistService.getItem(itemId);
    if (item == null) return 'Item $itemId not found';

    final results = await _checklistService.getResultsForItem(itemId);
    final depCheck = await _verificationService.checkDependencies(item);

    final sb = StringBuffer();
    sb.writeln('Item: ${item.title} (id: ${item.id})');
    sb.writeln('Status: ${item.status.name}');
    sb.writeln('Checklist: ${item.checklistId}');
    sb.writeln('Order: ${item.orderIndex}');
    sb.writeln('Required passes: ${item.requiredConsecutivePasses}');
    if (item.instructions.isNotEmpty) {
      sb.writeln('Instructions: ${item.instructions}');
    }
    if (item.acceptanceCriteria.isNotEmpty) {
      sb.writeln('Acceptance criteria: ${item.acceptanceCriteria}');
    }
    if (item.assignedAssistantId != null) {
      sb.writeln('Assigned to: ${item.assignedAssistantId}');
    }
    if (!depCheck.allMet) {
      sb.writeln('Dependencies: NOT MET — ${depCheck.blockers.join('; ')}');
    }
    if (results.isNotEmpty) {
      sb.writeln('Verification history:');
      for (final r in results) {
        final icon = r.passed ? '✓' : '✗';
        sb.writeln('  $icon #${r.sequenceNumber} by ${r.actorName} '
            '(${r.confidencePercent}% confidence): ${r.summary}');
      }
    }
    if (item.completedAt != null) {
      sb.writeln('Completed at: ${item.completedAt!.toIso8601String()}');
      sb.writeln('Completed by: ${item.completedByActorName ?? 'unknown'}');
    }
    return sb.toString().trim();
  }

  String _statusIcon(ChecklistItemStatus status) {
    switch (status) {
      case ChecklistItemStatus.open:
        return '○';
      case ChecklistItemStatus.inProgress:
        return '◐';
      case ChecklistItemStatus.blocked:
        return '⊘';
      case ChecklistItemStatus.verificationPending:
        return '◑';
      case ChecklistItemStatus.passedOnce:
        return '◕';
      case ChecklistItemStatus.completed:
        return '●';
      case ChecklistItemStatus.failed:
        return '✗';
      case ChecklistItemStatus.skipped:
        return '→';
      case ChecklistItemStatus.archived:
        return '∅';
    }
  }
}
