import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/entities.dart';
import '../../data/repositories/workout_repository.dart';
import '../../services/rest_timer_service.dart';
import '../../services/notification_service.dart';

// ─────────────────────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────────────────────
class ActiveWorkoutState {
  final Workout? workout;
  final bool isActive;
  final int elapsedSeconds;
  final String? currentExerciseId;
  final int? currentSetIndex;
  final bool isResting;
  final int restSecondsRemaining;
  final bool isSaving;
  final String? error;
  final Map<String, PersonalRecord?> prCache; // exerciseId → current PR

  const ActiveWorkoutState({
    this.workout,
    this.isActive = false,
    this.elapsedSeconds = 0,
    this.currentExerciseId,
    this.currentSetIndex,
    this.isResting = false,
    this.restSecondsRemaining = 0,
    this.isSaving = false,
    this.error,
    this.prCache = const {},
  });

  bool get isEmpty => workout == null;

  WorkoutExercise? get currentExercise => workout?.exercises
      .where((e) => e.id == currentExerciseId)
      .firstOrNull;

  ActiveWorkoutState copyWith({
    Workout? workout,
    bool? isActive,
    int? elapsedSeconds,
    String? currentExerciseId,
    int? currentSetIndex,
    bool? isResting,
    int? restSecondsRemaining,
    bool? isSaving,
    String? error,
    Map<String, PersonalRecord?>? prCache,
  }) => ActiveWorkoutState(
    workout:               workout               ?? this.workout,
    isActive:              isActive              ?? this.isActive,
    elapsedSeconds:        elapsedSeconds        ?? this.elapsedSeconds,
    currentExerciseId:     currentExerciseId     ?? this.currentExerciseId,
    currentSetIndex:       currentSetIndex       ?? this.currentSetIndex,
    isResting:             isResting             ?? this.isResting,
    restSecondsRemaining:  restSecondsRemaining  ?? this.restSecondsRemaining,
    isSaving:              isSaving              ?? this.isSaving,
    error:                 error,
    prCache:               prCache               ?? this.prCache,
  );
}

// ─────────────────────────────────────────────────────────────
// PROVIDER
// ─────────────────────────────────────────────────────────────
final activeWorkoutProvider =
    StateNotifierProvider<ActiveWorkoutNotifier, ActiveWorkoutState>((ref) {
  return ActiveWorkoutNotifier(
    ref.watch(workoutRepositoryProvider),
    ref.watch(restTimerServiceProvider),
  );
});

// ─────────────────────────────────────────────────────────────
// NOTIFIER
// ─────────────────────────────────────────────────────────────
class ActiveWorkoutNotifier extends StateNotifier<ActiveWorkoutState> {
  final WorkoutRepository _repository;
  final RestTimerService  _restTimer;
  Timer? _elapsedTimer;
  Timer? _restCountdownTimer;
  final _uuid = const Uuid();

  ActiveWorkoutNotifier(this._repository, this._restTimer)
      : super(const ActiveWorkoutState()) {
    _checkForActiveWorkout();
  }

  // ─── START WORKOUT ───────────────────────────────────────────
  Future<void> startWorkout({
    required String name,
    List<Exercise>? exercises,
    String? programId,
    int? programDay,
  }) async {
    final workout = Workout(
      id:         _uuid.v4(),
      userId:     _getCurrentUserId(),
      name:       name,
      status:     WorkoutStatus.inProgress,
      date:       DateTime.now(),
      exercises:  exercises?.map(_exerciseToWorkoutExercise).toList() ?? [],
      programId:  programId,
      programDay: programDay,
      startedAt:  DateTime.now(),
    );

    await _repository.saveWorkout(workout);
    _startElapsedTimer();

    // Keep screen on during workout
    // WakelockPlus.enable();

    state = state.copyWith(
      workout:           workout,
      isActive:          true,
      currentExerciseId: workout.exercises.firstOrNull?.id,
      currentSetIndex:   0,
      elapsedSeconds:    0,
    );

    // Load PRs for all exercises
    _loadPRCache(workout.exercises.map((e) => e.exercise.id).toList());
  }

  // ─── START FROM TEMPLATE ─────────────────────────────────────
  Future<void> startFromProgram({
    required Program program,
    required int dayIndex,
  }) async {
    final day = program.days[dayIndex];
    final exercises = day.exercises
        .map((pe) => _programExerciseToWorkoutExercise(pe))
        .toList();

    await startWorkout(
      name:       '${program.name} – ${day.name}',
      exercises:  exercises.map((we) => we.exercise).toList(),
      programId:  program.id,
      programDay: dayIndex + 1,
    );
  }

  // ─── ADD EXERCISE ────────────────────────────────────────────
  void addExercise(Exercise exercise) {
    if (state.workout == null) return;
    final we = _exerciseToWorkoutExercise(exercise);
    final updated = state.workout!.copyWith(
      exercises: [...state.workout!.exercises, we],
    );
    _updateWorkout(updated);
  }

