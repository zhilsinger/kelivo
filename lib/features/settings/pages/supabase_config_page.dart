import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/supabase/supabase_client_service.dart';

class SupabaseConfigPage extends StatefulWidget {
  const SupabaseConfigPage({super.key});

  @override
  State<SupabaseConfigPage> createState() => _SupabaseConfigPageState();
}

class _SupabaseConfigPageState extends State<SupabaseConfigPage> {
  late TextEditingController _urlController;
  late TextEditingController _keyController;
  bool _testing = false;
  bool? _testResult;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _urlController = TextEditingController(text: settings.supabaseUrl);
    _keyController = TextEditingController(text: settings.supabaseAnonKey);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    if (url.isEmpty || key.isEmpty) return;

    setState(() {
      _testing = true;
      _testResult = null;
    });

    final client = SupabaseClientService.instance;
    client.configure(url, key);
    final ok = await client.testConnection();
    setState(() {
      _testResult = ok;
      _testing = false;
    });
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    final key = _keyController.text.trim();
    await context.read<SettingsProvider>().setSupabaseConfig(url, key);
    if (url.isNotEmpty && key.isNotEmpty) {
      SupabaseClientService.instance.configure(url, key);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved'), duration: Duration(seconds: 2)),
      );
      Navigator.of(context).maybePop();
    }
  }

  void _clear() async {
    await context.read<SettingsProvider>().clearSupabaseConfig();
    SupabaseClientService.instance.clear();
    if (mounted) {
      _urlController.clear();
      _keyController.clear();
      setState(() => _testResult = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cleared'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: AppLocalizations.of(context)!.settingsPageBackButton,
          child: IconButton(
            icon: const Icon(Lucide.ArrowLeft),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: const Text('Supabase Sync'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: settings.supabaseConfigured
                  ? cs.primary.withValues(alpha: 0.12)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  settings.supabaseConfigured ? Lucide.CheckCircle : Lucide.CloudOff,
                  size: 20,
                  color: settings.supabaseConfigured
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Text(
                  settings.supabaseConfigured ? 'Connected' : 'Not configured',
                  style: TextStyle(
                    color: settings.supabaseConfigured
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Server URL',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: 'https://your-project.supabase.co',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          const Text('Anon Key',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _keyController,
            decoration: InputDecoration(
              hintText: 'eyJ...',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              suffixIcon: IconButton(
                icon: Icon(_obscureKey ? Lucide.Eye : Lucide.EyeOff, size: 18),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
            obscureText: _obscureKey,
            autocorrect: false,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Lucide.Wifi, size: 18),
              label: Text(_testing ? 'Testing...' : 'Test Connection'),
            ),
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _testResult! ? Lucide.CheckCircle : Lucide.XCircle,
                  size: 16,
                  color: _testResult! ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 6),
                Text(
                  _testResult! ? 'Connection successful' : 'Connection failed',
                  style: TextStyle(
                    color: _testResult! ? Colors.green : Colors.red,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Lucide.Save, size: 18),
                  label: const Text('Save'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Lucide.Trash2, size: 18),
                  label: const Text('Clear'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Lucide.Info, size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Threads backed up here will auto-sync to Supabase after import. '
                    'You can find your project URL and anon key in your Supabase project dashboard under Settings > API.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
