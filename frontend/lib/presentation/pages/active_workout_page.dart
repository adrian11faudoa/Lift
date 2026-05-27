import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../domain/entities/entities.dart';
import '../blocs/active_workout_notifier.dart';
import '../themes/app_theme.dart';
import '../widgets/set_row_widget.dart';
import '../widgets/rest_timer_widget.dart';
import '../widgets/pr_badge_widget.dart';

class ActiveWorkoutPage extends ConsumerStatefulWidget {
  const ActiveWorkoutPage({super.key});

  @override
  ConsumerState<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends ConsumerState<ActiveWorkoutPage>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final workout = ref.read(activeWorkoutProvider).workout;
    _tabController = TabController(
      length: workout?.exercises.length ?? 1,
      vsync:  this,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activeWorkoutProvider);

    if (!state.isActive || state.workout == null) {
      return const _NoActiveWorkoutScreen();
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: AppTheme.darkBg,
        body: Column(
          children: [
            // ── Header ──────────────────────────────────────────
            _WorkoutHeader(
              workout:        state.workout!,
              elapsedSeconds: state.elapsedSeconds,
            ),

            // ── Rest Timer (shown when resting) ─────────────────
            if (state.isResting)
              RestTimerWidget(
                secondsRemaining: state.restSecondsRemaining,
                onSkip:  () => ref.read(activeWorkoutProvider.notifier).skipRest(),
                onAdd30: () => ref.read(activeWorkoutProvider.notifier).addRestTime(30),
              ).animate().fadeIn(duration: 200.ms),

            // ── Exercise Tabs ────────────────────────────────────
            _ExerciseTabs(
              exercises:     state.workout!.exercises,
              tabController: _tabController,
            ),

            // ── Exercise Content ─────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: state.workout!.exercises.map((exercise) {
                  return _ExerciseSetList(
                    workoutExercise: exercise,
                    prCache:         state.prCache,
                  );
                }).toList(),
              ),
            ),

            // ── Bottom Actions ───────────────────────────────────
            _BottomActions(workout: state.workout!),
          ],
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('Leave Workout?'),
        content: const Text('Your progress is saved. You can resume later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ─────────────────────────────────────────────────────────────
// WORKOUT HEADER
// ─────────────────────────────────────────────────────────────
class _WorkoutHeader extends StatelessWidget {
  const _WorkoutHeader({required this.workout, required this.elapsedSeconds});

  final Workout workout;
  final int elapsedSeconds;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: AppTheme.darkBg,
        child: Row(
          children: [
            // Back button
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => context.pop(),
              color: AppTheme.darkText,
            ),
            const SizedBox(width: 8),
            // Workout name & timer
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workout.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.darkText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  _ElapsedTimer(seconds: elapsedSeconds),
                ],
              ),
            ),
            // Volume indicator
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${workout.totalVolume.toStringAsFixed(0)} kg',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const Text(
                  'Volume',
                  style: TextStyle(fontSize: 11, color: AppTheme.darkSubtext),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Finish button
            Consumer(builder: (context, ref, _) {
              return FilledButton(
                onPressed: () => _showFinishDialog(context, ref),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accentGreen,
                  minimumSize: const Size(72, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Finish'),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showFinishDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FinishWorkoutSheet(workout: workout),
    );
  }
}

class _ElapsedTimer extends StatelessWidget {
  const _ElapsedTimer({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final text = h > 0
        ? '${h}h ${m.toString().padLeft(2,'0')}m'
        : '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        color: AppTheme.darkSubtext,
        fontVariations: [FontVariation('wght', 500)],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EXERCISE TABS
// ─────────────────────────────────────────────────────────────
class _ExerciseTabs extends StatelessWidget {
  const _ExerciseTabs({required this.exercises, required this.tabController});

  final List<WorkoutExercise> exercises;
  final TabController tabController;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: AppTheme.darkSurface,
      child: TabBar(
        controller:     tabController,
        isScrollable:   true,
        tabAlignment:   TabAlignment.start,
        indicatorColor: AppTheme.primaryBlue,
        indicatorWeight: 3,
        labelColor:     AppTheme.primaryBlue,
        unselectedLabelColor: AppTheme.darkSubtext,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
        tabs: exercises
            .map((e) => Tab(text: e.exercise.name))
            .toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EXERCISE SET LIST
// ─────────────────────────────────────────────────────────────
class _ExerciseSetList extends ConsumerWidget {
  const _ExerciseSetList({
    required this.workoutExercise,
    required this.prCache,
  });

  final WorkoutExercise workoutExercise;
  final Map<String, PersonalRecord?> prCache;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(activeWorkoutProvider.notifier);
    final pr = prCache[workoutExercise.exercise.id];

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        // Exercise info header
        _ExerciseInfoBar(
          exercise: workoutExercise.exercise,
          pr:       pr,
        ),

        // Previous best hint
        if (pr != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Best: ${pr.weight.toStringAsFixed(1)}kg × ${pr.reps} reps (${pr.estimated1RM.toStringAsFixed(1)}kg e1RM)',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.accentGreen,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],

        // Column headers
        const _SetColumnHeaders(),

        // Set rows
        ...workoutExercise.sets.asMap().entries.map((entry) {
          final index = entry.key;
          final set   = entry.value;
          return SetRowWidget(
            set:              set,
            setIndex:         index,
            previousBestWeight: pr?.weight,
            onLog: (weight, reps, rpe) => notifier.logSet(
              workoutExerciseId: workoutExercise.id,
              setIndex:          index,
              weight:            weight,
              reps:              reps,
              rpe:               rpe,
            ),
            onRemove: () => notifier.removeSet(workoutExercise.id, index),
          ).animate(key: ValueKey(set.id))
            .fadeIn(duration: 200.ms, delay: (index * 40).ms);
        }),

        // Add set button
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => notifier.addSet(workoutExercise.id),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Set'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              foregroundColor: AppTheme.darkSubtext,
              side: const BorderSide(color: AppTheme.darkBorder),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExerciseInfoBar extends StatelessWidget {
  const _ExerciseInfoBar({required this.exercise, this.pr});
  final Exercise exercise;
  final PersonalRecord? pr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          // Muscle chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              exercise.primaryMuscle.name.capitalize(),
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Equipment chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Text(
              exercise.equipment.name.capitalize(),
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.darkSubtext,
              ),
            ),
          ),
          const Spacer(),
          // Notes icon
          IconButton(
            icon: const Icon(Icons.notes_rounded, size: 20),
            color: AppTheme.darkSubtext,
            onPressed: () {},
          ),
          // Replace exercise
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded, size: 20),
            color: AppTheme.darkSubtext,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _SetColumnHeaders extends StatelessWidget {
  const _SetColumnHeaders();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 32),
          const SizedBox(width: 8),
          _headerText('SET', flex: 1),
          _headerText('PREVIOUS', flex: 2),
          _headerText('kg', flex: 2),
          _headerText('REPS', flex: 2),
          _headerText('RPE', flex: 1),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _headerText(String text, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        color: AppTheme.darkSubtext,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      textAlign: TextAlign.center,
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// BOTTOM ACTIONS
// ─────────────────────────────────────────────────────────────
class _BottomActions extends ConsumerWidget {
  const _BottomActions({required this.workout});
  final Workout workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        border: Border(top: BorderSide(color: AppTheme.darkBorder)),
      ),
      child: Row(
        children: [
          // Add exercise
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showExercisePicker(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Exercise'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: AppTheme.primaryBlue,
                side: const BorderSide(color: AppTheme.primaryBlue),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Plate calculator
          IconButton.outlined(
            onPressed: () => _showPlateCalculator(context),
            icon: const Icon(Icons.calculate_outlined),
            style: IconButton.styleFrom(
              foregroundColor: AppTheme.darkSubtext,
              side: const BorderSide(color: AppTheme.darkBorder),
            ),
          ),
          const SizedBox(width: 8),
          // Discard
          IconButton.outlined(
            onPressed: () => _confirmDiscard(context, ref),
            icon: const Icon(Icons.delete_outline),
            style: IconButton.styleFrom(
              foregroundColor: AppTheme.accentRed,
              side: const BorderSide(color: AppTheme.accentRed.withOpacity(0.3)),
            ),
          ),
        ],
      ),
    );
  }

  void _showExercisePicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ExercisePickerSheet(),
    );
  }

  void _showPlateCalculator(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const PlateCalculatorSheet(),
    );
  }

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('Discard Workout?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.accentRed),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await ref.read(activeWorkoutProvider.notifier).discardWorkout();
      context.go('/');
    }
  }
}

// ─────────────────────────────────────────────────────────────
// FINISH WORKOUT SHEET
// ─────────────────────────────────────────────────────────────
class _FinishWorkoutSheet extends ConsumerStatefulWidget {
  const _FinishWorkoutSheet({required this.workout});
  final Workout workout;

  @override
  ConsumerState<_FinishWorkoutSheet> createState() => _FinishWorkoutSheetState();
}

class _FinishWorkoutSheetState extends ConsumerState<_FinishWorkoutSheet> {
  int _difficulty = 5;
  final _notesController = TextEditingController();
  bool _isFinishing = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.darkBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Finish Workout',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.darkText),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.workout.totalSets} sets · ${widget.workout.totalVolume.toStringAsFixed(0)}kg volume',
            style: const TextStyle(fontSize: 14, color: AppTheme.darkSubtext),
          ),
          const SizedBox(height: 24),

          // Difficulty
          const Text('Perceived Difficulty', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.darkText)),
          const SizedBox(height: 8),
          Row(
            children: List.generate(10, (i) {
              final val = i + 1;
              final selected = _difficulty == val;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _difficulty = val),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected ? _difficultyColor(val) : AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected ? _difficultyColor(val) : AppTheme.darkBorder,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$val',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : AppTheme.darkSubtext,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // Notes
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Workout notes (optional)...',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: 24),

          // Confirm button
          FilledButton(
            onPressed: _isFinishing ? null : _finish,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentGreen),
            child: _isFinishing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save Workout'),
          ),
        ],
      ),
    );
  }

  Color _difficultyColor(int val) {
    if (val <= 3) return AppTheme.accentGreen;
    if (val <= 6) return AppTheme.primaryOrange;
    return AppTheme.accentRed;
  }

  Future<void> _finish() async {
    setState(() => _isFinishing = true);
    final workout = await ref.read(activeWorkoutProvider.notifier).finishWorkout(
      perceivedDifficulty: _difficulty,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );
    if (mounted) {
      context.pop();
      if (workout != null) {
        context.go('/workout-complete', extra: workout);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────
// PLACEHOLDER WIDGETS
// ─────────────────────────────────────────────────────────────
class ExercisePickerSheet extends StatelessWidget {
  const ExercisePickerSheet({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(); // Implemented in exercises page
}

class PlateCalculatorSheet extends StatelessWidget {
  const PlateCalculatorSheet({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(); // See plate_calculator.dart
}

class _NoActiveWorkoutScreen extends StatelessWidget {
  const _NoActiveWorkoutScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fitness_center, size: 64, color: AppTheme.darkSubtext),
          const SizedBox(height: 16),
          const Text('No active workout', style: TextStyle(fontSize: 18, color: AppTheme.darkSubtext)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Start a Workout'),
          ),
        ],
      ),
    ),
  );
}

extension StringExtension on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
