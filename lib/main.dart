import 'package:battery_monitor_app/ble/battery_monitor_ble.dart';
import 'package:battery_monitor_app/screens/monitor_dashboard.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const BatteryMonitorApp());
}

class BatteryMonitorApp extends StatelessWidget {
  const BatteryMonitorApp({super.key, this.ble});

  final BatteryMonitorBleClient? ble;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Battery Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: MonitorDashboard(ble: ble),
    );
  }
}
