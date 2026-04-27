import 'package:hive_flutter/hive_flutter.dart';
import '../../models/agent_audit_event.dart';
import '../../models/agent_actor.dart';

/// Append-only audit trail for agent work operations.
///
/// Every mutation to checklists, items, timers, and teams is recorded
/// with before/after state for courtroom-grade traceability.
class AgentAuditService {
  static const String _boxName = 'agent_audit_events';

  Box<AgentAuditEvent>? _box;

  Future<Box<AgentAuditEvent>> get _events async {
    if (_box == null || !_box!.isOpen) {
      _box = await Hive.openBox<AgentAuditEvent>(_boxName);
    }
    return _box!;
  }

  /// Record an audit event.
  Future<AgentAuditEvent> writeAuditEvent({
    required String entityType,
    required String entityId,
    required String action,
    required AgentActor actor,
    Map<String, dynamic>? beforeState,
    Map<String, dynamic>? afterState,
    String? reason,
    String? conversationId,
    String? messageId,
  }) async {
    final event = AgentAuditEvent(
      entityType: entityType,
      entityId: entityId,
      action: action,
      actorId: actor.id,
      actorName: actor.name,
      actorType: actor.type.name,
      beforeJson: _safeJson(beforeState),
      afterJson: _safeJson(afterState),
      reason: reason,
      conversationId: conversationId,
      messageId: messageId,
    );
    final box = await _events;
    await box.put(event.id, event);
    return event;
  }

  /// Query audit events for an entity, newest first.
  Future<List<AgentAuditEvent>> getEventsForEntity({
    required String entityId,
    String? entityType,
    int limit = 50,
  }) async {
    final box = await _events;
    final results = box.values.where((e) {
      if (e.entityId != entityId) return false;
      if (entityType != null && e.entityType != entityType) return false;
      return true;
    }).toList();
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  /// Query audit events by actor, newest first.
  Future<List<AgentAuditEvent>> getEventsByActor({
    required String actorId,
    int limit = 50,
  }) async {
    final box = await _events;
    final results = box.values
        .where((e) => e.actorId == actorId)
        .toList();
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  /// Get the last audit event for a specific entity.
  Future<AgentAuditEvent?> getLastEventForEntity(String entityId) async {
    final box = await _events;
    final events = box.values
        .where((e) => e.entityId == entityId)
        .toList();
    if (events.isEmpty) return null;
    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return events.first;
  }

  String _safeJson(Map<String, dynamic>? state) {
    if (state == null) return '{}';
    // Simple JSON encoding — avoids circular references by only taking
    // shallow copies of primitive values and strings.
    final safe = <String, dynamic>{};
    state.forEach((key, value) {
      if (value is String || value is num || value is bool || value == null) {
        safe[key] = value;
      } else {
        safe[key] = value.toString();
      }
    });
    // Use manual string building to avoid import of dart:convert at class level
    final sb = StringBuffer();
    sb.write('{');
    var first = true;
    safe.forEach((k, v) {
      if (!first) sb.write(',');
      first = false;
      sb.write('"$k":');
      if (v == null) {
        sb.write('null');
      } else if (v is String) {
        sb.write('"${v.toString().replaceAll('"', '\\"')}"');
      } else if (v is bool) {
        sb.write(v.toString());
      } else {
        sb.write(v.toString());
      }
    });
    sb.write('}');
    return sb.toString();
  }
}
