import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/entities.dart';
import '../../core/storage/database.dart';
import '../../core/network/api_client.dart';
import '../../services/sync_service.dart';

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepository(
    db:     AppDatabase.instance,
    client: ref.watch(apiClientProvider),
    sync:   ref.read(syncServiceProvider.notifier),
  );
});

// ─────────────────────────────────────────────────────────────
// WORKOUT REPOSITORY
// Implements offline-first: write to SQLite, queue for sync
// ─────────────────────────────────────────────────────────────
class WorkoutRepository {
  const WorkoutRepository({
    required this.db,
    required this.client,
    required this.sync,
  });

  final AppDatabase     db;
  final ApiClient       client;
  final SyncService     sync;

  static const _uuid   = Uuid();
  static const _userId = 'local_user'; // Replace with auth service

  // ─── SAVE WORKOUT ─────────────────────────────────────────────
  Future<void> saveWorkout(Workout workout) async {
    // 1. Write to local SQLite
    await db.into(db.workouts).insertOnConflictUpdate(
      _workoutToCompanion(workout),
    );

    // Save exercises + sets
    for (final we in workout.exercises) {
      await db.into(db.workoutExercises).insertOnConflictUpdate(
        _workoutExerciseToCompanion(we, workout.id),
      );
      for (final set in we.sets) {
        await db.into(db.workoutSets).insertOnConflictUpdate(
          _workoutSetToCompanion(set),
        );
      }
    }

    // 2. Queue for remote sync (non-blocking)
    await db.addToSyncQueue(
      entityType: 'workout',
      entityId:   workout.id,
      operation:  'update',
      payload:    jsonEncode(_workoutToJson(workout)),
    );

    // 3. Trigger sync (will no-op if offline)
    sync.triggerSync();
  }

  // ─── GET ACTIVE WORKOUT ───────────────────────────────────────
  Future<Workout?> getActiveWorkout(String userId) async {
    final row = await db.getActiveWorkout(userId);
    if (row == null) return null;
    return _rowToWorkout(row);
  }

  // ─── GET WORKOUTS IN DATE RANGE ───────────────────────────────
  Future<List<Workout>> getWorkoutsInRange(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await db.getWorkoutsForDateRange(start, end, _userId);
    return Future.wait(rows.map(_rowToWorkout));
  }

  // ─── DELETE WORKOUT ───────────────────────────────────────────
  Future<void> deleteWorkout(String id) async {
    await (db.update(db.workouts)
      ..where((w) => w.id.equals(id)))
      .write(const WorkoutsCompanion(isDeleted: Value(true)));

    await db.addToSyncQueue(
      entityType: 'workout',
      entityId:   id,
      operation:  'delete',
      payload:    '{}',
    );
  }

  // ─── EXERCISE HISTORY ─────────────────────────────────────────
  Future<void> updateExerciseHistory(Workout workout) async {
    if (workout.status != WorkoutStatus.completed) return;

    for (final we in workout.exercises) {
      // Calculate stats for this exercise in this session
      final completedSets = we.sets.where((s) => s.completed == true).toList();
      if (completedSets.isEmpty) continue;

      final maxWeight   = completedSets
          .map((s) => s.loggedWeight ?? 0.0)
          .reduce((a, b) => a > b ? a : b);
      final maxReps     = completedSets
          .map((s) => s.loggedReps ?? 0)
          .reduce((a, b) => a > b ? a : b);
      final est1RM      = completedSets
          .where((s) => s.estimated1RM != null)
          .map((s) => s.estimated1RM!)
          .fold(0.0, (best, e) => e > best ? e : best);
      final totalVolume = we.totalVolume;

      // Insert/update exercise history
      await db.into(db.exerciseHistory).insertOnConflictUpdate(
        ExerciseHistoryCompanion(
          id:           Value(_uuid.v4()),
          userId:       const Value(_userId),
          exerciseId:   Value(we.exercise.id),
          workoutId:    Value(workout.id),
          date:         Value(workout.date),
          maxWeight:    Value(maxWeight > 0 ? maxWeight : null),
          maxReps:      Value(maxReps > 0 ? maxReps : null),
          estimated1Rm: Value(est1RM > 0 ? est1RM : null),
          totalVolume:  Value(totalVolume),
          totalSets:    Value(completedSets.length),
        ),
      );

      // Check and save PRs
      await _checkAndSavePR(we, workout);
    }
  }

  Future<void> _checkAndSavePR(WorkoutExercise we, Workout workout) async {
    final best1RM = we.sets
        .where((s) => s.estimated1RM != null)
        .map((s) => s.estimated1RM!)
        .fold(0.0, (best, e) => e > best ? e : best);

    if (best1RM <= 0) return;

    final existing = await db.getExercisePR(we.exercise.id, _userId);
    if (existing == null || best1RM > existing.estimated1Rm) {
      final bestSet = we.sets
          .where((s) => s.estimated1RM != null)
          .reduce((a, b) => (a.estimated1RM ?? 0) > (b.estimated1RM ?? 0) ? a : b);

      await db.into(db.personalRecords).insertOnConflictUpdate(
        PersonalRecordsCompanion(
          id:           Value(_uuid.v4()),
          userId:       const Value(_userId),
          exerciseId:   Value(we.exercise.id),
          exerciseName: Value(we.exercise.name),
          weight:       Value(bestSet.loggedWeight ?? 0),
          reps:         Value(bestSet.loggedReps ?? 0),
          estimated1Rm: Value(best1RM),
          achievedAt:   Value(DateTime.now()),
          workoutId:    Value(workout.id),
        ),
      );

      // Show PR notification
      await NotificationService.instance.showNewPR(
        exerciseName:  we.exercise.name,
        weight:        bestSet.loggedWeight ?? 0,
        reps:          bestSet.loggedReps ?? 0,
        estimated1RM:  best1RM,
      );
    }
  }

