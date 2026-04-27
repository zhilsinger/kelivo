import 'package:hive_flutter/hive_flutter.dart';
import '../../models/agent_checklist.dart';
import '../../models/agent_checklist_item.dart';
import '../../models/agent_check_result.dart';
import '../../models/agent_actor.dart';

/// CRUD service for agent checklists and items.
///
/// All persistence goes through dedicated Hive boxes opened on first use.
/// Permission-gated queries filter by owner type/id and access grants.
class ChecklistService {
  static const String _checklistsBoxName = 'agent_checklists';
  static const String _itemsBoxName = 'agent_checklist_items';
  static const String _resultsBoxName = 'agent_check_results';

  Box<AgentChecklist>? _checklistsBox;
  Box<AgentChecklistItem>? _itemsBox;
  Box<AgentCheckResult>? _resultsBox;

  Future<Box<AgentChecklist>> get _checklists async {
    if (_checklistsBox == null || !_checklistsBox!.isOpen) {
      _checklistsBox = await Hive.openBox<AgentChecklist>(_checklistsBoxName);
    }
    return _checklistsBox!;
  }

  Future<Box<AgentChecklistItem>> get _items async {
    if (_itemsBox == null || !_itemsBox!.isOpen) {
      _itemsBox = await Hive.openBox<AgentChecklistItem>(_itemsBoxName);
    }
    return _itemsBox!;
  }

  Future<Box<AgentCheckResult>> get _results async {
    if (_resultsBox == null || !_resultsBox!.isOpen) {
      _resultsBox = await Hive.openBox<AgentCheckResult>(_resultsBoxName);
    }
    return _resultsBox!;
  }

  /// Create a new checklist.
  Future<AgentChecklist> createChecklist({
    required String title,
    required AgentActor owner,
    String description = '',
    ChecklistVisibility visibility = ChecklistVisibility.private,
    DoubleCheckMode validationPolicy = DoubleCheckMode.sameAgentAllowed,
    int requiredConsecutivePasses = 2,
    List<ChecklistAccessGrant>? accessGrants,
  }) async {
    final checklist = AgentChecklist(
      title: title,
      description: description,
      ownerType: _ownerTypeFromActor(owner),
      ownerId: owner.id,
      visibility: visibility,
      validationPolicy: validationPolicy,
      requiredConsecutivePasses: requiredConsecutivePasses,
      accessGrants: accessGrants,
    );
    final box = await _checklists;
    await box.put(checklist.id, checklist);
    return checklist;
  }

  /// Get a checklist by ID.
  Future<AgentChecklist?> getChecklist(String id) async {
    final box = await _checklists;
    return box.get(id);
  }

  /// Update a checklist.
  Future<void> updateChecklist(AgentChecklist updated) async {
    final box = await _checklists;
    await box.put(updated.id, updated);
  }

  /// Delete a checklist and all its items and results.
  Future<void> deleteChecklist(String id) async {
    final box = await _checklists;
    final itemsBox = await _items;
    final resultsBox = await _results;

    // Delete all items for this checklist
    final itemKeys = itemsBox.keys.where((k) {
      final item = itemsBox.get(k);
      return item != null && item.checklistId == id;
    }).toList();
    for (final k in itemKeys) {
      // Also delete child check results
      final resultKeys = resultsBox.keys.where((rk) {
        final r = resultsBox.get(rk);
        if (r == null) return false;
        final item = itemsBox.get(k);
        return item != null && r.itemId == item.id;
      }).toList();
      for (final rk in resultKeys) {
        await resultsBox.delete(rk);
      }
      await itemsBox.delete(k);
    }
    await box.delete(id);
  }

  /// Archive a checklist (soft-delete).
  Future<void> archiveChecklist(String id) async {
    final checklist = await getChecklist(id);
    if (checklist == null) return;
    final updated = checklist.copyWith(archived: true);
    await updateChecklist(updated);
  }

  // ─── Items ────────────────────────────────────────────────────────

  /// Add an item to a checklist.
  Future<AgentChecklistItem> addItem({
    required String checklistId,
    required String title,
    String instructions = '',
    String acceptanceCriteria = '',
    required int orderIndex,
    int requiredConsecutivePasses = 2,
    List<String>? dependencyItemIds,
    String? assignedAssistantId,
    String? assignedTeamId,
  }) async {
    final item = AgentChecklistItem(
      checklistId: checklistId,
      title: title,
      instructions: instructions,
      acceptanceCriteria: acceptanceCriteria,
      orderIndex: orderIndex,
      requiredConsecutivePasses: requiredConsecutivePasses,
      dependencyItemIds: dependencyItemIds,
      assignedAssistantId: assignedAssistantId,
      assignedTeamId: assignedTeamId,
    );
    final box = await _items;
    await box.put(item.id, item);
    return item;
  }

