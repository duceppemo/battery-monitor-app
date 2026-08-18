import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A monitor the app has connected to before, identified by its stable
/// per-chip `ID` (see BLE_PROTOCOL.md) rather than the OS-assigned BLE
/// address, which can change between reconnects. [lastDeviceAddress] is the
/// address to try first on a quick reconnect; if the device isn't reachable
/// at that address (a new random address, or simply out of range), the user
/// falls back to a normal scan.
class SavedMonitor {
  const SavedMonitor({
    required this.id,
    required this.name,
    required this.lastDeviceAddress,
    required this.lastConnectedAt,
  });

  final String id;
  final String name;
  final String lastDeviceAddress;
  final DateTime lastConnectedAt;

  SavedMonitor copyWith({
    String? name,
    String? lastDeviceAddress,
    DateTime? lastConnectedAt,
  }) =>
      SavedMonitor(
        id: id,
        name: name ?? this.name,
        lastDeviceAddress: lastDeviceAddress ?? this.lastDeviceAddress,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      );

  Map<String, Object> toJson() => {
        'id': id,
        'name': name,
        'address': lastDeviceAddress,
        'lastConnectedAt': lastConnectedAt.toIso8601String(),
      };

  static SavedMonitor? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final address = json['address'] as String?;
    final lastConnectedAtText = json['lastConnectedAt'] as String?;
    if (id == null || name == null || address == null || lastConnectedAtText == null) {
      return null;
    }
    final lastConnectedAt = DateTime.tryParse(lastConnectedAtText);
    if (lastConnectedAt == null) return null;
    return SavedMonitor(
      id: id,
      name: name,
      lastDeviceAddress: address,
      lastConnectedAt: lastConnectedAt,
    );
  }
}

/// Persists the list of monitors this app has connected to, most-recent
/// first. Bounded to a handful of entries -- this is meant for someone's
/// own few monitors (house bank, starter battery, a friend's boat), not an
/// address book.
class SavedMonitorStore {
  static const _key = 'saved_monitors_v1';
  static const maxEntries = 10;

  Future<List<SavedMonitor>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final text = preferences.getString(_key);
    if (text == null) return const [];
    try {
      final decoded = jsonDecode(text) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SavedMonitor.tryFromJson)
          .whereType<SavedMonitor>()
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<void> _save(List<SavedMonitor> monitors) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode(monitors.map((m) => m.toJson()).toList(growable: false)),
    );
  }

  /// Records a successful connection: updates the existing entry (name is
  /// kept, address/timestamp refreshed) or adds a new one, most-recent
  /// first, trimmed to [maxEntries].
  Future<List<SavedMonitor>> recordConnection({
    required String id,
    required String defaultName,
    required String deviceAddress,
  }) async {
    final monitors = (await load()).toList();
    final existingIndex = monitors.indexWhere((m) => m.id == id);
    final updated = existingIndex >= 0
        ? monitors.removeAt(existingIndex).copyWith(
              lastDeviceAddress: deviceAddress,
              lastConnectedAt: DateTime.now(),
            )
        : SavedMonitor(
            id: id,
            name: defaultName,
            lastDeviceAddress: deviceAddress,
            lastConnectedAt: DateTime.now(),
          );
    monitors.insert(0, updated);
    final trimmed = monitors.take(maxEntries).toList(growable: false);
    await _save(trimmed);
    return trimmed;
  }

  Future<List<SavedMonitor>> rename(String id, String name) async {
    final monitors = (await load()).toList();
    final index = monitors.indexWhere((m) => m.id == id);
    if (index < 0) return monitors;
    monitors[index] = monitors[index].copyWith(name: name);
    await _save(monitors);
    return monitors;
  }

  Future<List<SavedMonitor>> remove(String id) async {
    final monitors = (await load()).toList()..removeWhere((m) => m.id == id);
    await _save(monitors);
    return monitors;
  }
}
