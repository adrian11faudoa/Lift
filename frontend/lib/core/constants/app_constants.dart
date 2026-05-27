// lib/core/constants/app_constants.dart

class AppConstants {
  AppConstants._();

  static const appName    = 'IronLog';
  static const appVersion = '1.0.0';
  static const appBuild   = 1;

  // ─── API ──────────────────────────────────────────────────────
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );
  static const apiVersion = 'v1';
  static const apiTimeout = Duration(seconds: 30);

  // ─── DATABASE ─────────────────────────────────────────────────
  static const dbName    = 'ironlog_db';
  static const dbVersion = 1;

  // ─── TRAINING ─────────────────────────────────────────────────
  static const defaultRestSeconds  = 90;
  static const maxSetsPerExercise  = 20;
  static const maxExercisesPerSession = 30;
  static const maxProgramWeeks     = 52;

  // Standard bar weights (kg)
  static const barWeightMens   = 20.0;
  static const barWeightWomens = 15.0;
  static const barWeightEZ     = 10.0;
  static const barWeightTrap   = 25.0;

  // Available plates (kg)
  static const List<double> standardPlatesKg = [
    25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25, 0.5, 0.25
  ];
  static const List<double> standardPlatesLb = [
    45.0, 35.0, 25.0, 10.0, 5.0, 2.5
  ];

  // ─── ANALYTICS ────────────────────────────────────────────────
  static const minSetsForPlateau   = 3;
  static const plateauVariancePct  = 0.02;  // < 2% weight change = plateau
  static const optimalSetsPerWeek  = 15;    // Per muscle group
  static const maxSetsBeforeDeload = 20;

  // ─── ADS ──────────────────────────────────────────────────────
  static const adInterstitialCooldownMinutes = 10;
  static const adRewardedCooldownMinutes     = 5;

  // ─── SYNC ─────────────────────────────────────────────────────
  static const syncIntervalMinutes = 5;
  static const syncMaxRetries      = 3;
  static const syncBatchSize       = 50;

  // ─── SUBSCRIPTION ─────────────────────────────────────────────
  static const revenueCatApiKeyAndroid = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const revenueCatApiKeyIos     = String.fromEnvironment('REVENUECAT_IOS_KEY');

  // ─── LINKS ────────────────────────────────────────────────────
  static const privacyPolicyUrl = 'https://ironlog.app/privacy';
  static const termsOfServiceUrl= 'https://ironlog.app/terms';
  static const supportEmail     = 'support@ironlog.app';
}

// ─────────────────────────────────────────────────────────────
// lib/core/constants/assets.dart
// ─────────────────────────────────────────────────────────────
class Assets {
  Assets._();

  // Animations (Lottie)
  static const animWorkoutComplete = 'assets/animations/workout_complete.json';
  static const animNewPR           = 'assets/animations/new_pr.json';
  static const animLoading         = 'assets/animations/loading.json';

  // Images
  static const imgOnboarding1 = 'assets/images/onboarding_1.png';
  static const imgOnboarding2 = 'assets/images/onboarding_2.png';
  static const imgOnboarding3 = 'assets/images/onboarding_3.png';
  static const imgEmptyState  = 'assets/images/empty_barbell.png';
  static const imgProBadge    = 'assets/images/pro_badge.png';

  // Icons
  static const iconAppLogo    = 'assets/icons/ironlog_logo.svg';
  static const iconGoogle     = 'assets/icons/google.svg';
  static const iconApple      = 'assets/icons/apple.svg';
}
