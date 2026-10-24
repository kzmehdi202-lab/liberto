import 'package:flutter/material.dart';

import '../services/github_service.dart';
import '../services/liberto_source.dart';
import '../services/native_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _keyCtrl = TextEditingController();
  final TextEditingController _systemCtrl = TextEditingController();
  final TextEditingController _ghUserCtrl = TextEditingController();
  final TextEditingController _ghTokenCtrl = TextEditingController();
  bool _obscure = true;
  bool _ghObscure = true;
  bool _loaded = false;
  String _fingerprint = '';
  String? _ghStatus;
  bool _ghOk = false;
  bool _ghTesting = false;
  bool _selfPushing = false;
  String? _selfPushMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await NativeService.getApiKey();
    final system = await NativeService.getSetting('system_prompt');
    _keyCtrl.text = key;
    _systemCtrl.text = system;
    _ghUserCtrl.text = await NativeService.getSetting('github_user');
    _ghTokenCtrl.text = await NativeService.getSetting('github_token');
    if (key.isNotEmpty) {
      _fingerprint = await NativeService.nativeSha256(key);
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final key = _keyCtrl.text.trim();
    if (key.isNotEmpty) {
      await NativeService.saveApiKey(key);
      _fingerprint = await NativeService.nativeSha256(key);
    } else {
      await NativeService.deleteApiKey();
      _fingerprint = '';
    }
    await NativeService.saveSetting('system_prompt', _systemCtrl.text.trim());
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ذخیره شد ✓')),
      );
    }
  }

  void _deleteKey() async {
    await NativeService.deleteApiKey();
    _keyCtrl.clear();
    _fingerprint = '';
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('کلید حذف شد')),
    );
  }

  Future<void> _saveGithub() async {
    await NativeService.saveSetting('github_user', _ghUserCtrl.text.trim());
    await NativeService.saveSetting('github_token', _ghTokenCtrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تنظیمات GitHub ذخیره شد ✓')),
      );
    }
  }

  Future<void> _testGithub() async {
    setState(() {
      _ghTesting = true;
      _ghStatus = null;
      _ghOk = false;
    });
    try {
      final login = await GitHubService().verifyToken(_ghTokenCtrl.text.trim());
      if (mounted) {
        setState(() {
          _ghOk = true;
          _ghStatus = '✓ متصل شد به حساب: $login';
          _ghTesting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ghOk = false;
          _ghStatus = e.toString();
          _ghTesting = false;
        });
      }
    }
  }

  /// Pushes Liberto's own source to the user's GitHub (repo: liberto).
  /// GitHub Actions then builds the Liberto APK in the cloud.
  Future<void> _selfPush() async {
    if (_ghUserCtrl.text.trim().isEmpty || _ghTokenCtrl.text.trim().isEmpty) {
      setState(() => _selfPushMsg = 'اول یوزر و توکن GitHub را وارد و ذخیره کن');
      return;
    }
    setState(() {
      _selfPushing = true;
      _selfPushMsg = 'اتصال به GitHub...';
    });
    try {
      await _saveGithub();
      final gh = GitHubService();
      final token = _ghTokenCtrl.text.trim();
      final login = await gh.verifyToken(token);
      if (mounted) setState(() => _selfPushMsg = 'ساخت ریپوی liberto...');
      await gh.createRepo(token, 'liberto',
          description: 'Liberto — AI Android app builder (source)');
      if (mounted) {
        setState(() => _selfPushMsg = 'ارسال ${libertoSource.length} فایل...');
      }
      await gh.pushAllFiles(token, login, 'liberto', libertoSource);
      if (mounted) {
        setState(() => _selfPushMsg =
            '✅ تموم شد! ریپو: https://github.com/$login/liberto — بیلد ابری شروع شده؛ فایل نصب Liberto به‌عنوان artifact در همان ریپو آماده می‌شود.');
      }
    } catch (e) {
      if (mounted) setState(() => _selfPushMsg = '❌ ${e.toString()}');
    } finally {
      if (mounted) setState(() => _selfPushing = false);
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _systemCtrl.dispose();
    _ghUserCtrl.dispose();
    _ghTokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.key, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('کلید API OpenRouter',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: _obscure,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: 'sk-or-v1-…',
                      helperText: 'از openrouter.ai/keys می‌گیری',
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_fingerprint.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.fingerprint,
                            size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'SHA-256 (محاسبه در C++): ${_fingerprint.substring(0, 16)}…',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: _keyCtrl.text.isEmpty ? null : _deleteKey,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('حذف کلید'),
                      style:
                          TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('GitHub', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                      'برنامه‌ساز با این توکن کد اپ‌های تو را روی GitHub می‌گذارد و آنجا کامپایل می‌کند.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ghUserCtrl,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'یوزرنیم GitHub',
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ghTokenCtrl,
                    obscureText: _ghObscure,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'توکن GitHub (ghp_...)',
                      suffixIcon: IconButton(
                        icon: Icon(_ghObscure
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _ghObscure = !_ghObscure),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saveGithub,
                          child: const Text('ذخیره'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _ghTesting ? null : _testGithub,
                          child: _ghTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('آزمایش اتصال'),
                        ),
                      ),
                    ],
                  ),
                  if (_ghStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        _ghStatus!,
                        style: TextStyle(
                            fontSize: 13,
                            color: _ghOk ? Colors.green : Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('کد خودِ Liberto',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                      'کد کامل همین برنامه (Flutter + Kotlin + C++) را در ریپوی liberto روی حساب خودت می‌گذارد؛ GitHub خودش بیلد می‌کند و فایل نصب Liberto را در آن ریپو آماده می‌کند — لینک دائمی.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _selfPushing ? null : _selfPush,
                    icon: _selfPushing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.upload_rounded),
                    label: const Text('بفرست به GitHub من'),
                  ),
                  if (_selfPushMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(_selfPushMsg!,
                          style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.psychology,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('دستور شخصی (اختیاری)',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _systemCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText:
                          'مثلا‌ً: همیشه به فارسی جواب بده و کوتاه جواب بده…',
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('ذخیره تنظیمات'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }
}