  void removeExercise(String workoutExerciseId) {
    if (state.workout == null) return;
    final updated = state.workout!.copyWith(
      exercises: state.workout!.exercises
          .where((e) => e.id != workoutExerciseId)
          .toList(),
    );
    _updateWorkout(updated);
  }

  void reorderExercises(int oldIndex, int newIndex) {
    if (state.workout == null) return;
    final exercises = [...state.workout!.exercises];
    final item = exercises.removeAt(oldIndex);
    exercises.insert(newIndex, item);
    _updateWorkout(state.workout!.copyWith(exercises: exercises));
  }

  // ─── LOGGING SETS ────────────────────────────────────────────
  void logSet({
    required String workoutExerciseId,
    required int setIndex,
    double? weight,
    int? reps,
    double? rpe,
    bool completed = true,
  }) {
    if (state.workout == null) return;

    final exercises = state.workout!.exercises.map((we) {
      if (we.id != workoutExerciseId) return we;
      final sets = we.sets.mapIndexed((i, s) {
        if (i != setIndex) return s;
        return s.copyWith(
          loggedWeight: weight,
          loggedReps:   reps,
          loggedRpe:    rpe,
          completed:    completed,
          completedAt:  completed ? DateTime.now() : null,
        );
      }).toList();
      return we.copyWith(sets: sets);
    }).toList();

    final updated = state.workout!.copyWith(exercises: exercises);
    _updateWorkout(updated);

    // Check for new PR
    if (completed && weight != null && reps != null) {
      _checkForPR(workoutExerciseId, weight, reps);
    }

    // Start rest timer
    if (completed) {
      final exercise = state.workout!.exercises
          .firstWhere((e) => e.id == workoutExerciseId);
      _startRestTimer(exercise.restSeconds ?? 90);
    }
  }

  void updateSetTarget({
    required String workoutExerciseId,
    required int setIndex,
    double? targetWeight,
    int? targetReps,
    double? targetRpe,
  }) {
    if (state.workout == null) return;
    final exercises = state.workout!.exercises.map((we) {
      if (we.id != workoutExerciseId) return we;
      final sets = we.sets.mapIndexed((i, s) {
        if (i != setIndex) return s;
        return s.copyWith(
          targetWeight: targetWeight ?? s.targetWeight,
          targetReps:   targetReps   ?? s.targetReps,
          targetRpe:    targetRpe    ?? s.targetRpe,
        );
      }).toList();
      return we.copyWith(sets: sets);
    }).toList();
    _updateWorkout(state.workout!.copyWith(exercises: exercises));
  }

  void addSet(String workoutExerciseId) {
    if (state.workout == null) return;
    final exercises = state.workout!.exercises.map((we) {
      if (we.id != workoutExerciseId) return we;
      final lastSet = we.sets.lastOrNull;
      final newSet = WorkoutSet(
        id:                 _uuid.v4(),
        workoutExerciseId:  workoutExerciseId,
        setNumber:          we.sets.length + 1,
        type:               SetType.normal,
        targetWeight:       lastSet?.loggedWeight ?? lastSet?.targetWeight,
        targetReps:         lastSet?.targetReps,
      );
      return we.copyWith(sets: [...we.sets, newSet]);
    }).toList();
    _updateWorkout(state.workout!.copyWith(exercises: exercises));
  }

  void removeSet(String workoutExerciseId, int setIndex) {
    if (state.workout == null) return;
    final exercises = state.workout!.exercises.map((we) {
      if (we.id != workoutExerciseId) return we;
      final sets = [...we.sets]..removeAt(setIndex);
      // Re-number sets
      final renumbered = sets.mapIndexed(
        (i, s) => s.copyWith(setNumber: i + 1),
      ).toList();
      return we.copyWith(sets: renumbered);
    }).toList();
    _updateWorkout(state.workout!.copyWith(exercises: exercises));
  }

