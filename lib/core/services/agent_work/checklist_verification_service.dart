import '../../models/agent_checklist.dart';
import '../../models/agent_checklist_item.dart';
import '../../models/agent_check_result.dart';
import '../../models/agent_actor.dart';
import 'checklist_service.dart';

/// Double-verification state machine for checklist items.
///
/// Rules:
/// - The agent never calls `complete_checklist_item` directly.
/// - The agent calls `submit_check_result` instead.
/// - An item is completed only after the required number of consecutive
///   clean verification passes, each from the appropriate actor per the
///   checklist's validation policy.
class ChecklistVerificationService {
  final ChecklistService _checklistService;

  ChecklistVerificationService({required ChecklistService checklistService})
      : _checklistService = checklistService;

  /// Submit a verification result from an agent.
  ///
  /// Returns the number of consecutive passes after this result is
  /// recorded (0 if this result was a failure).
  Future<SubmitCheckResultOutcome> submitCheckResult({
    required String checklistId,
    required String itemId,
    required AgentActor actor,
    required bool passed,
    int confidencePercent = 0,
    String summary = '',
    List<String>? issuesFound,
    List<String>? evidenceRefs,
  }) async {
    final checklist = await _checklistService.getChecklist(checklistId);
    if (checklist == null) {
      return const SubmitCheckResultOutcome(
        accepted: false,
        reason: 'Checklist not found',
      );
    }

    final item = await _checklistService.getItem(itemId);
    if (item == null) {
      return const SubmitCheckResultOutcome(
        accepted: false,
        reason: 'Item not found',
      );
    }

    // Don't accept results for already-completed items
    if (item.status == ChecklistItemStatus.completed) {
      return const SubmitCheckResultOutcome(
        accepted: false,
        reason: 'Item is already completed',
      );
    }

    // Get existing results to compute sequence number
    final existingResults = await _checklistService.getResultsForItem(itemId);
    final sequenceNumber = existingResults.length + 1;

    // Store the check result
    await _checklistService.addCheckResult(
      checklistId: checklistId,
      itemId: itemId,
      actor: actor,
      passed: passed,
      confidencePercent: confidencePercent,
      summary: summary,
      issuesFound: issuesFound,
      evidenceRefs: evidenceRefs,
      itemRevisionHash: item.currentRevisionHash,
      sequenceNumber: sequenceNumber,
    );

    if (!passed) {
      // Failed: reset streak, mark item as failed
      final updated = item.copyWith(
        status: ChecklistItemStatus.failed,
        updatedAt: DateTime.now(),
      );
      await _checklistService.updateItem(updated);
      return const SubmitCheckResultOutcome(
        accepted: true,
        passed: false,
        streak: 0,
        itemCompleted: false,
      );
    }

    // Passed: count consecutive passes
    final consecutivePasses = _countConsecutivePasses(existingResults,
        item.currentRevisionHash) + 1;
    final required = item.requiredConsecutivePasses;

    if (consecutivePasses >= required) {
      // Validate actor policy
      final policyCheck = _validateActorPolicy(
        checklist: checklist,
        item: item,
        actor: actor,
        existingResults: existingResults,
      );
      if (!policyCheck.allowed) {
        // Rejection: not the right actor for this pass
        final updated = item.copyWith(
          status: ChecklistItemStatus.verificationPending,
          updatedAt: DateTime.now(),
        );
        await _checklistService.updateItem(updated);
        return SubmitCheckResultOutcome(
          accepted: true,
          passed: true,
          streak: consecutivePasses,
          itemCompleted: false,
          actorPolicyMessage: policyCheck.message,
        );
      }

      // Mark item completed
      final completed = item.copyWith(
        status: ChecklistItemStatus.completed,
        updatedAt: DateTime.now(),
        completedByActorId: actor.id,
        completedByActorName: actor.name,
        completedByActorType: actor.type.name,
        completedAt: DateTime.now(),
        completionSummary: summary,
      );
      await _checklistService.updateItem(completed);
      return SubmitCheckResultOutcome(
        accepted: true,
        passed: true,
        streak: consecutivePasses,
        itemCompleted: true,
      );
    }

    // Partial: passed but need more passes
    ChecklistItemStatus nextStatus;
    if (consecutivePasses == 1 && required >= 2) {
      nextStatus = ChecklistItemStatus.passedOnce;
    } else {
      nextStatus = ChecklistItemStatus.verificationPending;
    }
    final updated = item.copyWith(
      status: nextStatus,
      updatedAt: DateTime.now(),
    );
    await _checklistService.updateItem(updated);
    return SubmitCheckResultOutcome(
      accepted: true,
      passed: true,
      streak: consecutivePasses,
      itemCompleted: false,
    );
  }

