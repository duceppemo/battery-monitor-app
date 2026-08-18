import 'dart:math' as math;

import 'session_log.dart';

/// One point on the discharge curve: voltage at a given amount of capacity
/// already delivered since the session started (not wall-clock time), which
/// is the axis a capacity test is usually read against.
class CapacityCurvePoint {
  const CapacityCurvePoint({
    required this.dischargedAmpHours,
    required this.voltageVolts,
  });

  final double dischargedAmpHours;
  final double voltageVolts;
}

enum CapacityTestVerdict { pass, fail, inconclusive }

/// A capacity test report computed from a finished [TestSessionSummary] and
/// its raw entries. Everything here is derived, app-local math over data
/// already captured by [SessionLog]; nothing is fetched from the monitor.
///
/// The Peukert-adjusted figures only appear when the caller supplies both a
/// Peukert exponent and the discharge duration the rated capacity was
/// specified at ([referenceDischargeHours]) — there is no built-in default
/// for either, since guessing wrong for an unknown chemistry would make a
/// pass/fail verdict silently untrustworthy. Without them the report still
/// shows the raw observed-vs-rated comparison, just not rate-normalized.
class CapacityTestReport {
  const CapacityTestReport({
    required this.summary,
    required this.curve,
    required this.observedCapacityAh,
    required this.observedEnergyWh,
    required this.averageDischargeCurrentAmps,
    required this.averageDischargeRateC,
    required this.percentOfRated,
    required this.peukertAdjustedCapacityAh,
    required this.peukertAdjustedPercentOfRated,
    required this.peukertExponent,
    required this.referenceDischargeHours,
    required this.passThresholdPercent,
    required this.verdict,
  });

  final TestSessionSummary summary;
  final List<CapacityCurvePoint> curve;

  /// Ah delivered during the session (positive = discharge), straight from
  /// [TestSessionSummary.netAmpHours].
  final double? observedCapacityAh;
  final double? observedEnergyWh;
  final double? averageDischargeCurrentAmps;

  /// Average discharge current expressed as a multiple of the rated
  /// capacity, e.g. 0.5 means the test ran at roughly a 0.5C rate.
  final double? averageDischargeRateC;

  /// Observed capacity as a percentage of the rated capacity, with no rate
  /// adjustment applied.
  final double? percentOfRated;

  final double? peukertAdjustedCapacityAh;
  final double? peukertAdjustedPercentOfRated;
  final double? peukertExponent;
  final double? referenceDischargeHours;

  final double passThresholdPercent;
  final CapacityTestVerdict verdict;

  bool get isRateAdjusted => peukertAdjustedCapacityAh != null;

  /// The percentage the verdict was actually decided on: the rate-adjusted
  /// figure when available, otherwise the raw observed-vs-rated one.
  double? get verdictPercent => peukertAdjustedPercentOfRated ?? percentOfRated;

  static CapacityTestReport compute({
    required TestSessionSummary summary,
    required List<SessionLogEntry> entries,
    double? peukertExponent,
    double? referenceDischargeHours,
    double passThresholdPercent = 80,
    int maxCurvePoints = 300,
  }) {
    final ratedCapacityAh = summary.metadata.ratedCapacityAh;
    final observedCapacityAh = summary.netAmpHours;
    final observedEnergyWh = summary.netWattHours;
    final durationHours = summary.duration.inMilliseconds / 3600000.0;

    final averageDischargeCurrentAmps =
        (observedCapacityAh != null && durationHours > 0)
            ? observedCapacityAh / durationHours
            : null;

    final averageDischargeRateC = (averageDischargeCurrentAmps != null &&
            ratedCapacityAh != null &&
            ratedCapacityAh > 0)
        ? averageDischargeCurrentAmps / ratedCapacityAh
        : null;

    final percentOfRated = (observedCapacityAh != null &&
            ratedCapacityAh != null &&
            ratedCapacityAh > 0)
        ? 100 * observedCapacityAh / ratedCapacityAh
        : null;

    double? peukertAdjustedCapacityAh;
    double? peukertAdjustedPercentOfRated;
    if (observedCapacityAh != null &&
        observedCapacityAh > 0 &&
        averageDischargeCurrentAmps != null &&
        averageDischargeCurrentAmps > 0 &&
        peukertExponent != null &&
        peukertExponent > 0 &&
        referenceDischargeHours != null &&
        referenceDischargeHours > 0 &&
        ratedCapacityAh != null &&
        ratedCapacityAh > 0) {
      // Peukert's law: I^k * t = constant. Solving for the capacity an
      // observed I/t pair implies at a different (reference) current gives
      // C_ref = C_observed * (I_observed / I_reference) ^ (k - 1).
      final referenceCurrentAmps = ratedCapacityAh / referenceDischargeHours;
      final rateRatio = averageDischargeCurrentAmps / referenceCurrentAmps;
      peukertAdjustedCapacityAh = observedCapacityAh *
          math.pow(rateRatio, peukertExponent - 1).toDouble();
      peukertAdjustedPercentOfRated =
          100 * peukertAdjustedCapacityAh / ratedCapacityAh;
    }

    final verdictPercent = peukertAdjustedPercentOfRated ?? percentOfRated;
    final verdict = verdictPercent == null
        ? CapacityTestVerdict.inconclusive
        : (verdictPercent >= passThresholdPercent
            ? CapacityTestVerdict.pass
            : CapacityTestVerdict.fail);

    return CapacityTestReport(
      summary: summary,
      curve: _buildCurve(entries, maxCurvePoints),
      observedCapacityAh: observedCapacityAh,
      observedEnergyWh: observedEnergyWh,
      averageDischargeCurrentAmps: averageDischargeCurrentAmps,
      averageDischargeRateC: averageDischargeRateC,
      percentOfRated: percentOfRated,
      peukertAdjustedCapacityAh: peukertAdjustedCapacityAh,
      peukertAdjustedPercentOfRated: peukertAdjustedPercentOfRated,
      peukertExponent: peukertExponent,
      referenceDischargeHours: referenceDischargeHours,
      passThresholdPercent: passThresholdPercent,
      verdict: verdict,
    );
  }

  static List<CapacityCurvePoint> _buildCurve(
    List<SessionLogEntry> entries,
    int maxPoints,
  ) {
    final withVoltage =
        entries.where((entry) => entry.voltageVolts != null).toList();
    if (withVoltage.isEmpty) return const [];

    final startAh = withVoltage.first.netAmpHours;
    final points = withVoltage
        .map((entry) => CapacityCurvePoint(
              dischargedAmpHours: entry.netAmpHours - startAh,
              voltageVolts: entry.voltageVolts!,
            ))
        .toList();

    if (points.length <= maxPoints || maxPoints < 2) return points;

    final decimated = <CapacityCurvePoint>[];
    final step = (points.length - 1) / (maxPoints - 1);
    for (var i = 0; i < maxPoints; i++) {
      decimated.add(points[(i * step).round()]);
    }
    return decimated;
  }
}