  // ─── PERSONAL RECORDS ─────────────────────────────────────────
  Future<PersonalRecord?> getExercisePR(String exerciseId, String userId) async {
    final row = await db.getExercisePR(exerciseId, userId);
    if (row == null) return null;
    return PersonalRecord(
      id:           row.id,
      userId:       row.userId,
      exerciseId:   row.exerciseId,
      exerciseName: row.exerciseName,
      weight:       row.weight,
      reps:         row.reps,
      estimated1RM: row.estimated1Rm,
      achievedAt:   row.achievedAt,
      workoutId:    row.workoutId,
    );
  }

  Future<void> savePR(PersonalRecord pr) async {
    await db.into(db.personalRecords).insertOnConflictUpdate(
      PersonalRecordsCompanion(
        id:           Value(pr.id),
        userId:       Value(pr.userId),
        exerciseId:   Value(pr.exerciseId),
        exerciseName: Value(pr.exerciseName),
        weight:       Value(pr.weight),
        reps:         Value(pr.reps),
        estimated1Rm: Value(pr.estimated1RM),
        achievedAt:   Value(pr.achievedAt),
        workoutId:    Value(pr.workoutId),
      ),
    );
  }

  // ─── MAPPERS ──────────────────────────────────────────────────
  WorkoutsCompanion _workoutToCompanion(Workout w) => WorkoutsCompanion(
    id:                   Value(w.id),
    userId:               Value(w.userId),
    name:                 Value(w.name),
    status:               Value(w.status.name),
    date:                 Value(w.date),
    programId:            Value(w.programId),
    programDay:           Value(w.programDay),
    durationSeconds:      Value(w.durationSeconds),
    notes:                Value(w.notes),
    bodyweight:           Value(w.bodyweight),
    perceivedDifficulty:  Value(w.perceivedDifficulty),
    startedAt:            Value(w.startedAt),
    completedAt:          Value(w.completedAt),
    isSynced:             const Value(false),
    isDeleted:            const Value(false),
  );

  WorkoutExercisesCompanion _workoutExerciseToCompanion(
    WorkoutExercise we, String workoutId,
  ) => WorkoutExercisesCompanion(
    id:             Value(we.id),
    workoutId:      Value(workoutId),
    exerciseId:     Value(we.exercise.id),
    orderIndex:     Value(we.order),
    restSeconds:    Value(we.restSeconds),
    notes:          Value(we.notes),
    supersetGroupId: Value(we.supersetGroupId),
  );

  WorkoutSetsCompanion _workoutSetToCompanion(WorkoutSet s) => WorkoutSetsCompanion(
    id:                 Value(s.id),
    workoutExerciseId:  Value(s.workoutExerciseId),
    setNumber:          Value(s.setNumber),
    setType:            Value(s.type.name),
    targetWeight:       Value(s.targetWeight),
    targetReps:         Value(s.targetReps),
    targetRpe:          Value(s.targetRpe),
    targetRir:          Value(s.targetRir),
    tempo:              Value(s.tempo),
    targetDuration:     Value(s.targetDuration),
    loggedWeight:       Value(s.loggedWeight),
    loggedReps:         Value(s.loggedReps),
    loggedRpe:          Value(s.loggedRpe),
    completed:          Value(s.completed),
    restSeconds:        Value(s.restSeconds),
    completedAt:        Value(s.completedAt),
    notes:              Value(s.notes),
  );

  Future<Workout> _rowToWorkout(Workout row) async {
    // In a full implementation this would join exercises and sets
    // Using the Drift join queries defined in database.dart
    return row;
  }

  Map<String, dynamic> _workoutToJson(Workout w) => {
    'id':                   w.id,
    'name':                 w.name,
    'status':               w.status.name,
    'date':                 w.date.toIso8601String(),
    'programId':            w.programId,
    'programDay':           w.programDay,
    'durationSeconds':      w.durationSeconds,
    'notes':                w.notes,
    'bodyweight':           w.bodyweight,
    'perceivedDifficulty':  w.perceivedDifficulty,
    'startedAt':            w.startedAt?.toIso8601String(),
    'completedAt':          w.completedAt?.toIso8601String(),
    'exercises':            w.exercises.map((we) => {
      'id':             we.id,
      'exerciseId':     we.exercise.id,
      'orderIndex':     we.order,
      'restSeconds':    we.restSeconds,
      'notes':          we.notes,
      'supersetGroupId': we.supersetGroupId,
      'sets':           we.sets.map((s) => {
        'id':                s.id,
        'setNumber':         s.setNumber,
        'setType':           s.type.name,
        'targetWeight':      s.targetWeight,
        'targetReps':        s.targetReps,
        'loggedWeight':      s.loggedWeight,
        'loggedReps':        s.loggedReps,
        'loggedRpe':         s.loggedRpe,
        'completed':         s.completed,
        'restSeconds':       s.restSeconds,
        'notes':             s.notes,
      }).toList(),
    }).toList(),
  };
}
