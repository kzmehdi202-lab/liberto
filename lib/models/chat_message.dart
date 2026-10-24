/// One chat message (user or assistant).
class ChatMessage {
  ChatMessage({
    required this.role,
    required this.text,
    DateTime? time,
    this.audioPath,
    this.audioSeconds,
    this.videoPath,
  }) : time = time ?? DateTime.now();

  /// 'user' or 'assistant'
  final String role;
  String text;
  final DateTime time;

  /// Local media attached to this message (not sent to the LLM API).
  final String? audioPath;
  final int? audioSeconds;
  final String? videoPath;

  bool get isUser => role == 'user';
  bool get hasMedia => audioPath != null || videoPath != null;

  Map<String, dynamic> toApiMap() {
    final content = text.isNotEmpty
        ? text
        : (videoPath != null ? '[video message]' : '[voice message]');
    return {'role': role, 'content': content};
  }
}