  // ─── REST TIMER ──────────────────────────────────────────────
  void _startRestTimer(int seconds) {
    _restCountdownTimer?.cancel();
    state = state.copyWith(isResting: true, restSecondsRemaining: seconds);
    _restCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final remaining = state.restSecondsRemaining - 1;
      if (remaining <= 0) {
        t.cancel();
        state = state.copyWith(isResting: false, restSecondsRemaining: 0);
        NotificationService.instance.showRestComplete();
      } else {
        state = state.copyWith(restSecondsRemaining: remaining);
      }
    });
  }

  void skipRest() {
    _restCountdownTimer?.cancel();
    state = state.copyWith(isResting: false, restSecondsRemaining: 0);
  }

  void addRestTime(int seconds) {
    state = state.copyWith(
      restSecondsRemaining: state.restSecondsRemaining + seconds,
    );
  }

  // ─── FINISH WORKOUT ──────────────────────────────────────────
  Future<Workout?> finishWorkout({
    int? perceivedDifficulty,
    String? notes,
    double? bodyweight,
  }) async {
    if (state.workout == null) return null;
    _elapsedTimer?.cancel();
    _restCountdownTimer?.cancel();

    final completed = state.workout!.copyWith(
      status:               WorkoutStatus.completed,
      durationSeconds:      state.elapsedSeconds,
      completedAt:          DateTime.now(),
      perceivedDifficulty:  perceivedDifficulty,
      notes:                notes,
      bodyweight:           bodyweight,
    );

    state = state.copyWith(isSaving: true);
    await _repository.saveWorkout(completed);
    await _repository.updateExerciseHistory(completed);
    // WakelockPlus.disable();

    state = const ActiveWorkoutState();
    return completed;
  }

  Future<void> discardWorkout() async {
    if (state.workout == null) return;
    _elapsedTimer?.cancel();
    _restCountdownTimer?.cancel();
    await _repository.deleteWorkout(state.workout!.id);
    // WakelockPlus.disable();
    state = const ActiveWorkoutState();
  }

  // ─── ELAPSED TIMER ───────────────────────────────────────────
  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
    });
  }

  // ─── PR CHECK ────────────────────────────────────────────────
  Future<void> _checkForPR(
    String workoutExerciseId,
    double weight,
    int reps,
  ) async {
    final exercise = state.workout!.exercises
        .firstWhere((e) => e.id == workoutExerciseId);
    final exerciseId = exercise.exercise.id;
    final estimated1RM = weight * (1 + reps / 30.0);
    final currentPR = state.prCache[exerciseId];

    if (currentPR == null || estimated1RM > currentPR.estimated1RM) {
      // NEW PR!
      final pr = PersonalRecord(
        id:            _uuid.v4(),
        userId:        _getCurrentUserId(),
        exerciseId:    exerciseId,
        exerciseName:  exercise.exercise.name,
        weight:        weight,
        reps:          reps,
        estimated1RM:  estimated1RM,
        achievedAt:    DateTime.now(),
        workoutId:     state.workout!.id,
      );
      await _repository.savePR(pr);
      state = state.copyWith(
        prCache: {...state.prCache, exerciseId: pr},
      );
      // Show PR notification in workout screen
    }
  }

  Future<void> _loadPRCache(List<String> exerciseIds) async {
    final cache = <String, PersonalRecord?>{};
    for (final id in exerciseIds) {
      cache[id] = await _repository.getExercisePR(id, _getCurrentUserId());
    }
    state = state.copyWith(prCache: cache);
  }

  // ─── PERSISTENCE ─────────────────────────────────────────────
  void _updateWorkout(Workout workout) {
    state = state.copyWith(workout: workout);
    _repository.saveWorkout(workout); // Save locally (no await - fire & forget)
  }

  Future<void> _checkForActiveWorkout() async {
    final active = await _repository.getActiveWorkout(_getCurrentUserId());
    if (active != null) {
      state = state.copyWith(
        workout:  active,
        isActive: true,
        currentExerciseId: active.exercises.firstOrNull?.id,
      );
      _startElapsedTimer();
    }
  }

  // ─── HELPERS ─────────────────────────────────────────────────
  String _getCurrentUserId() => 'local_user'; // Replace with auth service

  WorkoutExercise _exerciseToWorkoutExercise(Exercise e) => WorkoutExercise(
    id:         _uuid.v4(),
    workoutId:  state.workout?.id ?? '',
    exercise:   e,
    order:      state.workout?.exercises.length ?? 0,
    sets:       List.generate(3, (i) => WorkoutSet(
      id:                _uuid.v4(),
      workoutExerciseId: '',
      setNumber:         i + 1,
      type:              SetType.normal,
    )),
  );

  WorkoutExercise _programExerciseToWorkoutExercise(ProgramExercise pe) {
    final setCount = pe.sets;
    final targetReps = _parseRepsScheme(pe.repsScheme);
    return WorkoutExercise(
      id:         _uuid.v4(),
      workoutId:  '',
      exercise:   pe.exercise,
      order:      0,
      sets:       List.generate(setCount, (i) => WorkoutSet(
        id:                _uuid.v4(),
        workoutExerciseId: '',
        setNumber:         i + 1,
        type:              SetType.normal,
        targetReps:        targetReps,
        targetRpe:         pe.rpeTarget,
      )),
      restSeconds: pe.restSeconds,
      notes:      pe.notes,
    );
  }

  int? _parseRepsScheme(String scheme) {
    // Parse "5", "8-12", "AMRAP" etc.
    if (scheme == 'AMRAP') return null;
    if (scheme.contains('-')) {
      return int.tryParse(scheme.split('-').first);
    }
    return int.tryParse(scheme);
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _restCountdownTimer?.cancel();
    super.dispose();
  }
}

// Helper extension
extension IndexedMap<T> on Iterable<T> {
  Iterable<R> mapIndexed<R>(R Function(int index, T element) f) sync* {
    var i = 0;
    for (final e in this) {
      yield f(i++, e);
    }
  }
}
