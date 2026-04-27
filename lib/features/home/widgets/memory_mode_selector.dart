import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/supabase_memory_context.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/supabase/supabase_memory_settings.dart';
import '../../../l10n/app_localizations.dart';

/// A standalone widget that shows a horizontal chip bar for selecting
/// the Supabase AI memory mode.
///
/// Composed alongside the chat body per Extension-by-Addition rule —
/// this widget is self-contained and manages its own state via providers.
class MemoryModeSelectorBar extends StatelessWidget {
  const MemoryModeSelectorBar({super.key});

  @override
  Widget build(BuildContext context) {
    final memSettings = context.watch<SupabaseMemorySettings>();
    final supabaseConfigured =
        context.watch<SettingsProvider>().supabaseConfigured;
    final l10n = AppLocalizations.of(context)!;

    // Hidden entirely when memory is off or Supabase not configured.
    if (!memSettings.aiMemoryEnabled || !supabaseConfigured) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: SupabaseMemoryMode.values.map((mode) {
          final selected = memSettings.memoryMode == mode;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(_labelForMode(mode, l10n)),
              selected: selected,
              onSelected: (_) => memSettings.setMemoryMode(mode),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _labelForMode(SupabaseMemoryMode mode, AppLocalizations l10n) {
    switch (mode) {
      case SupabaseMemoryMode.off:
        return l10n.supabaseMemoryModeOff;
      case SupabaseMemoryMode.currentThread:
        return l10n.supabaseMemoryModeCurrentThread;
      case SupabaseMemoryMode.allArchives:
        return l10n.supabaseMemoryModeAllArchives;
      case SupabaseMemoryMode.pinnedOnly:
        return l10n.supabaseMemoryModePinned;
      case SupabaseMemoryMode.project:
        return l10n.supabaseMemoryModeProject;
    }
  }
}
