import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../core/models/assistant.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/instruction_injection.dart';
import '../../../core/models/world_book.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/memory_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/chat/document_text_extractor.dart';
import '../../../core/services/chat/prompt_transformer.dart';
import '../../../core/services/instruction_injection_store.dart';
import '../../../core/services/world_book_store.dart';
import '../../../core/services/search/search_tool_service.dart';
import '../../../core/providers/instruction_injection_provider.dart';
import '../../../core/providers/world_book_provider.dart';
import '../../../core/services/api/builtin_tools.dart';
import '../../../core/models/assistant_regex.dart';
import '../../../core/utils/multimodal_input_utils.dart';
import '../../../utils/assistant_regex.dart';
import '../../../utils/markdown_media_sanitizer.dart';

class MessageBuilderService {
  static const String internalMediaPathsKey = multimodalInternalMediaPathsKey;

  MessageBuilderService({
    required this.chatService,
    required this.contextProvider,
    this.ocrHandler,
    this.geminiThoughtSignatureHandler,
  });

  final ChatService chatService;
  final BuildContext contextProvider;
  final Future<String?> Function(List<String> imagePaths)? ocrHandler;
  String Function(String ocrText)? ocrTextWrapper;
  final String Function(ChatMessage message, String content)?
      geminiThoughtSignatureHandler;

  final Map<String, _DocTextCacheEntry> _docTextCache =
      <String, _DocTextCacheEntry>{};
  // ... rest of file unchanged ...
}