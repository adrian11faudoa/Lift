import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../blocs/active_workout_notifier.dart';
import '../themes/app_theme.dart';

// ─────────────────────────────────────────────────────────────
// AD PLACEMENT ENUM — controls WHERE ads can appear
// ─────────────────────────────────────────────────────────────
/// CRITICAL: Ads are NEVER shown during active workouts.
/// The [AdManager] enforces this at the widget and service level.
enum AdPlacement {
  dashboard,        // ✅ Allowed
  workoutHistory,   // ✅ Allowed
  analytics,        // ✅ Allowed
  programMarket,    // ✅ Allowed
  workoutComplete,  // ✅ Allowed (post-workout summary)
  exerciseLibrary,  // ✅ Allowed
  // ❌ activeWorkout  — NEVER shown, not in this enum
  // ❌ logSet         — NEVER shown
  // ❌ restTimer      — NEVER shown
}

// ─────────────────────────────────────────────────────────────
// AD UNIT IDs (replace with real IDs for production)
// ─────────────────────────────────────────────────────────────
class AdUnitIds {
  AdUnitIds._();

  static String get banner => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/6300978111'   // Test ID
      : 'ca-app-pub-3940256099942544/2934735716';  // Test ID

  static String get interstitial => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-3940256099942544/4411468910';

  static String get rewarded => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-3940256099942544/1712485313';

  static String get nativeAdvanced => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/2247696110'
      : 'ca-app-pub-3940256099942544/3986624511';
}

// ─────────────────────────────────────────────────────────────
// AD MANAGER SERVICE
// ─────────────────────────────────────────────────────────────
class AdManager {
  AdManager._();
  static final AdManager instance = AdManager._();

  InterstitialAd? _interstitialAd;
  RewardedAd?     _rewardedAd;

  bool _isPreloadingInterstitial = false;
  bool _isPreloadingRewarded     = false;

  DateTime? _lastInterstitialTime;
  static const _interstitialCooldown = Duration(minutes: 10);

  // ── INITIALIZATION ──────────────────────────────────────────
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _preloadInterstitial();
    _preloadRewarded();
  }

  // ── BANNER ADS ──────────────────────────────────────────────
  BannerAd createBannerAd() {
    return BannerAd(
      adUnitId: AdUnitIds.banner,
      size:     AdSize.banner,
      request:  const AdRequest(),
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('[AdManager] Banner failed: $error');
        },
      ),
    );
  }

  // ── INTERSTITIAL ADS ─────────────────────────────────────────
  void _preloadInterstitial() {
    if (_isPreloadingInterstitial) return;
    _isPreloadingInterstitial = true;
    InterstitialAd.load(
      adUnitId:     AdUnitIds.interstitial,
      request:      const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isPreloadingInterstitial = false;
        },
        onAdFailedToLoad: (err) {
          _isPreloadingInterstitial = false;
          debugPrint('[AdManager] Interstitial failed: $err');
        },
      ),
    );
  }

  /// Show interstitial — ONLY call from allowed placements.
  /// [isWorkoutActive] is checked before showing.
  Future<bool> showInterstitial({required bool isWorkoutActive}) async {
    // ✅ CRITICAL: Never interrupt workout
    if (isWorkoutActive) {
      debugPrint('[AdManager] Interstitial blocked: workout active');
      return false;
    }

    // Frequency cap
    if (_lastInterstitialTime != null) {
      final elapsed = DateTime.now().difference(_lastInterstitialTime!);
      if (elapsed < _interstitialCooldown) {
        debugPrint('[AdManager] Interstitial blocked: cooldown active');
        return false;
      }
    }

    if (_interstitialAd == null) {
      _preloadInterstitial();
      return false;
    }

    final completer = Completer<bool>();
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _lastInterstitialTime = DateTime.now();
        _preloadInterstitial();
        completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        _preloadInterstitial();
        completer.complete(false);
      },
    );
    _interstitialAd!.show();
    return completer.future;
  }

  // ── REWARDED ADS ─────────────────────────────────────────────
  void _preloadRewarded() {
    if (_isPreloadingRewarded) return;
    _isPreloadingRewarded = true;
    RewardedAd.load(
      adUnitId:     AdUnitIds.rewarded,
      request:      const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isPreloadingRewarded = false;
        },
        onAdFailedToLoad: (err) {
          _isPreloadingRewarded = false;
        },
      ),
    );
  }

  /// Show rewarded ad for premium feature unlock (free users).
  Future<bool> showRewardedAd({required bool isWorkoutActive}) async {
    if (isWorkoutActive) return false;
    if (_rewardedAd == null) {
      _preloadRewarded();
      return false;
    }
    final completer = Completer<bool>();
    bool rewarded = false;
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _preloadRewarded();
        completer.complete(rewarded);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd = null;
        _preloadRewarded();
        completer.complete(false);
      },
    );
    _rewardedAd!.show(
      onUserEarnedReward: (_, reward) {
        rewarded = true;
      },
    );
    return completer.future;
  }

  void dispose() {
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
  }
}

