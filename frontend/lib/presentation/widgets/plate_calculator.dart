import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../themes/app_theme.dart';

// ─────────────────────────────────────────────────────────────
// PLATE CALCULATOR
// The most-used tool in any gym app. Calculates what plates to
// put on the bar for a target weight.
// ─────────────────────────────────────────────────────────────
class PlateCalculatorSheet extends ConsumerStatefulWidget {
  const PlateCalculatorSheet({super.key, this.initialWeight});
  final double? initialWeight;

  @override
  ConsumerState<PlateCalculatorSheet> createState() => _PlateCalculatorSheetState();
}

class _PlateCalculatorSheetState extends ConsumerState<PlateCalculatorSheet> {
  late TextEditingController _weightCtrl;
  double _barWeight   = 20.0;   // kg (standard Olympic bar)
  bool   _useKg       = true;
  double _targetWeight= 100.0;

  // Available plates (per side) — in kg
  static const _platesKg = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25, 0.5, 0.25];
  static const _platesLb = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];

  // Bar options
  static const _barOptions = [
    (label: 'Men\'s Bar (20kg)', weight: 20.0),
    (label: 'Women\'s Bar (15kg)', weight: 15.0),
    (label: 'EZ Bar (10kg)', weight: 10.0),
    (label: 'Trap Bar (25kg)', weight: 25.0),
    (label: 'No Bar (0kg)', weight: 0.0),
  ];

  @override
  void initState() {
    super.initState();
    _targetWeight = widget.initialWeight ?? 100.0;
    _weightCtrl   = TextEditingController(text: _targetWeight.toStringAsFixed(1));
  }

  // ─── CALCULATION ─────────────────────────────────────────────
  Map<double, int> _calculatePlates() {
    final plates    = _useKg ? _platesKg : _platesLb;
    var remaining   = (_targetWeight - _barWeight) / 2;  // Per side
    final result    = <double, int>{};

    if (remaining <= 0) return result;

    for (final plate in plates) {
      final count = (remaining / plate).floor();
      if (count > 0) {
        result[plate] = count;
        remaining -= count * plate;
        remaining  = double.parse(remaining.toStringAsFixed(4)); // Float precision
      }
      if (remaining < 0.01) break;
    }

    return result;
  }

  double get _achievableWeight {
    final plates = _calculatePlates();
    var total = _barWeight;
    plates.forEach((plate, count) => total += plate * count * 2);
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final plateMap = _calculatePlates();
    final achievable = _achievableWeight;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: const BoxDecoration(
        color:        AppTheme.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle ──────────────────────────────────────────
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppTheme.darkBorder, borderRadius: BorderRadius.circular(2)),
          )),
          const SizedBox(height: 16),

          // ── Title ────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🏋️ Plate Calculator',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.darkText),
              ),
              // kg/lbs toggle
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true,  label: Text('kg')),
                  ButtonSegment(value: false, label: Text('lbs')),
                ],
                selected: {_useKg},
                onSelectionChanged: (sel) => setState(() => _useKg = sel.first),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return AppTheme.primaryBlue;
                    return AppTheme.darkCard;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Target weight input ──────────────────────────────
          Row(
            children: [
              // Decrement
              _AdjustButton(
                label: '-2.5',
                onTap: () => _adjustWeight(-2.5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryBlue,
                  ),
                  decoration: InputDecoration(
                    suffixText: _useKg ? 'kg' : 'lbs',
                    suffixStyle: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.darkSubtext,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryBlue),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.darkBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
                    ),
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null) setState(() => _targetWeight = parsed);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Increment
              _AdjustButton(
                label: '+2.5',
                onTap: () => _adjustWeight(2.5),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Bar selector ─────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _barOptions.map((opt) {
                final selected = opt.weight == _barWeight;
                return GestureDetector(
                  onTap: () => setState(() => _barWeight = opt.weight),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color:        selected ? AppTheme.primaryBlue.withOpacity(0.15) : AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(8),
                      border:       Border.all(
                        color: selected ? AppTheme.primaryBlue : AppTheme.darkBorder,
                      ),
                    ),
                    child: Text(
                      opt.label,
                      style: TextStyle(
                        fontSize:   12,
                        fontWeight: FontWeight.w600,
                        color:      selected ? AppTheme.primaryBlue : AppTheme.darkSubtext,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // ── Achievable weight (if not exact) ─────────────────
          if ((achievable - _targetWeight).abs() > 0.01)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin:  const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color:        AppTheme.primaryOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border:       Border.all(color: AppTheme.primaryOrange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppTheme.primaryOrange),
                  const SizedBox(width: 8),
                  Text(
                    'Closest achievable: ${achievable.toStringAsFixed(2)}${_useKg ? "kg" : "lbs"}',
                    style: const TextStyle(fontSize: 13, color: AppTheme.primaryOrange),
                  ),
                ],
              ),
            ),

          // ── Plate visualization ──────────────────────────────
          const Text(
            'PLATES PER SIDE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.darkSubtext,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),

          if (plateMap.isEmpty)
            const Text(
              'Weight ≤ bar weight. Remove plates.',
              style: TextStyle(color: AppTheme.darkSubtext, fontSize: 14),
            )
          else ...[
            // Bar visualization
            _BarVisualization(plateMap: plateMap, useKg: _useKg),
            const SizedBox(height: 16),
            // Plate list
            ...plateMap.entries.map((entry) => _PlateRow(
              weight: entry.key,
              count:  entry.value,
              useKg:  _useKg,
            )),
          ],

          const SizedBox(height: 16),

          // ── Totals ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:        AppTheme.darkCard,
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(
              children: [
                _TotalRow(label: 'Bar weight',      value: '${_barWeight.toStringAsFixed(1)}${_useKg ? "kg" : "lbs"}'),
                _TotalRow(
                  label: 'Plates (each side)',
                  value: '${((_achievableWeight - _barWeight) / 2).toStringAsFixed(2)}${_useKg ? "kg" : "lbs"}',
                ),
                const Divider(color: AppTheme.darkBorder, height: 16),
                _TotalRow(
                  label: 'Total',
                  value: '${_achievableWeight.toStringAsFixed(2)}${_useKg ? "kg" : "lbs"}',
                  isTotal: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _adjustWeight(double delta) {
    setState(() {
      _targetWeight = (_targetWeight + delta).clamp(0.0, 1000.0);
      _weightCtrl.text = _targetWeight.toStringAsFixed(1);
    });
  }
}

class _AdjustButton extends StatelessWidget {
  const _AdjustButton({required this.label, required this.onTap});
  final String     label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 52, height: 52,
      decoration: BoxDecoration(
        color:        AppTheme.darkCard,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: AppTheme.darkBorder),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontSize:   13,
            fontWeight: FontWeight.w700,
            color:      AppTheme.darkText,
          ),
        ),
      ),
    ),
  );
}

class _BarVisualization extends StatelessWidget {
  const _BarVisualization({required this.plateMap, required this.useKg});
  final Map<double, int> plateMap;
  final bool useKg;

  static const _plateColors = {
    25.0: Color(0xFFDC2626), // Red
    20.0: Color(0xFF2563EB), // Blue
    15.0: Color(0xFFFFD700), // Yellow
    10.0: Color(0xFF16A34A), // Green
    5.0:  Color(0xFFFFFFFF), // White
    2.5:  Color(0xFF000000), // Black
    1.25: Color(0xFF9CA3AF), // Chrome
    0.5:  Color(0xFF6B7280), // Dark chrome
    0.25: Color(0xFF4B5563), // Gunmetal
    // LB plates
    45.0: Color(0xFFDC2626),
    35.0: Color(0xFF2563EB),
    10.0: Color(0xFF16A34A),
  };

  @override
  Widget build(BuildContext context) {
    // Build plate list for visualization
    final plateList = <double>[];
    plateMap.forEach((weight, count) {
      for (var i = 0; i < count; i++) {
        plateList.add(weight);
      }
    });

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Left plates (reversed — largest outside)
        ...plateList.reversed.map((p) => _PlateVisual(weight: p, colors: _plateColors)),
        // Bar
        Container(
          width: 60, height: 14,
          decoration: BoxDecoration(
            color:        const Color(0xFF9CA3AF),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        // Right plates
        ...plateList.map((p) => _PlateVisual(weight: p, colors: _plateColors)),
      ],
    );
  }
}

class _PlateVisual extends StatelessWidget {
  const _PlateVisual({required this.weight, required this.colors});
  final double weight;
  final Map<double, Color> colors;

  @override
  Widget build(BuildContext context) {
    final height = _plateHeight(weight);
    final color  = colors[weight] ?? AppTheme.darkSubtext;
    return Container(
      width:  8,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color:        color,
        borderRadius: BorderRadius.circular(2),
        border:       Border.all(color: Colors.black26, width: 0.5),
      ),
    );
  }

  double _plateHeight(double weight) {
    if (weight >= 20) return 60;
    if (weight >= 15) return 52;
    if (weight >= 10) return 44;
    if (weight >= 5)  return 36;
    if (weight >= 2.5)return 28;
    return 20;
  }
}