  /// Force-complete an item (user/leader override, also used for
  /// auto-complete with 100% confidence).
  Future<void> forceCompleteItem({
    required AgentChecklistItem item,
    required AgentActor actor,
    String summary = '',
  }) async {
    final completed = item.copyWith(
      status: ChecklistItemStatus.completed,
      updatedAt: DateTime.now(),
      completedByActorId: actor.id,
      completedByActorName: actor.name,
      completedByActorType: actor.type.name,
      completedAt: DateTime.now(),
      completionSummary: summary,
    );
    await _checklistService.updateItem(completed);
  }

  /// Mark an item as blocked.
  Future<void> blockItem({
    required AgentChecklistItem item,
    String? reason,
  }) async {
    final blocked = item.copyWith(
      status: ChecklistItemStatus.blocked,
      updatedAt: DateTime.now(),
      completionSummary: reason,
    );
    await _checklistService.updateItem(blocked);
  }

  /// Try to auto-complete an item when a 100% confidence check is submitted.
  ///
  /// Returns true if the item was auto-completed.
  Future<bool> tryAutoComplete({
    required String checklistId,
    required String itemId,
    required AgentActor actor,
    int confidencePercent = 100,
    String summary = '',
  }) async {
    if (confidencePercent < 100) return false;

    final item = await _checklistService.getItem(itemId);
    if (item == null || item.status == ChecklistItemStatus.completed) {
      return false;
    }

    await forceCompleteItem(
      item: item,
      actor: actor,
      summary: summary,
    );
    return true;
  }

  /// Check if an item's dependencies are met.
  Future<DependencyCheckResult> checkDependencies(
      AgentChecklistItem item) async {
    if (item.dependencyItemIds.isEmpty) {
      return const DependencyCheckResult(allMet: true);
    }
    final blockers = <String>[];
    for (final depId in item.dependencyItemIds) {
      final dep = await _checklistService.getItem(depId);
      if (dep == null) {
        blockers.add('Dependency $depId not found');
        continue;
      }
      if (dep.status == ChecklistItemStatus.blocked) {
        blockers.add('${dep.title} is blocked');
      } else if (dep.status != ChecklistItemStatus.completed) {
        blockers.add('${dep.title} is not yet completed');
      }
    }
    return DependencyCheckResult(
      allMet: blockers.isEmpty,
      blockers: blockers,
    );
  }

  // ─── Private helpers ──────────────────────────────────────────────

  /// Count consecutive passes from the most recent results, as long as
  /// they all share the same revision hash.
  int _countConsecutivePasses(
    List<AgentCheckResult> results,
    String currentHash,
  ) {
    int count = 0;
    for (int i = results.length - 1; i >= 0; i--) {
      final r = results[i];
      if (r.passed && r.itemRevisionHash == currentHash) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// Validate that the actor meets the checklist's validation policy
  /// for this specific verification pass.
  ActorPolicyResult _validateActorPolicy({
    required AgentChecklist checklist,
    required AgentChecklistItem item,
    required AgentActor actor,
    required List<AgentCheckResult> existingResults,
  }) {
    switch (checklist.validationPolicy) {
      case DoubleCheckMode.sameAgentAllowed:
        return const ActorPolicyResult(allowed: true);

      case DoubleCheckMode.differentAgentRequired:
        if (existingResults.isNotEmpty) {
          final lastActor = existingResults.last.actorId;
          if (lastActor == actor.id) {
            return const ActorPolicyResult(
              allowed: false,
              message: 'A different agent must perform the second verification',
            );
          }
        }
        return const ActorPolicyResult(allowed: true);

      case DoubleCheckMode.leaderMustApproveSecondPass:
        // The second pass must come from a team leader (user type in this
        // implementation — can be extended for team hierarchy)
        if (existingResults.isNotEmpty && actor.type != ActorType.user) {
          return const ActorPolicyResult(
            allowed: false,
            message: 'A team leader must approve the final verification pass',
          );
        }
        return const ActorPolicyResult(allowed: true);

      case DoubleCheckMode.userMustApproveFinalPass:
        if (existingResults.isNotEmpty && actor.type != ActorType.user) {
          return const ActorPolicyResult(
            allowed: false,
            message: 'A user must approve the final verification pass',
          );
        }
        return const ActorPolicyResult(allowed: true);
    }
  }
}

/// Outcome of a check result submission.
class SubmitCheckResultOutcome {
  final bool accepted;
  final String? reason;
  final bool passed;
  final int streak;
  final bool itemCompleted;
  final String? actorPolicyMessage;

  const SubmitCheckResultOutcome({
    required this.accepted,
    this.reason,
    this.passed = false,
    this.streak = 0,
    this.itemCompleted = false,
    this.actorPolicyMessage,
  });
}

/// Result of a dependency check.
class DependencyCheckResult {
  final bool allMet;
  final List<String> blockers;

  const DependencyCheckResult({
    required this.allMet,
    this.blockers = const [],
  });
}

/// Result of an actor policy validation.
class ActorPolicyResult {
  final bool allowed;
  final String? message;

  const ActorPolicyResult({required this.allowed, this.message});
}
