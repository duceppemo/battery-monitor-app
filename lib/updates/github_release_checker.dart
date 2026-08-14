import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class GithubReleaseAsset {
  const GithubReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
  });
  final String name;
  final Uri downloadUrl;
  final int sizeBytes;
}

class GithubRelease {
  const GithubRelease({
    required this.version,
    required this.url,
    required this.assets,
  });
  final String version;
  final Uri url;
  final List<GithubReleaseAsset> assets;

  GithubReleaseAsset? get firmwareAsset {
    for (final asset in assets) {
      final name = asset.name.toLowerCase();
      if (name.endsWith('.bin') && !name.contains('factory')) return asset;
    }
    return null;
  }
}

class GithubReleaseChecker {
  GithubReleaseChecker({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;

  static const _requestTimeout = Duration(seconds: 12);

  Future<GithubRelease?> latestAppRelease() =>
      _latest('duceppemo/battery-monitor-app');
  Future<GithubRelease?> latestFirmwareRelease() =>
      _latest('duceppemo/battery_current_monitor');

  Future<GithubRelease?> _latest(String repository) async {
    final response = await _get(
      Uri.parse('https://api.github.com/repos/$repository/releases/latest'),
    );
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('GitHub returned ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = json['tag_name'] as String?;
    final url = json['html_url'] as String?;
    if (tag == null || url == null) return null;
    final assets = (json['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((asset) {
          final name = asset['name'] as String?;
          final download = asset['browser_download_url'] as String?;
          if (name == null || download == null) return null;
          return GithubReleaseAsset(
            name: name,
            downloadUrl: Uri.parse(download),
            sizeBytes: asset['size'] as int? ?? 0,
          );
        })
        .whereType<GithubReleaseAsset>()
        .toList(growable: false);
    return GithubRelease(
      version: tag.replaceFirst(RegExp(r'^v'), ''),
      url: Uri.parse(url),
      assets: assets,
    );
  }

  Future<Uint8List> download(GithubReleaseAsset asset) async {
    final response = await _get(asset.downloadUrl);
    if (response.statusCode != 200) {
      throw Exception('Firmware download returned ${response.statusCode}');
    }
    if (response.bodyBytes.isEmpty) throw Exception('Firmware file is empty');
    return response.bodyBytes;
  }

  Future<http.Response> _get(Uri url) => _client.get(
        url,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'BatteryMonitorApp',
        },
      ).timeout(_requestTimeout);

  static String describeRequestError(Object error) {
    // package:http wraps platform SocketExceptions in ClientException, so use
    // both the concrete type and its message to give a useful offline hint.
    if (error is SocketException ||
        error.toString().contains('SocketException')) {
      return 'Could not reach GitHub. Connect the tablet to Wi-Fi or cellular internet; the monitor\'s BatteryMonitor Wi-Fi is local-only.';
    }
    if (error is TimeoutException) {
      return 'GitHub did not respond. Check the internet connection and try again.';
    }
    return error.toString();
  }

  static bool isNewer(String candidate, String installed) {
    List<int> parse(String value) => value
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final a = parse(candidate), b = parse(installed);
    for (var index = 0; index < 3; index++) {
      final left = index < a.length ? a[index] : 0,
          right = index < b.length ? b[index] : 0;
      if (left != right) return left > right;
    }
    return false;
  }
}
