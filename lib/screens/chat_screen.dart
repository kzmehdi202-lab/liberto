import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../models/chat_message.dart';
import '../services/native_service.dart';
import '../services/openrouter_service.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final OpenRouterService _api = OpenRouterService();
  final List<ChatMessage> _messages = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _modelId = 'qwen/qwen-2.5-72b-instruct';
  String _modelName = 'Qwen 2.5 72B';
  String _systemPrompt = '';
  bool _sending = false;
  bool _hasKey = false;
  String? _error;

  // Voice + video
  AudioRecorder? _recorder;
  bool _recording = false;
  DateTime? _recordStart;
  int _recSecs = 0;
  Timer? _recTimer;
  int _playingMsgIdx = -1;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final key = await NativeService.getApiKey();
    final modelId = await NativeService.getSetting('model_id');
    final system = await NativeService.getSetting('system_prompt');
    if (!mounted) return;
    setState(() {
      _hasKey = key.isNotEmpty;
      if (modelId.isNotEmpty) _modelId = modelId;
      _systemPrompt = system;
    });
  }

  Future<void> _pickModel() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModelPickerScreen(initialId: _modelId),
      ),
    );
    if (result is List && result.length == 2) {
      final id = result[0] as String;
      final name = result[1] as String;
      setState(() {
        _modelId = id;
        _modelName = name;
      });
      await NativeService.saveSetting('model_id', id);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _loadState();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    if (!_hasKey) {
      _showError('اول کلید OpenRouter رو از تنظیمات وارد کن.');
      return;
    }

    final key = await NativeService.getApiKey();
    final history = _messages.map((m) => m.toApiMap()).toList();
    history.add({'role': 'user', 'content': text});

    final userMsg = ChatMessage(role: 'user', text: text);
    final aiMsg = ChatMessage(role: 'assistant', text: '');
    _messages.add(userMsg);
    _messages.add(aiMsg);
    _input.clear();

    setState(() {
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      await _api.streamChat(
        apiKey: key,
        model: _modelId,
        messages: history,
        systemPrompt: _systemPrompt,
        onToken: (token) {
          if (!mounted) return;
          aiMsg.text += token;
          setState(() {});
          _scrollToBottom();
        },
      );
    } on Exception catch (e) {
      if (aiMsg.text.isEmpty) {
        _messages.remove(aiMsg);
      }
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------- Voice (mic) ----------

  Future<void> _toggleMic() async {
    if (_recording) {
      await _stopRecord();
      return;
    }
    var granted = await NativeService.hasAudioPermission();
    if (!granted) {
      granted = await NativeService.requestAudioPermission();
      if (!granted) {
        for (var i = 0; i < 10 && !granted; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
          granted = await NativeService.hasAudioPermission();
        }
      }
    }
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('دسترسی میکروفون داده نشد')));
      }
      return;
    }
    _recorder ??= AudioRecorder();
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder!.start(
        const AudioSet(bitRate: 48000, encoder: AudioEncoder.aacLc),
        path: path,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطا در ضبط صدا: $e')));
      }
      return;
    }
    setState(() {
      _recording = true;
      _recordStart = DateTime.now();
      _recSecs = 0;
    });
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recordStart != null) {
        setState(
            () => _recSecs = DateTime.now().difference(_recordStart!).inSeconds);
      }
    });
  }

  Future<void> _stopRecord() async {
    _recTimer?.cancel();
    final startedAt = _recordStart;
    String? path;
    try {
      path = await _recorder?.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
    final secs =
        startedAt == null ? 0 : DateTime.now().difference(startedAt).inSeconds;
    if (path != null && File(path).existsSync()) {
      _messages.add(ChatMessage(
          role: 'user', text: '', audioPath: path, audioSeconds: secs));
      _scrollToBottom();
    }
  }

  // ---------- Video ----------

  Future<void> _pickVideo() async {
    try {
      final xfile = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxDuration: const Duration(seconds: 60),
      );
      if (xfile != null) {
        _messages.add(ChatMessage(role: 'user', text: '', videoPath: xfile.path));
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('انتخاب ویدیو ممکن نشد: $e')));
      }
    }
  }

  Future<void> _togglePlay(int idx) async {
    final ap = _messages[idx].audioPath;
    if (ap == null) return;
    if (_playingMsgIdx == idx) {
      await NativeService.stopAudio();
      if (mounted) setState(() => _playingMsgIdx = -1);
      return;
    }
    await NativeService.stopAudio();
    final ok = await NativeService.playAudio(ap);
    if (mounted) setState(() => _playingMsgIdx = ok ? idx : -1);
  }

  void _showError(String msg) {
    setState(() => _error = msg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  void _clearChat() {
    NativeService.stopAudio();
    setState(() {
      _messages.clear();
      _error = null;
      _playingMsgIdx = -1;
    });
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _recorder?.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Liberto'),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _modelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تغییر مدل',
            icon: const Icon(Icons.auto_awesome),
            onPressed: _sending ? null : _pickModel,
          ),
          IconButton(
            tooltip: 'پاک کردن چت',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _messages.isEmpty ? null : _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_hasKey)
            Material(
              color: Colors.amber.shade800,
              child: InkWell(
                onTap: _openSettings,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.key, size: 20),
                      const SizedBox(width: 8),
                      const Text('کلید OpenRouter تنظیم نشده — لمس کن تا تنظیم کنی'),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) =>
                        _buildBubble(_messages[i], i),
                  ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade100,
              padding: const EdgeInsets.all(12),
              child: Text(_error!,
                  style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.forum, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'با هوش مصنوعی گپ بزن',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'مدل فعلی: $_modelId\nهر مدل OpenRouter رو می‌تونی انتخاب کنی',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMessage m, int idx) {
    final isUser = m.isUser;
    final theme = Theme.of(context);
    final String? ap = m.audioPath;
    final String? vp = m.videoPath;

    Widget content;
    if (ap != null) {
      content = _VoiceBubble(
        path: ap,
        seconds: m.audioSeconds,
        isPlaying: _playingMsgIdx == idx,
        onToggle: () => _togglePlay(idx),
      );
    } else if (vp != null) {
      content = _VideoBubble(path: vp);
    } else {
      content = Text(
        m.text.isEmpty ? '…' : m.text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: isUser
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface,
          height: 1.4,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.smart_toy, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'ویدیو بفرست',
              icon: const Icon(Icons.videocam_rounded),
              onPressed: _sending || _recording ? null : _pickVideo,
            ),
            IconButton(
              tooltip: 'صوت ضبط کن',
              icon: Icon(
                _recording ? Icons.stop_rounded : Icons.mic_rounded,
                color: _recording ? Colors.red : null,
              ),
              onPressed: _sending ? null : _toggleMic,
            ),
            if (_recording)
              Padding(
                paddingBottom: 14,
                child: Text('⏺ $_recSecs',
                    style:
                        const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'پیامت رو بنویس…',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _sending
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.primary,
                ),
                child: Icon(
                  _sending ? Icons.stop : Icons.send,
                  color: _sending
                      ? theme.colorScheme.error
                      : theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Voice message bubble with play/stop.
class _VoiceBubble extends StatelessWidget {
  const _VoiceBubble({
    required this.path,
    required this.seconds,
    required this.isPlaying,
    required this.onToggle,
  });

  final String path;
  final int? seconds;
  final bool isPlaying;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(isPlaying
                ? Icons.pause_circle
                : Icons.play_circle,
                size: 32),
            onPressed: onToggle,
          ),
          const SizedBox(width: 2),
          Text(
            'پیام صوتی${seconds != null ? ' (${seconds} ثانیه)' : ''}',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Video message bubble: tap to play/pause.
class _VideoBubble extends StatefulWidget {
  const _VideoBubble({required this.path});

  final String path;

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  VideoPlayerController? _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.file(File(widget.path));
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _ready = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'نمایش ویدیو ممکن نشد');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(_error!, style: const TextStyle(fontSize: 13)),
      );
    }
    if (!_ready || _controller == null) {
      return const SizedBox(
          width: 200,
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final c = _controller!;
    final ratio = c.value.aspectRatio.isFinite ? c.value.aspectRatio : 16 / 9;
    return GestureDetector(
      onTap: () {
        if (c.value.isPlaying) {
          c.pause();
        } else {
          c.play();
        }
        setState(() {});
      },
      child: SizedBox(
        width: 240,
        child: AspectRatio(
          aspectRatio: ratio,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}

/// Simple model picker: fetches the full OpenRouter model list and lets the
/// user pick any of them (free choice), or type a custom model id.
class ModelPickerScreen extends StatefulWidget {
  const ModelPickerScreen({super.key, required this.initialId});

  final String initialId;

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  final OpenRouterService _api = OpenRouterService();
  List<OpenRouterModel> _models = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  final TextEditingController _custom = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final models = await _api.fetchModels();
      _custom.text = widget.initialId;
      setState(() {
        _models = models;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'خطا در دریافت لیست مدل‌ها: $e';
      });
    }
  }

  List<OpenRouterModel> get _filtered {
    if (_query.isEmpty) return _models;
    final q = _query.toLowerCase();
    return _models
        .where((m) =>
            m.name.toLowerCase().contains(q) || m.id.toLowerCase().contains(q))
        .toList();
  }

  void _pick(OpenRouterModel m) {
    Navigator.of(context).pop([m.id, m.name]);
  }

  void _pickCustom() {
    final id = _custom.text.trim();
    if (id.isEmpty) return;
    Navigator.of(context).pop([id, id]);
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('انتخاب هوش مصنوعی')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'جستجو در ${_models.length} مدل…',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _custom,
                    decoration: InputDecoration(
                      labelText: 'یا مدل دلخواه (id کامل)',
                      hintText: 'مثلاً anthropic/claude-3.5-sonnet',
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _pickCustom(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _pickCustom,
                  icon: const Icon(Icons.check),
                  label: const Text('ثبت'),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_error!),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('تلاش دوباره'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final m = filtered[i];
                          return ListTile(
                            title: Text(m.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(m.id,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(fontFamily: 'monospace')),
                            trailing: m.id == widget.initialId
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green)
                                : null,
                            onTap: () => _pick(m),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
