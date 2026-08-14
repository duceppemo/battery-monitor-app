import 'dart:io';

import 'package:battery_monitor_app/updates/github_release_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

void main() {
  test('parses a public firmware release and selects its OTA asset', () async {
    final checker = GithubReleaseChecker(
      client: MockClient((request) async {
        expect(request.headers['user-agent'], 'BatteryMonitorApp');
        return Response('''
          {
            "tag_name": "v0.5.1",
            "html_url": "https://github.com/duceppemo/battery_current_monitor/releases/tag/v0.5.1",
            "assets": [
              {"name": "battery-monitor-0.5.1.factory.bin", "browser_download_url": "https://example.invalid/factory.bin", "size": 10},
              {"name": "battery-monitor-0.5.1.bin", "browser_download_url": "https://example.invalid/ota.bin", "size": 20}
            ]
          }
        ''', 200);
      }),
    );

    final release = await checker.latestFirmwareRelease();

    expect(release?.version, '0.5.1');
    expect(release?.firmwareAsset?.name, 'battery-monitor-0.5.1.bin');
    expect(GithubReleaseChecker.isNewer('0.5.1', '0.5.0'), isTrue);
    expect(GithubReleaseChecker.isNewer('0.3.0', '0.3.0+6'), isFalse);
  });

  test('explains GitHub network failures without exposing socket details', () {
    final message = GithubReleaseChecker.describeRequestError(
      const SocketException('Failed host lookup'),
    );

    expect(message, contains('BatteryMonitor Wi-Fi is local-only'));
  });
}
