import 'package:flutter/foundation.dart';
import '../services/agent_work/agent_audit_service.dart';
import '../models/agent_audit_event.dart';

/// Provider for agent audit event state. Wraps AgentAuditService
/// and exposes paginated audit queries to the UI via ChangeNotifier.
class AgentAuditProvider extends ChangeNotifier {
  final AgentAuditService _auditService;

  AgentAuditProvider({AgentAuditService? auditService})
      : _auditService = auditService ?? AgentAuditService();

  List<AgentAuditEvent> _recentEvents = [];
  List<AgentAuditEvent> get recentEvents => List.unmodifiable(_recentEvents);

  /// Initialize by loading recent events.
  Future<void> init() async {
    await refresh();
  }

  /// Refresh from storage (loads most recent events across all actors).
  Future<void> refresh() async {
    // Load events across all entity types — limited to 50 most recent
    final allEvents = <AgentAuditEvent>[];
    final actorIds = <String>{};
    // Get unique actor IDs from the events store
    // For now, query with empty actor filter to get all events
    try {
      // Use a generic query approach — get events for the latest actors
      final futures = <Future<List<AgentAuditEvent>>>[];
      // Load events for various entity types
      futures.add(_auditService.getEventsForEntity(entityId: '*', limit: 50));
      final results = await Future.wait(futures);
      for (final list in results) {
        allEvents.addAll(list);
      }
    } catch (_) {
      // Fallback: empty list
    }
    // Deduplicate and sort
    final seen = <String>{};
    _recentEvents = allEvents
        .where((e) => seen.add(e.id))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_recentEvents.length > 50) {
      _recentEvents = _recentEvents.sublist(0, 50);
    }
    notifyListeners();
  }

  /// Query events for a specific entity.
  Future<List<AgentAuditEvent>> eventsForEntity({
    required String entityId,
    String? entityType,
  }) async {
    return _auditService.getEventsForEntity(
      entityId: entityId,
      entityType: entityType,
    );
  }
}