import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../themes/app_theme.dart';

/// Animated rest timer widget shown during active workout.
/// Displays countdown, progress ring, skip and +30s buttons.
class RestTimerWidget extends StatelessWidget {
  const RestTimerWidget({
    super.key,
    required this.secondsRemaining,
    required this.onSkip,
    required this.onAdd30,
    this.totalSeconds,
  });

  final int  secondsRemaining;
  final int? totalSeconds;
  final VoidCallback onSkip;
  final VoidCallback onAdd30;

  @override
  Widget build(BuildContext context) {
    final total    = totalSeconds ?? 90;
    final progress = (secondsRemaining / total).clamp(0.0, 1.0);
    final isLow    = secondsRemaining <= 10;

    return Container(
      margin:  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        isLow
            ? AppTheme.accentRed.withOpacity(0.08)
            : AppTheme.primaryBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(
          color: isLow
              ? AppTheme.accentRed.withOpacity(0.3)
              : AppTheme.primaryBlue.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          // ── Progress ring ─────────────────────────────────
          SizedBox(
            width: 56, height: 56,
            child: Stack(
              children: [
                // Background ring
                CircularProgressIndicator(
                  value:            1.0,
                  strokeWidth:      4,
                  backgroundColor:  AppTheme.darkBorder,
                  valueColor:       const AlwaysStoppedAnimation(AppTheme.darkBorder),
                ),
                // Progress ring
                CircularProgressIndicator(
                  value:      progress,
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation(
                    isLow ? AppTheme.accentRed : AppTheme.primaryBlue,
                  ),
                ).animate(
                  key: ValueKey(secondsRemaining),
                  effects: isLow && secondsRemaining <= 3
                      ? [const ShakeEffect(hz: 3, offset: Offset(2, 0), duration: Duration(milliseconds: 500))]
                      : [],
                ),
                // Time text
                Center(
                  child: Text(
                    _formatTime(secondsRemaining),
                    style: TextStyle(
                      fontSize:   14,
                      fontWeight: FontWeight.w800,
                      color:      isLow ? AppTheme.accentRed : AppTheme.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // ── Label ────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize:       MainAxisSize.min,
              children: [
                Text(
                  isLow ? 'Get ready!' : 'Resting',
                  style: TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w700,
                    color:      isLow ? AppTheme.accentRed : AppTheme.darkText,
                  ),
                ),
                Text(
                  isLow
                      ? 'Next set starting soon'
                      : 'Next set in ${_formatTime(secondsRemaining)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.darkSubtext),
                ),
              ],
            ),
          ),

          // ── +30s button ───────────────────────────────────
          _TimerButton(
            label:   '+30s',
            onTap:   onAdd30,
            color:   AppTheme.darkSubtext,
            compact: true,
          ),
          const SizedBox(width: 8),

          // ── Skip button ───────────────────────────────────
          _TimerButton(
            label:   'Skip',
            onTap:   onSkip,
            color:   isLow ? AppTheme.accentRed : AppTheme.primaryBlue,
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0
        ? '${m}:${s.toString().padLeft(2, '0')}'
        : '${s}s';
  }
}

class _TimerButton extends StatelessWidget {
  const _TimerButton({
    required this.label,
    required this.onTap,
    required this.color,
    this.compact = false,
  });

  final String     label;
  final VoidCallback onTap;
  final Color      color;
  final bool       compact;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 14,
        vertical:   8,
      ),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize:   13,
          fontWeight: FontWeight.w700,
          color:      color,
        ),
      ),
    ),
  );
}
