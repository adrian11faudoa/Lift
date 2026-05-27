import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../presentation/themes/app_theme.dart';

// ─────────────────────────────────────────────────────────────
// PRODUCT IDs — match RevenueCat & App Store / Play Console
// ─────────────────────────────────────────────────────────────
class ProductIds {
  ProductIds._();
  static const proMonthly = 'ironlog_pro_monthly';
  static const proYearly  = 'ironlog_pro_yearly';
  static const lifetime   = 'ironlog_lifetime';
}

class EntitlementIds {
  EntitlementIds._();
  static const pro = 'pro_access';
}

// ─────────────────────────────────────────────────────────────
// SUBSCRIPTION SERVICE
// ─────────────────────────────────────────────────────────────
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  CustomerInfo? _customerInfo;
  Offerings?    _offerings;

  Future<void> initialize({
    required String revenueCatApiKey,
    String?  userId,
  }) async {
    await Purchases.setLogLevel(LogLevel.debug);
    final config = PurchasesConfiguration(revenueCatApiKey);
    await Purchases.configure(config);
    if (userId != null) {
      await Purchases.logIn(userId);
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      _customerInfo = await Purchases.getCustomerInfo();
      _offerings    = await Purchases.getOfferings();
    } catch (e) {
      debugPrint('[SubscriptionService] Refresh error: $e');
    }
  }

  // ── SUBSCRIPTION STATUS ──────────────────────────────────────
  bool get isPro {
    return _customerInfo?.entitlements.active
        .containsKey(EntitlementIds.pro) ?? false;
  }

  SubscriptionTier get currentTier {
    if (!isPro) return SubscriptionTier.free;
    final activeEntitlement = _customerInfo
        ?.entitlements.active[EntitlementIds.pro];
    if (activeEntitlement == null) return SubscriptionTier.free;
    return switch (activeEntitlement.productIdentifier) {
      ProductIds.lifetime   => SubscriptionTier.lifetime,
      ProductIds.proYearly  => SubscriptionTier.proYearly,
      _                     => SubscriptionTier.proMonthly,
    };
  }

  DateTime? get expirationDate {
    return _customerInfo?.entitlements.active[EntitlementIds.pro]
        ?.expirationDate != null
        ? DateTime.tryParse(
            _customerInfo!.entitlements.active[EntitlementIds.pro]!
                .expirationDate!)
        : null;
  }

  // ── PURCHASES ────────────────────────────────────────────────
  Future<PurchaseResult> purchaseMonthly() async =>
      _purchase(ProductIds.proMonthly);

  Future<PurchaseResult> purchaseYearly() async =>
      _purchase(ProductIds.proYearly);

  Future<PurchaseResult> purchaseLifetime() async =>
      _purchase(ProductIds.lifetime);

  Future<PurchaseResult> _purchase(String productId) async {
    try {
      final offering = _offerings?.current;
      if (offering == null) {
        return PurchaseResult.error('No offerings available');
      }

      Package? package;
      for (final p in offering.availablePackages) {
        if (p.storeProduct.identifier == productId) {
          package = p;
          break;
        }
      }
      if (package == null) {
        return PurchaseResult.error('Product not found: $productId');
      }

      _customerInfo = (await Purchases.purchasePackage(package)).customerInfo;
      await _refresh();
      return PurchaseResult.success();
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseResult.cancelled();
      }
      return PurchaseResult.error(e.toString());
    } catch (e) {
      return PurchaseResult.error(e.toString());
    }
  }

  Future<PurchaseResult> restore() async {
    try {
      _customerInfo = await Purchases.restorePurchases();
      return isPro ? PurchaseResult.success() : PurchaseResult.nothingToRestore();
    } catch (e) {
      return PurchaseResult.error(e.toString());
    }
  }

  // ── OFFERINGS ────────────────────────────────────────────────
  List<SubscriptionPackageInfo> get packages {
    final result = <SubscriptionPackageInfo>[];
    final offering = _offerings?.current;
    if (offering == null) return result;

    for (final package in offering.availablePackages) {
      result.add(SubscriptionPackageInfo(
        productId:    package.storeProduct.identifier,
        title:        package.storeProduct.title,
        description:  package.storeProduct.description,
        priceString:  package.storeProduct.priceString,
        price:        package.storeProduct.price,
        period:       _packagePeriod(package),
      ));
    }
    return result;
  }

  String _packagePeriod(Package package) {
    return switch (package.packageType) {
      PackageType.monthly  => 'month',
      PackageType.annual   => 'year',
      PackageType.lifetime => 'once',
      _ => '',
    };
  }
}

