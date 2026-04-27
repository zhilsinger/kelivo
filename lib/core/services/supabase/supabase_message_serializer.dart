import '../../../models/chat_message.dart';
import '../../../models/conversation.dart';

/// Sidecar serializer: converts Kelivo models to Supabase REST payloads.
///
/// Extension-by-Addition: zero changes to Conversation or ChatMessage.
/// Replaces the phantom toSupabaseJson() calls from sync_orchestrator.dart
/// which would otherwise require adding Supabase knowledge to frozen models.
class SupabaseMessageSerializer {
  SupabaseMessageSerializer._();

  /// Serialize a Conversation to a Supabase thread row payload.
  static Map<String, dynamic> serializeConversation(
    Conversation c, {
    required String userId,
  }) => {
    'id': c.id,
    'user_id': userId,
    'title': c.title,
    'source': 'kelivo',
    'created_at': c.createdAt.toUtc().toIso8601String(),
    'updated_at': c.updatedAt.toUtc().toIso8601String(),
  };

  /// Serialize a ChatMessage to a Supabase message row payload.
  static Map<String, dynamic> serializeMessage(
    ChatMessage msg, {
    required String userId,
    required String threadId,
  }) => {
    'id': msg.id,
    'user_id': userId,
    'thread_id': threadId,
    'role': msg.role,
    'content': msg.content,
    'content_hash': msg.content.hashCode.toRadixString(36),
    'model_id': msg.modelId,
    'provider_id': msg.providerId,
    'total_tokens': msg.totalTokens,
    'created_at': msg.timestamp.toUtc().toIso8601String(),
  };
}
