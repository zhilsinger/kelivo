import 'package:flutter/foundation.dart';
import '../services/agent_work/checklist_service.dart';
import '../services/agent_work/checklist_verification_service.dart';
import '../models/agent_checklist.dart';
import '../models/agent_checklist_item.dart';
import '../models/agent_check_result.dart';
import '../models/agent_actor.dart';

/// Provider for checklist system state. Wraps ChecklistService,
/// ChecklistVerificationService, and exposes filtered lists to the UI.
class ChecklistProvider extends ChangeNotifier {
  final ChecklistService _checklistService;
  final ChecklistVerificationService _verificationService;
  final AgentActor _currentActor;

  ChecklistProvider({
    ChecklistService? checklistService,
    ChecklistVerificationService? verificationService,
    required AgentActor currentActor,
  })  : _checklistService = checklistService ?? ChecklistService(),
        _verificationService = verificationService ?? ChecklistVerificationService(
              checklistService: ChecklistService(),
            ),
        _currentActor = currentActor;

  List<AgentChecklist> _myChecklists = [];
  List<AgentChecklist> get myChecklists => List.unmodifiable(_myChecklists);

  /// Initialize by loading checklists.
  Future<void> init() async {
    await refresh();
  }

  /// Refresh from storage.
  Future<void> refresh() async {
    _myChecklists = await _checklistService.getMyChecklists(_currentActor);
    notifyListeners();
  }

  /// Create a new checklist.
  Future<AgentChecklist> createChecklist(
    String title, {
    String description = '',
    ChecklistVisibility visibility = ChecklistVisibility.private,
  }) async {
    final checklist = await _checklistService.createChecklist(
      title: title,
      owner: _currentActor,
      description: description,
      visibility: visibility,
    );
    await refresh();
    return checklist;
  }

  /// Get items for a specific checklist.
  List<AgentChecklistItem> getItemsForChecklist(String checklistId) {
    // Synchronous: items must be loaded elsewhere or cached.
    // For now, return empty — will be loaded on demand via detail view.
    return [];
  }

  /// Get a single item by ID.
  AgentChecklistItem? getItem(String itemId) {
    // Placeholder — items are loaded asynchronously
    return null;
  }

  /// Get verification results for an item.
  List<AgentCheckResult> getResultsForItem(String itemId) {
    return [];
  }

  /// Add an item to a checklist.
  Future<AgentChecklistItem> addItem({
    required String checklistId,
    required String title,
    String instructions = '',
    String acceptanceCriteria = '',
    required int orderIndex,
  }) async {
    final item = await _checklistService.addItem(
      checklistId: checklistId,
      title: title,
      instructions: instructions,
      acceptanceCriteria: acceptanceCriteria,
      orderIndex: orderIndex,
    );
    await refresh();
    return item;
  }

  /// Submit a check result.
  Future<SubmitCheckResultOutcome> submitCheckResult({
    required String checklistId,
    required String itemId,
    required bool passed,
    int confidencePercent = 0,
    String summary = '',
    List<String>? issuesFound,
    List<String>? evidenceRefs,
  }) async {
    final outcome = await _verificationService.submitCheckResult(
      checklistId: checklistId,
      itemId: itemId,
      actor: _currentActor,
      passed: passed,
      confidencePercent: confidencePercent,
      summary: summary,
      issuesFound: issuesFound,
      evidenceRefs: evidenceRefs,
    );
    notifyListeners();
    return outcome;
  }
}