// ─────────────────────────────────────────────────────────────
// PREMIUM PROVIDER
// ─────────────────────────────────────────────────────────────
final isPremiumProvider = StateProvider<bool>((ref) => false);

// ─────────────────────────────────────────────────────────────
// AD BANNER WIDGET
// ─────────────────────────────────────────────────────────────
/// Smart banner that:
/// 1. Never shows if user has premium
/// 2. Never shows during active workout (enforced by checking state)
/// 3. Gracefully handles ad load failures
class AdBannerWidget extends ConsumerStatefulWidget {
  const AdBannerWidget({super.key, required this.placement});
  final AdPlacement placement;

  @override
  ConsumerState<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends ConsumerState<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    // Check premium BEFORE creating ad
    final isPremium = ref.read(isPremiumProvider);
    if (isPremium) return;

    // Check workout active
    final workoutActive = ref.read(activeWorkoutProvider).isActive;
    if (workoutActive) return;

    _bannerAd = AdManager.instance.createBannerAd()
      ..load().then((_) {
        if (mounted) setState(() => _isLoaded = true);
      }).catchError((_) {
        if (mounted) setState(() => _loadFailed = true);
      });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPremium     = ref.watch(isPremiumProvider);
    final workoutActive = ref.watch(activeWorkoutProvider).isActive;

    // Strictly hide for premium or during workout
    if (isPremium || workoutActive || _loadFailed || !_isLoaded) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      width:  _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// REWARDED AD BUTTON
// ─────────────────────────────────────────────────────────────
/// Button shown to free users to unlock a premium feature temporarily
/// by watching a rewarded ad.
class RewardedAdButton extends ConsumerWidget {
  const RewardedAdButton({
    super.key,
    required this.featureLabel,
    required this.onRewarded,
    this.child,
  });

  final String featureLabel;
  final VoidCallback onRewarded;
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium     = ref.watch(isPremiumProvider);
    final workoutActive = ref.watch(activeWorkoutProvider).isActive;

    if (isPremium) {
      return child ?? const SizedBox.shrink();
    }

    return OutlinedButton.icon(
      onPressed: workoutActive ? null : () async {
        final rewarded = await AdManager.instance.showRewardedAd(
          isWorkoutActive: workoutActive,
        );
        if (rewarded) onRewarded();
      },
      icon: const Icon(Icons.play_circle_outline, size: 18),
      label: Text('Watch ad to use $featureLabel'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryOrange,
        side: const BorderSide(color: AppTheme.primaryOrange),
      ),
    );
  }
}

// Missing import
class Completer<T> {
  late T _value;
  bool _isCompleted = false;
  final _completers = <void Function(T)>[];

  Future<T> get future => Future<T>(() async {
    while (!_isCompleted) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return _value;
  });

  void complete(T value) {
    _isCompleted = true;
    _value = value;
  }
}