  /// Get all items for a checklist, ordered by orderIndex.
  Future<List<AgentChecklistItem>> getItems(String checklistId) async {
    final box = await _items;
    final items = box.values
        .where((i) => i.checklistId == checklistId)
        .toList();
    items.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return items;
  }

  /// Get a single item.
  Future<AgentChecklistItem?> getItem(String itemId) async {
    final box = await _items;
    return box.get(itemId);
  }

  /// Update an item.
  Future<void> updateItem(AgentChecklistItem updated) async {
    final box = await _items;
    await box.put(updated.id, updated);
  }

  /// Delete an item and its results.
  Future<void> deleteItem(String itemId) async {
    final box = await _items;
    final resultsBox = await _results;
    final resultKeys = resultsBox.keys.where((k) {
      final r = resultsBox.get(k);
      return r != null && r.itemId == itemId;
    }).toList();
    for (final k in resultKeys) {
      await resultsBox.delete(k);
    }
    await box.delete(itemId);
  }

  // ─── Check Results ────────────────────────────────────────────────

  /// Store a check result.
  Future<AgentCheckResult> addCheckResult({
    required String checklistId,
    required String itemId,
    required AgentActor actor,
    required bool passed,
    int confidencePercent = 0,
    String summary = '',
    List<String>? issuesFound,
    List<String>? evidenceRefs,
    required String itemRevisionHash,
    required int sequenceNumber,
  }) async {
    final result = AgentCheckResult(
      checklistId: checklistId,
      itemId: itemId,
      actorId: actor.id,
      actorName: actor.name,
      actorType: actor.type.name,
      passed: passed,
      confidencePercent: confidencePercent,
      summary: summary,
      issuesFound: issuesFound,
      evidenceRefs: evidenceRefs,
      itemRevisionHash: itemRevisionHash,
      sequenceNumber: sequenceNumber,
    );
    final box = await _results;
    await box.put(result.id, result);
    return result;
  }

  /// Get all check results for an item, ordered by sequenceNumber.
  Future<List<AgentCheckResult>> getResultsForItem(String itemId) async {
    final box = await _results;
    final results = box.values
        .where((r) => r.itemId == itemId)
        .toList();
    results.sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
    return results;
  }

  // ─── Queries ──────────────────────────────────────────────────────

  /// Get all non-archived checklists owned by an actor.
  Future<List<AgentChecklist>> getMyChecklists(AgentActor actor) async {
    final box = await _checklists;
    return box.values
        .where((c) =>
            !c.archived &&
            c.ownerId == actor.id &&
            c.ownerType == _ownerTypeFromActor(actor))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Get checklists shared with an actor (via access grants).
  Future<List<AgentChecklist>> getSharedChecklists(AgentActor actor) async {
    final box = await _checklists;
    return box.values
        .where((c) {
          if (c.archived) return false;
          if (c.visibility == ChecklistVisibility.team) return true;
          return c.accessGrants.any((g) =>
              g.principalId == actor.id);
        })
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Get all completed (all items done) checklists.
  Future<List<AgentChecklist>> getCompletedChecklists(AgentActor actor) async {
    final box = await _checklists;
    final itemsBox = await _items;
    final candidates = box.values
        .where((c) =>
            !c.archived &&
            (c.ownerId == actor.id &&
                c.ownerType == _ownerTypeFromActor(actor)))
        .toList();
    final completed = <AgentChecklist>[];
    for (final c in candidates) {
      final items = itemsBox.values
          .where((i) => i.checklistId == c.id)
          .toList();
      if (items.isNotEmpty &&
          items.every((i) => i.status == ChecklistItemStatus.completed)) {
        completed.add(c);
      }
    }
    completed.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return completed;
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  ChecklistOwnerType _ownerTypeFromActor(AgentActor actor) {
    switch (actor.type) {
      case ActorType.assistant:
        return ChecklistOwnerType.assistant;
      case ActorType.team:
        return ChecklistOwnerType.team;
      case ActorType.user:
        return ChecklistOwnerType.user;
      case ActorType.system:
        return ChecklistOwnerType.workspace;
    }
  }
}
