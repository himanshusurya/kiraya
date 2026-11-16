/// Build-time configuration, passed with --dart-define (see README).
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// "owner/repo" on GitHub whose Releases carry the APKs (for the update check).
  static const githubRepo = String.fromEnvironment('GITHUB_REPO');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
