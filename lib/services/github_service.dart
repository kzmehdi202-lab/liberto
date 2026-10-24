import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

class GitHubError implements Exception {
  GitHubError(this.message);
  final String message;
  @override
  String toString() => message;
}

class ActionRun {
  ActionRun({required this.id, required this.status, this.conclusion});
  final int id;
  final String status; // queued | in_progress | completed
  final String? conclusion; // success | failure | ...
}

/// Thin client for the GitHub REST API (repos, contents, Actions, artifacts).
class GitHubService {
  static const String _api = 'https://api.github.com';

  Map<String, String> _h(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Liberto',
      };

  /// Verifies the token; returns the account login name.
  Future<String> verifyToken(String token) async {
    final res = await http.get(Uri.parse('$_api/user'), headers: _h(token))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw GitHubError(
          'توکن GitHub معتبر نیست (HTTP ${res.statusCode}) — توکن را دوباره بساز');
    }
    return (jsonDecode(res.body)['login'] as String?) ?? 'unknown';
  }

  Future<void> createRepo(String token, String name,
      {String description = 'Built with Liberto'}) async {
    final res = await http
        .post(Uri.parse('$_api/user/repos'),
            headers: _h(token),
            body: jsonEncode({
              'name': name,
              'description': description,
              'private': false,
              'auto_init': false,
            }))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode == 200 || res.statusCode == 201) return;
    if (res.statusCode == 422) return; // already exists → keep going
    throw GitHubError(
        'ساخت ریپو $name نشکست! HTTP ${res.statusCode}: ${_err(res.body)}');
  }

  Future<void> putFile(String token, String owner, String repo, String path,
      String content, {String branch = 'main'}) async {
    final res = await http
        .put(Uri.parse('$_api/repos/$owner/$repo/contents/$path'),
            headers: _h(token),
            body: jsonEncode({
              'message': 'Liberto: $path',
              'content': base64Encode(utf8.encode(content)),
              'branch': branch,
            }))
        .timeout(const Duration(seconds: 120));
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw GitHubError('نوشتن فایل $path شکست (HTTP ${res.statusCode})');
    }
  }

  /// Pushes all project files. README first (creates the default branch).
  Future<void> pushAllFiles(
      String token, String owner, String repo, Map<String, String> files) async {
    final ordered = <String, String>{
      'README.md': files['README.md'] ??
          'Built with [Liberto] — $repo',
      ...files,
    };
    for (final e in ordered.entries) {
      await putFile(token, owner, repo, e.key, e.value);
    }
  }

  Future<ActionRun?> latestRun(String token, String owner, String repo) async {
    try {
      final res = await http
          .get(Uri.parse('$_api/repos/$owner/$repo/actions/runs?per_page=1'),
              headers: _h(token))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final runs = (jsonDecode(res.body)['workflow_runs'] as List?) ?? const [];
      if (runs.isEmpty) return null;
      final r = runs.first as Map<String, dynamic>;
      return ActionRun(
        id: r['id'] as int,
        status: (r['status'] as String?) ?? 'unknown',
        conclusion: r['conclusion'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listArtifacts(
      String token, String owner, String repo, int runId) async {
    final res = await http
        .get(
            Uri.parse('$_api/repos/$owner/$repo/actions/runs/$runId/artifacts'),
            headers: _h(token))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw GitHubError('دریافت artifacts شکست (HTTP ${res.statusCode})');
    }
    final arts = (jsonDecode(res.body)['artifacts'] as List?) ?? const [];
    return arts.cast<Map<String, dynamic>>();
  }

  /// Downloads the artifact zip, extracts it, and copies the first APK to [destApkPath].
  Future<void> downloadApkArtifact(String token, String owner, String repo,
      int artifactId, String destApkPath) async {
    final client = http.Client();
    try {
      final req = http.Request(
          'GET', Uri.parse('$_api/repos/$owner/$repo/actions/artifacts/$artifactId/zip'))
        ..headers.addAll(_h(token));
      final streamed = await client.send(req).timeout(const Duration(seconds: 300));
      if (streamed.statusCode != 200) {
        throw GitHubError(
            'دانلود فایل نصب شکست (HTTP ${streamed.statusCode})');
      }
      final bytes = await streamed.stream.toBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive.files) {
        if (!f.name.toLowerCase().endsWith('.apk')) continue;
        final out = File(destApkPath);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>);
        return;
      }
      throw GitHubError('APK در artifact پیدا نشد');
    } finally {
      client.close();
    }
  }

  static String _err(String body) {
    try {
      final o = jsonDecode(body);
      final msg = o['message'] as String?;
      final errors = o['errors'] as List?;
      if (errors != null && errors.isNotEmpty) {
        final first = errors.first as Map<String, dynamic>;
        return '${msg ?? ''} ${first['message'] ?? ''}';
      }
      return msg ?? body;
    } catch (_) {
      return body;
    }
  }
}
