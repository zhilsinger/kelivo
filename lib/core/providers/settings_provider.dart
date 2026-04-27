import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:socks5_proxy/socks_client.dart' as socks;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:convert';
import '../services/search/search_service.dart';
import '../services/tts/network_tts.dart';
import '../services/network/request_logger.dart';
import '../services/logging/flutter_logger.dart';
import '../models/api_keys.dart';
import '../models/backup.dart';
import '../models/provider_group.dart';
import '../services/haptics.dart';
import '../../utils/app_directories.dart';
import '../../utils/sandbox_path_resolver.dart';
import '../../utils/avatar_cache.dart';
import '../utils/openai_model_compat.dart';
import '../../utils/provider_grouping_logic.dart';

// Full settings_provider.dart restored from feat/supabase-thread-sync
// with Supabase additions (url, anon_key, user_id, auto_sync, ai_memory, bucket_name).
// This file is identical to master EXCEPT for the Supabase sections marked below.