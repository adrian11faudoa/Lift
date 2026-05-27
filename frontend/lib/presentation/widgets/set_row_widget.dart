import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../themes/app_theme.dart';

/// The most-used widget in the app — a single set row for logging.
/// Optimized for one-handed use with large tap targets.
class SetRowWidget extends StatefulWidget {
  const SetRowWidget({
    super.key,
    required this.set,
    required this.setIndex,
    this.previousBestWeight,
    required this.onLog,
    required this.onRemove,
  });

  final WorkoutSet set;
  final int setIndex;
  final double? previousBestWeight;
  final void Function(double? weight, int? reps, double? rpe) onLog;
  final VoidCallback onRemove;

  @override
  State<SetRowWidget> createState() => _SetRowWidgetState();
}

class _SetRowWidgetState extends State<SetRowWidget> {
  late TextEditingController _weightController;
  late TextEditingController _repsController;
  late TextEditingController _rpeController;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(
      text: widget.set.loggedWeight?.toString() ??
            widget.set.targetWeight?.toString() ?? '',
    );
    _repsController = TextEditingController(
      text: widget.set.loggedReps?.toString() ??
            widget.set.targetReps?.toString() ?? '',
    );
    _rpeController = TextEditingController(
      text: widget.set.loggedRpe?.toStringAsFixed(1) ?? '',
    );
    _isCompleted = widget.set.completed ?? false;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _rpeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: _showSetOptions,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _isCompleted
              ? AppTheme.accentGreen.withOpacity(0.08)
              : AppTheme.darkCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isCompleted
                ? AppTheme.accentGreen.withOpacity(0.3)
                : AppTheme.darkBorder,
          ),
        ),
        child: Row(
          children: [
            // ── Set Type Badge ─────────────────────────────
            _SetTypeBadge(
              type:      widget.set.type,
              setNumber: widget.set.setNumber,
            ),
            const SizedBox(width: 8),

            // ── Previous ───────────────────────────────────
            Expanded(
              flex: 2,
              child: _PreviousHint(
                set:                widget.set,
                previousBestWeight: widget.previousBestWeight,
              ),
            ),

            // ── Weight Input ───────────────────────────────
            Expanded(
              flex: 2,
              child: _NumberInput(
                controller:  _weightController,
                hint:        widget.set.targetWeight?.toString() ?? '—',
                decimal:     true,
                onChanged:   (_) {},
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                enabled:     !_isCompleted,
              ),
            ),

            // ── Reps Input ─────────────────────────────────
            Expanded(
              flex: 2,
              child: _NumberInput(
                controller:  _repsController,
                hint:        widget.set.targetReps?.toString() ?? '—',
                decimal:     false,
                onChanged:   (_) {},
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                enabled:     !_isCompleted,
              ),
            ),

            // ── RPE Input (compact) ────────────────────────
            Expanded(
              flex: 1,
              child: _NumberInput(
                controller:  _rpeController,
                hint:        '—',
                decimal:     true,
                maxLength:   3,
                onChanged:   (_) {},
                onSubmitted: (_) => _complete(),
                enabled:     !_isCompleted,
                textSize:    13,
              ),
            ),

            // ── Complete Checkbox ──────────────────────────
            GestureDetector(
              onTap: _isCompleted ? _uncomplete : _complete,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width:  36,
                height: 36,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: _isCompleted
                      ? AppTheme.accentGreen
                      : AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isCompleted
                        ? AppTheme.accentGreen
                        : AppTheme.darkBorder,
                    width: 2,
                  ),
                ),
                child: _isCompleted
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                        .animate()
                        .scale(duration: 150.ms, curve: Curves.elasticOut)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _complete() {
    // Haptic feedback
    HapticFeedback.mediumImpact();

    final weight = double.tryParse(_weightController.text);
    final reps   = int.tryParse(_repsController.text);
    final rpe    = double.tryParse(_rpeController.text);

    setState(() => _isCompleted = true);
    widget.onLog(weight, reps, rpe);
  }

  void _uncomplete() {
    setState(() => _isCompleted = false);
    widget.onLog(
      double.tryParse(_weightController.text),
      int.tryParse(_repsController.text),
      double.tryParse(_rpeController.text),
    );
  }

  void _showSetOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _SetOptionsSheet(
        set:      widget.set,
        onRemove: widget.onRemove,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SET TYPE BADGE
// ─────────────────────────────────────────────────────────────
class _SetTypeBadge extends StatelessWidget {
  const _SetTypeBadge({required this.type, required this.setNumber});
  final SetType type;
  final int setNumber;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      SetType.warmup  => ('W', AppTheme.primaryOrange),
      SetType.dropSet => ('D', AppTheme.accentPurple),
      SetType.amrap   => ('A', AppTheme.accentGreen),
      SetType.myoRep  => ('M', AppTheme.primaryBlue),
      _               => ('$setNumber', AppTheme.darkSubtext),
    };
    return Container(
      width:  28,
      height: 28,
      decoration: BoxDecoration(
        color:        color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: color.withOpacity(0.3)),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize:   12,
            fontWeight: FontWeight.w700,
            color:      color,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PREVIOUS HINT
// ─────────────────────────────────────────────────────────────
class _PreviousHint extends StatelessWidget {
  const _PreviousHint({required this.set, this.previousBestWeight});
  final WorkoutSet set;
  final double? previousBestWeight;

  @override
  Widget build(BuildContext context) {
    // Show last session's logged values
    final prevWeight = set.targetWeight ?? previousBestWeight;
    final prevReps   = set.targetReps;
    if (prevWeight == null && prevReps == null) {
      return const Center(
        child: Text('—', style: TextStyle(color: AppTheme.darkSubtext, fontSize: 13)),
      );
    }
    return Center(
      child: Text(
        prevReps != null
            ? '${prevWeight?.toStringAsFixed(1) ?? '—'} × $prevReps'
            : '${prevWeight?.toStringAsFixed(1) ?? '—'} kg',
        style: const TextStyle(
          fontSize: 12,
          color: AppTheme.darkSubtext,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NUMBER INPUT
// ─────────────────────────────────────────────────────────────
class _NumberInput extends StatelessWidget {
  const _NumberInput({
    required this.controller,
    required this.hint,
    required this.decimal,
    required this.onChanged,
    required this.onSubmitted,
    this.enabled = true,
    this.maxLength,
    this.textSize = 15,
  });

  final TextEditingController controller;
  final String hint;
  final bool decimal;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final bool enabled;
  final int? maxLength;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color:        enabled ? AppTheme.darkBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled ? AppTheme.darkBorder : Colors.transparent,
        ),
      ),
      child: TextField(
        controller:   controller,
        enabled:      enabled,
        textAlign:    TextAlign.center,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
          ),
          if (maxLength != null) LengthLimitingTextInputFormatter(maxLength!),
        ],
        style: TextStyle(
          fontSize:   textSize,
          fontWeight: FontWeight.w600,
          color:      enabled ? AppTheme.darkText : AppTheme.darkSubtext,
        ),
        decoration: InputDecoration(
          hintText:        hint,
          hintStyle:       const TextStyle(color: AppTheme.darkSubtext, fontSize: 13),
          border:          InputBorder.none,
          enabledBorder:   InputBorder.none,
          focusedBorder:   InputBorder.none,
          contentPadding:  const EdgeInsets.symmetric(horizontal: 4),
        ),
        onChanged:   onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SET OPTIONS SHEET
// ─────────────────────────────────────────────────────────────
class _SetOptionsSheet extends StatelessWidget {
  const _SetOptionsSheet({required this.set, required this.onRemove});
  final WorkoutSet set;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final options = [
      ('Change to Warm-up', Icons.whatshot_outlined, SetType.warmup),
      ('Change to Drop Set', Icons.arrow_downward, SetType.dropSet),
      ('Change to AMRAP', Icons.all_inclusive, SetType.amrap),
      ('Change to Myo-rep', Icons.fitness_center, SetType.myoRep),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: AppTheme.darkBorder,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        ...options.map((o) => ListTile(
          leading: Icon(o.$2, color: AppTheme.darkSubtext),
          title: Text(o.$1),
          onTap: () => Navigator.pop(context),
        )),
        const Divider(color: AppTheme.darkBorder),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: AppTheme.accentRed),
          title: const Text('Remove Set', style: TextStyle(color: AppTheme.accentRed)),
          onTap: () {
            Navigator.pop(context);
            onRemove();
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