// ─────────────────────────────────────────────────────────────
// RESULT TYPES
// ─────────────────────────────────────────────────────────────
sealed class PurchaseResult {
  const PurchaseResult();
  factory PurchaseResult.success()         = PurchaseSuccess;
  factory PurchaseResult.cancelled()       = PurchaseCancelled;
  factory PurchaseResult.nothingToRestore()= PurchaseNothingToRestore;
  factory PurchaseResult.error(String msg) = PurchaseError;
}

class PurchaseSuccess         extends PurchaseResult { const PurchaseSuccess(); }
class PurchaseCancelled       extends PurchaseResult { const PurchaseCancelled(); }
class PurchaseNothingToRestore extends PurchaseResult { const PurchaseNothingToRestore(); }
class PurchaseError extends PurchaseResult {
  const PurchaseError(this.message);
  final String message;
}

// ─────────────────────────────────────────────────────────────
// PACKAGE INFO MODEL
// ─────────────────────────────────────────────────────────────
class SubscriptionPackageInfo {
  const SubscriptionPackageInfo({
    required this.productId,
    required this.title,
    required this.description,
    required this.priceString,
    required this.price,
    required this.period,
  });
  final String productId;
  final String title;
  final String description;
  final String priceString;
  final double price;
  final String period;
}

// ─────────────────────────────────────────────────────────────
// PAYWALL PAGE
// ─────────────────────────────────────────────────────────────
class PaywallPage extends ConsumerStatefulWidget {
  const PaywallPage({super.key, this.highlightFeature});
  final String? highlightFeature;

