import 'package:battery_monitor_app/models/saved_monitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('recordConnection adds a new monitor most-recent first', () async {
    final store = SavedMonitorStore();

    final afterFirst = await store.recordConnection(
      id: 'AABBCCDDEEFF',
      defaultName: 'Battery Monitor EEFF',
      deviceAddress: 'addr-1',
    );
    expect(afterFirst, hasLength(1));
    expect(afterFirst.single.id, 'AABBCCDDEEFF');
    expect(afterFirst.single.name, 'Battery Monitor EEFF');
    expect(afterFirst.single.lastDeviceAddress, 'addr-1');

    final afterSecond = await store.recordConnection(
      id: '112233445566',
      defaultName: 'Battery Monitor 5566',
      deviceAddress: 'addr-2',
    );
    expect(afterSecond, hasLength(2));
    expect(afterSecond.first.id, '112233445566');
    expect(afterSecond.last.id, 'AABBCCDDEEFF');
  });

  test('recordConnection updates address/timestamp but keeps a renamed name',
      () async {
    final store = SavedMonitorStore();
    await store.recordConnection(
      id: 'AABBCCDDEEFF',
      defaultName: 'Battery Monitor EEFF',
      deviceAddress: 'addr-1',
    );
    await store.rename('AABBCCDDEEFF', 'House bank');

    final monitors = await store.recordConnection(
      id: 'AABBCCDDEEFF',
      defaultName: 'Battery Monitor EEFF',
      deviceAddress: 'addr-1-new',
    );

    expect(monitors, hasLength(1));
    expect(monitors.single.name, 'House bank');
    expect(monitors.single.lastDeviceAddress, 'addr-1-new');
  });

  test('remove forgets a monitor', () async {
    final store = SavedMonitorStore();
    await store.recordConnection(
      id: 'AABBCCDDEEFF',
      defaultName: 'Battery Monitor EEFF',
      deviceAddress: 'addr-1',
    );

    final monitors = await store.remove('AABBCCDDEEFF');

    expect(monitors, isEmpty);
    expect(await store.load(), isEmpty);
  });

  test('recordConnection trims to maxEntries, dropping the oldest', () async {
    final store = SavedMonitorStore();
    for (var i = 0; i < SavedMonitorStore.maxEntries + 2; i++) {
      await store.recordConnection(
        id: 'id-$i',
        defaultName: 'Monitor $i',
        deviceAddress: 'addr-$i',
      );
    }

    final monitors = await store.load();

    expect(monitors, hasLength(SavedMonitorStore.maxEntries));
    // Most recent inserts are index 0; the two oldest ("id-0", "id-1") were
    // dropped once the list grew past maxEntries.
    expect(monitors.map((m) => m.id), isNot(contains('id-0')));
    expect(monitors.map((m) => m.id), isNot(contains('id-1')));
    expect(monitors.first.id, 'id-${SavedMonitorStore.maxEntries + 1}');
  });

  test('persists across store instances via SharedPreferences', () async {
    await SavedMonitorStore().recordConnection(
      id: 'AABBCCDDEEFF',
      defaultName: 'Battery Monitor EEFF',
      deviceAddress: 'addr-1',
    );

    final monitors = await SavedMonitorStore().load();

    expect(monitors, hasLength(1));
    expect(monitors.single.id, 'AABBCCDDEEFF');
  });
}
