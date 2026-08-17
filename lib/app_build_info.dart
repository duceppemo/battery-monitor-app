/// Human-readable identity shown in the app and included in support reports.
/// The Git revision is injected by the build command through `--dart-define`.
abstract final class AppBuildInfo {
  static const version = '0.3.5+14';
  static const gitRevision = String.fromEnvironment(
    'GIT_SHA',
    defaultValue: 'local',
  );

  static String get label => 'App $version  |  Build $gitRevision';
}