  @override
  ConsumerState<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends ConsumerState<PaywallPage> {
  String _selectedPlan = ProductIds.proYearly;
  bool _isPurchasing   = false;
  String? _errorMsg;

  static const _features = [
    (Icons.block,               'Remove all ads',              true),
    (Icons.psychology_outlined, 'AI coaching & programming',   true),
    (Icons.bar_chart_rounded,   'Advanced analytics',          true),
    (Icons.cloud_sync_outlined, 'Unlimited cloud backup',      true),
    (Icons.download_rounded,    'Export workouts (CSV/PDF)',    true),
    (Icons.fitness_center,      'Premium programs library',    true),
    (Icons.code_rounded,        'Advanced scripting engine',   true),
    (Icons.monitor_heart_outlined,'Recovery metrics',          true),
    (Icons.palette_outlined,    'Exclusive themes',            true),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            backgroundColor: AppTheme.darkBg,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end:   Alignment.bottomRight,
                    colors: [
                      Color(0xFF1A1AFF),
                      Color(0xFF0066CC),
                    ],
                  ),
                ),
                child: const SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.workspace_premium, size: 52, color: Color(0xFFFFD700)),
                      SizedBox(height: 12),
                      Text(
                        'IronLog Pro',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Unlock your full potential',
                        style: TextStyle(fontSize: 15, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Features ─────────────────────────────────
                ..._features.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.check, size: 16, color: AppTheme.accentGreen),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        f.$2,
                        style: const TextStyle(fontSize: 15, color: AppTheme.darkText),
                      ),
                    ],
                  ),
                )),

                const SizedBox(height: 28),

                // ── Plan selector ─────────────────────────────
                const Text(
                  'Choose your plan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.darkText),
                ),
                const SizedBox(height: 12),

                _PlanCard(
                  productId: ProductIds.proMonthly,
                  title:     'Monthly',
                  price:     '\$9.99',
                  period:    '/month',
                  isSelected: _selectedPlan == ProductIds.proMonthly,
                  onTap: () => setState(() => _selectedPlan = ProductIds.proMonthly),
                ),
                const SizedBox(height: 10),
                _PlanCard(
                  productId:  ProductIds.proYearly,
                  title:      'Yearly',
                  price:      '\$59.99',
                  period:     '/year',
                  badge:      'Save 50%',
                  isSelected: _selectedPlan == ProductIds.proYearly,
                  onTap: () => setState(() => _selectedPlan = ProductIds.proYearly),
                ),
                const SizedBox(height: 10),
                _PlanCard(
                  productId:  ProductIds.lifetime,
                  title:      'Lifetime',
                  price:      '\$149.99',
                  period:     'once',
                  badge:      'Best Value',
                  isSelected: _selectedPlan == ProductIds.lifetime,
                  onTap: () => setState(() => _selectedPlan = ProductIds.lifetime),
                ),

                const SizedBox(height: 24),

                // ── Error message ─────────────────────────────
                if (_errorMsg != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.accentRed.withOpacity(0.3)),
                    ),
                    child: Text(_errorMsg!, style: const TextStyle(color: AppTheme.accentRed, fontSize: 13)),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Subscribe button ──────────────────────────
                FilledButton(
                  onPressed: _isPurchasing ? null : _purchase,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1AFF),
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isPurchasing
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Start Pro',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                ),

                const SizedBox(height: 12),

                // ── Restore ───────────────────────────────────
                TextButton(
                  onPressed: _restore,
                  child: const Text('Restore purchases', style: TextStyle(color: AppTheme.darkSubtext)),
                ),

                const SizedBox(height: 8),

                const Text(
                  'Cancel anytime. No commitments. Subscriptions auto-renew unless cancelled.',
                  style: TextStyle(fontSize: 11, color: AppTheme.darkSubtext),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _purchase() async {
    setState(() { _isPurchasing = true; _errorMsg = null; });
    final result = await switch (_selectedPlan) {
      ProductIds.proMonthly => SubscriptionService.instance.purchaseMonthly(),
      ProductIds.proYearly  => SubscriptionService.instance.purchaseYearly(),
      _                     => SubscriptionService.instance.purchaseLifetime(),
    };
    if (mounted) {
      setState(() => _isPurchasing = false);
      switch (result) {
        case PurchaseSuccess():
          ref.read(isPremiumProvider.notifier).state = true;
          if (mounted) Navigator.pop(context);
        case PurchaseCancelled():
          break;
        case PurchaseNothingToRestore():
          setState(() => _errorMsg = 'No purchases found to restore');
        case PurchaseError(:final message):
          setState(() => _errorMsg = message);
      }
    }
  }

  Future<void> _restore() async {
    setState(() => _isPurchasing = true);
    final result = await SubscriptionService.instance.restore();
    if (mounted) {
      setState(() => _isPurchasing = false);
      switch (result) {
        case PurchaseSuccess():
          ref.read(isPremiumProvider.notifier).state = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pro access restored!')),
          );
          Navigator.pop(context);
        case PurchaseNothingToRestore():
          setState(() => _errorMsg = 'No active subscription found');
        default:
          break;
      }
    }
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.productId,
    required this.title,
    required this.price,
    required this.period,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  final String  productId;
  final String  title;
  final String  price;
  final String  period;
  final bool    isSelected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:  isSelected ? const Color(0xFF1A1AFF).withOpacity(0.1) : AppTheme.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:  isSelected ? const Color(0xFF1A1AFF) : AppTheme.darkBorder,
            width:  isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:  isSelected ? const Color(0xFF1A1AFF) : Colors.transparent,
                border: Border.all(
                  color: isSelected ? const Color(0xFF1A1AFF) : AppTheme.darkBorder,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            // Title
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppTheme.darkText,
                ),
              ),
            ),
            // Badge
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentGreen,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // Price
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : AppTheme.darkText,
                  ),
                ),
                Text(
                  period,
                  style: const TextStyle(fontSize: 11, color: AppTheme.darkSubtext),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