class _PlateRow extends StatelessWidget {
  const _PlateRow({required this.weight, required this.count, required this.useKg});
  final double weight;
  final int    count;
  final bool   useKg;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color:  _weightColor(weight),
            shape:  BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${weight.toStringAsFixed(weight % 1 == 0 ? 0 : 2)}${useKg ? "kg" : "lbs"}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.darkText),
        ),
        const Spacer(),
        Text(
          '×$count',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
        ),
      ],
    ),
  );

  Color _weightColor(double w) {
    if (w >= 20) return const Color(0xFFDC2626);
    if (w >= 15) return const Color(0xFF2563EB);
    if (w >= 10) return const Color(0xFF16A34A);
    if (w >= 5)  return const Color(0xFFFFFFFF);
    return const Color(0xFF9CA3AF);
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.isTotal = false});
  final String label;
  final String value;
  final bool   isTotal;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize:   isTotal ? 15 : 13,
          fontWeight: isTotal ? FontWeight.w700 : FontWeight.w400,
          color:      isTotal ? AppTheme.darkText : AppTheme.darkSubtext,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize:   isTotal ? 17 : 13,
          fontWeight: FontWeight.w700,
          color:      isTotal ? AppTheme.primaryBlue : AppTheme.darkText,
        ),
      ),
    ],
  );
}
