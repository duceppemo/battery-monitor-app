import 'dart:convert';
import 'dart:ui' as ui;

import 'package:battery_monitor_app/models/capacity_test_report.dart';
import 'package:battery_monitor_app/models/session_log.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Full capacity test report: a discharge curve plus a pass/fail read on the
/// observed capacity against the rated capacity, optionally normalized to a
/// reference discharge rate via Peukert's law. Everything here is computed
/// locally from [summary]/[entries]; nothing is fetched from the monitor.
class CapacityReportScreen extends StatefulWidget {
  const CapacityReportScreen({
    super.key,
    required this.summary,
    required this.entries,
    this.deviceInfo,
    this.temperatureFahrenheit = false,
  });

  final TestSessionSummary summary;
  final List<SessionLogEntry> entries;
  final String? deviceInfo;
  final bool temperatureFahrenheit;

  @override
  State<CapacityReportScreen> createState() => _CapacityReportScreenState();
}

class _CapacityReportScreenState extends State<CapacityReportScreen> {
  final _exponentController = TextEditingController();
  final _referenceHoursController = TextEditingController();
  final _thresholdController = TextEditingController(text: '80');

  late CapacityTestReport _report;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void dispose() {
    _exponentController.dispose();
    _referenceHoursController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  void _recompute() {
    _report = CapacityTestReport.compute(
      summary: widget.summary,
      entries: widget.entries,
      peukertExponent: double.tryParse(_exponentController.text.trim()),
      referenceDischargeHours:
          double.tryParse(_referenceHoursController.text.trim()),
      passThresholdPercent:
          double.tryParse(_thresholdController.text.trim()) ?? 80,
    );
  }

  Future<void> _share() async {
    final text = _reportText(_report, widget.deviceInfo);
    final stem = widget.summary.metadata.displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final fileName =
        'capacity-report-${stem.isEmpty ? 'session' : stem}.txt';
    try {
      await SharePlus.instance.share(ShareParams(
        title: '${widget.summary.metadata.displayName} capacity report',
        text: text,
        files: [
          XFile.fromData(utf8.encode(text), mimeType: 'text/plain', name: fileName),
        ],
        fileNameOverrides: [fileName],
      ));
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Share failed: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final metadata = widget.summary.metadata;
    return Scaffold(
      appBar: AppBar(
        title: Text('${metadata.displayName} report'),
        actions: [
          IconButton(
            onPressed: _share,
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share report',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _VerdictBanner(report: report),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Discharge curve',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (report.curve.length < 2)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                        'Not enough voltage samples were captured for a curve.'),
                  )
                else
                  SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _DischargeCurvePainter(
                        points: report.curve,
                        lineColor: Theme.of(context).colorScheme.primary,
                        gridColor: Theme.of(context).colorScheme.outlineVariant,
                        textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Voltage vs. capacity delivered since the test started.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Capacity',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricCard('Observed', _fmt(report.observedCapacityAh, 'Ah'),
                    report.percentOfRated == null
                        ? ''
                        : '${report.percentOfRated!.toStringAsFixed(1)}% of rated'),
                _MetricCard('Rated', metadata.ratedCapacityAh == null
                    ? 'Not set'
                    : '${metadata.ratedCapacityAh!.toStringAsFixed(3)} Ah', ''),
                _MetricCard('Avg. current',
                    _fmt(report.averageDischargeCurrentAmps, 'A'),
                    report.averageDischargeRateC == null
                        ? ''
                        : '${report.averageDischargeRateC!.toStringAsFixed(2)}C rate'),
                _MetricCard('Energy', _fmt(report.observedEnergyWh, 'Wh'), ''),
                _MetricCard('Duration', _fmtDuration(widget.summary.duration),
                    '${widget.summary.sampleCount} samples'),
                if (report.isRateAdjusted)
                  _MetricCard(
                    'Rate-adjusted',
                    _fmt(report.peukertAdjustedCapacityAh, 'Ah'),
                    '${report.peukertAdjustedPercentOfRated!.toStringAsFixed(1)}% of rated',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Rate adjustment (optional)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A battery delivers less capacity the faster it is '
                  'discharged. Fill these in to normalize this test to the '
                  'rate its rated capacity was actually specified at, using '
                  "Peukert's law. Leave either blank to skip the "
                  'adjustment — there is no built-in default, since '
                  'guessing wrong for the wrong chemistry would make the '
                  'verdict silently untrustworthy.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _exponentController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Peukert exponent',
                          helperText: 'e.g. 1.1–1.3 lead-acid, ~1.05 LiFePO₄',
                        ),
                        onChanged: (_) => setState(_recompute),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _referenceHoursController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Reference rate (hours)',
                          helperText: 'e.g. 20 for a C/20 rating',
                        ),
                        onChanged: (_) => setState(_recompute),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _thresholdController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Pass threshold (% of rated)',
                    helperText:
                        '80% is a common health cutoff; adjust for your needs',
                  ),
                  onChanged: (_) => setState(_recompute),
                ),
                if (report.isRateAdjusted) ...[
                  const SizedBox(height: 12),
                  Text(
                    "Peukert extrapolation is approximate and most reliable "
                    'when the test rate is reasonably close to the '
                    'reference rate — treat a large adjustment as a rough '
                    'estimate, not a precise figure.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Session details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (metadata.chemistry.trim().isNotEmpty)
                  _detailRow('Chemistry', metadata.chemistry.trim()),
                if (metadata.notes.trim().isNotEmpty)
                  _detailRow('Notes', metadata.notes.trim()),
                _detailRow('Voltage',
                    '${_fmt(widget.summary.voltageStartVolts, 'V')} → ${_fmt(widget.summary.voltageEndVolts, 'V')}'),
                _detailRow('Voltage range',
                    _minMax(widget.summary.voltageMinVolts, widget.summary.voltageMaxVolts, 'V')),
                _detailRow('Current range',
                    _minMax(widget.summary.currentMinAmps, widget.summary.currentMaxAmps, 'A')),
                _detailRow('Temperature range', _minMax(
                    _displayTemp(widget.summary.temperatureMinCelsius),
                    _displayTemp(widget.summary.temperatureMaxCelsius),
                    widget.temperatureFahrenheit ? '°F' : '°C')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double? _displayTemp(double? celsius) => celsius == null
      ? null
      : (widget.temperatureFahrenheit ? celsius * 9 / 5 + 32 : celsius);

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 130, child: Text(label)),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

String _fmt(double? value, String unit, {int decimals = 3}) =>
    value == null ? 'Unavailable' : '${value.toStringAsFixed(decimals)} $unit';

String _minMax(double? min, double? max, String unit) => min == null || max == null
    ? 'Unavailable'
    : '${min.toStringAsFixed(3)} to ${max.toStringAsFixed(3)} $unit';

String _fmtDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

String _reportText(CapacityTestReport report, String? deviceInfo) {
  final metadata = report.summary.metadata;
  final buffer = StringBuffer()
    ..writeln('${metadata.displayName} — capacity test report')
    ..writeln('Verdict: ${_verdictText(report.verdict)}');
  if (deviceInfo != null && deviceInfo.isNotEmpty) buffer.writeln('Device: $deviceInfo');
  if (metadata.chemistry.trim().isNotEmpty) buffer.writeln('Chemistry: ${metadata.chemistry.trim()}');
  if (metadata.ratedCapacityAh != null) {
    buffer.writeln('Rated capacity: ${metadata.ratedCapacityAh!.toStringAsFixed(3)} Ah');
  }
  buffer
    ..writeln('Duration: ${_fmtDuration(report.summary.duration)}')
    ..writeln('Observed capacity: ${_fmt(report.observedCapacityAh, 'Ah')}');
  if (report.percentOfRated != null) {
    buffer.writeln('Percent of rated: ${report.percentOfRated!.toStringAsFixed(1)}%');
  }
  if (report.isRateAdjusted) {
    buffer
      ..writeln('Rate-adjusted capacity: ${_fmt(report.peukertAdjustedCapacityAh, 'Ah')}')
      ..writeln('Rate-adjusted percent of rated: ${report.peukertAdjustedPercentOfRated!.toStringAsFixed(1)}%')
      ..writeln('Peukert exponent: ${report.peukertExponent}')
      ..writeln('Reference rate: C/${report.referenceDischargeHours}');
  }
  if (report.averageDischargeCurrentAmps != null) {
    buffer.writeln('Average discharge current: ${_fmt(report.averageDischargeCurrentAmps, 'A')}');
  }
  if (metadata.notes.trim().isNotEmpty) buffer.writeln('Notes: ${metadata.notes.trim()}');
  return buffer.toString();
}

String _verdictText(CapacityTestVerdict verdict) => switch (verdict) {
      CapacityTestVerdict.pass => 'PASS',
      CapacityTestVerdict.fail => 'FAIL',
      CapacityTestVerdict.inconclusive => 'INCONCLUSIVE (no rated capacity set)',
    };

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner({required this.report});
  final CapacityTestReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color background, Color foreground, IconData icon, String label) =
        switch (report.verdict) {
      CapacityTestVerdict.pass => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.check_circle,
          'PASS'
        ),
      CapacityTestVerdict.fail => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.cancel,
          'FAIL'
        ),
      CapacityTestVerdict.inconclusive => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.help_outline,
          'INCONCLUSIVE'
        ),
    };
    final percent = report.verdictPercent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    percent == null
                        ? 'Set a rated capacity when starting a test to get a verdict.'
                        : '${percent.toStringAsFixed(1)}% of rated capacity'
                            '${report.isRateAdjusted ? ' (rate-adjusted)' : ''}'
                            ' — threshold ${report.passThresholdPercent.toStringAsFixed(0)}%',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.detail);
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 155,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleMedium),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      );
}

