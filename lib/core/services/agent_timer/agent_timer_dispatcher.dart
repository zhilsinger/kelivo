import 'dart:convert';
import '../../models/agent_timer_job.dart';
import '../../models/chat_message.dart';
import '../chat/chat_service.dart';

/// Handles dispatching timer jobs when they fire.
///
/// Creates a conversation and adds a system-level message containing
/// the timer prompt. The UI/home page controller is responsible for
/// detecting new system messages and triggering generation.
class AgentTimerDispatcher {
  final ChatService _chatService;

  AgentTimerDispatcher({required ChatService chatService})
      : _chatService = chatService;

  /// Dispatch a fired timer: create a conversation, add system message.
  ///
  /// Returns the conversation ID where the timer prompt was placed.
  Future<String> dispatch(AgentTimerJob job) async {
    // Create or reuse target conversation
    String conversationId;
    if (job.targetConversationId != null) {
      conversationId = job.targetConversationId!;
      final existing = _chatService.getConversation(conversationId);
      if (existing == null) {
        // Conversation was deleted — create a new one
        final convo = await _chatService.createConversation(
          assistantId: job.targetAssistantId,
          title: 'Timer: ${job.title}',
        );
        conversationId = convo.id;
      }
    } else {
      final convo = await _chatService.createConversation(
        assistantId: job.targetAssistantId,
        title: 'Timer: ${job.title}',
      );
      conversationId = convo.id;
    }

    // Build the timer prompt message
    final content = _buildTimerPrompt(job);

    // Add as a system-level message (not sent to the LLM as history)
    await _chatService.addMessage(
      conversationId: conversationId,
      role: 'system',
      content: content,
    );

    return conversationId;
  }

  /// Build the prompt message that will be sent when the timer fires.
  String _buildTimerPrompt(AgentTimerJob job) {
    final buffer = StringBuffer();
    buffer.writeln('[TIMER_TRIGGER]');
    buffer.writeln('Timer: ${job.title}');
    buffer.writeln('Fired at: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Run: ${job.runCount + 1}');
    if (job.targetChecklistId != null) {
      buffer.writeln('Checklist: ${job.targetChecklistId}');
    }
    if (job.targetChecklistItemId != null) {
      buffer.writeln('Checklist Item: ${job.targetChecklistItemId}');
    }
    buffer.writeln('---');
    buffer.writeln(job.prompt);
    buffer.writeln('[/TIMER_TRIGGER]');
    return buffer.toString();
  }
}