class _DischargeCurvePainter extends CustomPainter {
  const _DischargeCurvePainter({
    required this.points,
    required this.lineColor,
    required this.gridColor,
    required this.textColor,
  });

  final List<CapacityCurvePoint> points;
  final Color lineColor;
  final Color gridColor;
  final Color textColor;

  static const double _leftAxisWidth = 46;
  static const double _bottomAxisHeight = 20;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final chartRect = Rect.fromLTWH(
      _leftAxisWidth,
      0,
      size.width - _leftAxisWidth,
      size.height - _bottomAxisHeight,
    );
    if (chartRect.width <= 0 || chartRect.height <= 0) return;

    var minVoltage = points.first.voltageVolts;
    var maxVoltage = points.first.voltageVolts;
    var maxAh = 0.0;
    for (final point in points) {
      if (point.voltageVolts < minVoltage) minVoltage = point.voltageVolts;
      if (point.voltageVolts > maxVoltage) maxVoltage = point.voltageVolts;
      if (point.dischargedAmpHours > maxAh) maxAh = point.dischargedAmpHours;
    }
    if (minVoltage == maxVoltage) {
      minVoltage -= 0.5;
      maxVoltage += 0.5;
    }
    if (maxAh <= 0) maxAh = 1;

    double xFor(double ah) => chartRect.left + (ah / maxAh) * chartRect.width;
    double yFor(double volts) => chartRect.top +
        chartRect.height -
        ((volts - minVoltage) / (maxVoltage - minVoltage)) * chartRect.height;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const gridLines = 4;
    for (var i = 0; i <= gridLines; i++) {
      final y = chartRect.top + chartRect.height * i / gridLines;
      canvas.drawLine(Offset(chartRect.left, y), Offset(chartRect.right, y), gridPaint);
      final voltage = maxVoltage - (maxVoltage - minVoltage) * i / gridLines;
      _drawText(canvas, voltage.toStringAsFixed(2), Offset(0, y - 6), textColor, 10);
    }

    _drawText(canvas, '0', Offset(chartRect.left, chartRect.bottom + 4), textColor, 10);
    _drawText(canvas, '${maxAh.toStringAsFixed(2)} Ah',
        Offset(chartRect.right - 40, chartRect.bottom + 4), textColor, 10);

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final offset = Offset(xFor(points[i].dischargedAmpHours), yFor(points[i].voltageVolts));
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(xFor(points.last.dischargedAmpHours), chartRect.bottom)
      ..lineTo(xFor(points.first.dischargedAmpHours), chartRect.bottom)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, chartRect.top),
          Offset(0, chartRect.bottom),
          [lineColor.withValues(alpha: 0.22), lineColor.withValues(alpha: 0.0)],
        ),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final endpointPaint = Paint()..color = lineColor;
    canvas.drawCircle(
      Offset(xFor(points.last.dischargedAmpHours), yFor(points.last.voltageVolts)),
      4,
      endpointPaint,
    );
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _DischargeCurvePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor;
}
