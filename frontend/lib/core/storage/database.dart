import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

// ─────────────────────────────────────────────────────────────
// TABLE DEFINITIONS
// ─────────────────────────────────────────────────────────────

class Exercises extends Table {
  TextColumn get id          => text()();
  TextColumn get name        => text()();
  TextColumn get primaryMuscle => text()();
  TextColumn get secondaryMuscles => text()(); // JSON array
  TextColumn get equipment   => text()();
  TextColumn get category    => text()();
  TextColumn get description => text().nullable()();
  TextColumn get videoUrl    => text().nullable()();
  TextColumn get thumbnailUrl=> text().nullable()();
  TextColumn get instructions=> text().nullable()();
  BoolColumn get isCustom    => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite  => boolean().withDefault(const Constant(false))();
  TextColumn get userId      => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  BoolColumn get isSynced    => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Workouts extends Table {
  TextColumn get id          => text()();
  TextColumn get userId      => text()();
  TextColumn get name        => text()();
  TextColumn get status      => text()(); // planned|inProgress|completed|skipped
  DateTimeColumn get date    => dateTime()();
  TextColumn get programId   => text().nullable()();
  IntColumn get programDay   => integer().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
  TextColumn get notes       => text().nullable()();
  RealColumn get bodyweight  => real().nullable()();
  IntColumn get perceivedDifficulty => integer().nullable()();
  DateTimeColumn get startedAt  => dateTime().nullable()();
  DateTimeColumn get completedAt=> dateTime().nullable()();
  DateTimeColumn get createdAt  => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced    => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted   => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class WorkoutExercises extends Table {
  TextColumn get id          => text()();
  TextColumn get workoutId   => text().references(Workouts, #id)();
  TextColumn get exerciseId  => text().references(Exercises, #id)();
  IntColumn get orderIndex   => integer()();
  IntColumn get restSeconds  => integer().nullable()();
  TextColumn get notes       => text().nullable()();
  TextColumn get supersetGroupId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class WorkoutSets extends Table {
  TextColumn get id           => text()();
  TextColumn get workoutExerciseId => text().references(WorkoutExercises, #id)();
  IntColumn get setNumber     => integer()();
  TextColumn get setType      => text()(); // normal|warmup|dropset|amrap
  RealColumn get targetWeight => real().nullable()();
  IntColumn get targetReps    => integer().nullable()();
  RealColumn get targetRpe    => real().nullable()();
  IntColumn get targetRir     => integer().nullable()();
  TextColumn get tempo        => text().nullable()();
  IntColumn get targetDuration=> integer().nullable()();
  RealColumn get loggedWeight => real().nullable()();
  IntColumn get loggedReps    => integer().nullable()();
  RealColumn get loggedRpe    => real().nullable()();
  BoolColumn get completed    => boolean().nullable()();
  IntColumn get restSeconds   => integer().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get notes        => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Programs extends Table {
  TextColumn get id           => text()();
  TextColumn get name         => text()();
  TextColumn get description  => text()();
  TextColumn get type         => text()();
  IntColumn get daysPerWeek   => integer()();
  IntColumn get durationWeeks => integer()();
  TextColumn get authorId     => text()();
  TextColumn get authorName   => text().nullable()();
  TextColumn get progressionScript => text().nullable()();
  BoolColumn get isPublic     => boolean().withDefault(const Constant(false))();
  BoolColumn get isPremium    => boolean().withDefault(const Constant(false))();
  TextColumn get tags         => text().nullable()(); // JSON
  DateTimeColumn get createdAt=> dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt=> dateTime().nullable()();
  BoolColumn get isSynced     => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class ProgramDays extends Table {
  TextColumn get id           => text()();
  TextColumn get programId    => text().references(Programs, #id)();
  IntColumn get dayNumber     => integer()();
  TextColumn get name         => text()();
  BoolColumn get isRestDay    => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class ProgramExercises extends Table {
  TextColumn get id           => text()();
  TextColumn get programDayId => text().references(ProgramDays, #id)();
  TextColumn get exerciseId   => text().references(Exercises, #id)();
  IntColumn get orderIndex    => integer()();
  IntColumn get sets          => integer()();
  TextColumn get repsScheme   => text()();
  TextColumn get weightScheme => text().nullable()();
  TextColumn get progressionScript => text().nullable()();
  TextColumn get progressionType => text().nullable()();
  IntColumn get restSeconds   => integer().nullable()();
  RealColumn get rpeTarget    => real().nullable()();
  IntColumn get rirTarget     => integer().nullable()();
  TextColumn get tempo        => text().nullable()();
  TextColumn get notes        => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class PersonalRecords extends Table {
  TextColumn get id           => text()();
  TextColumn get userId       => text()();
  TextColumn get exerciseId   => text()();
  TextColumn get exerciseName => text()();
  RealColumn get weight       => real()();
  IntColumn get reps          => integer()();
  RealColumn get estimated1RM => real()();
  DateTimeColumn get achievedAt => dateTime()();
  TextColumn get workoutId    => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ExerciseHistory extends Table {
  TextColumn get id           => text()();
  TextColumn get userId       => text()();
  TextColumn get exerciseId   => text()();
  TextColumn get workoutId    => text()();
  DateTimeColumn get date     => dateTime()();
  RealColumn get maxWeight    => real().nullable()();
  IntColumn get maxReps       => integer().nullable()();
  RealColumn get estimated1RM => real().nullable()();
  RealColumn get totalVolume  => real()();
  IntColumn get totalSets     => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQueue extends Table {
  IntColumn get id            => integer().autoIncrement()();
  TextColumn get entityType   => text()(); // workout|program|exercise
  TextColumn get entityId     => text()();
  TextColumn get operation    => text()(); // create|update|delete
  TextColumn get payload      => text()(); // JSON
  DateTimeColumn get queuedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get retryCount    => integer().withDefault(const Constant(0))();
  TextColumn get lastError    => text().nullable()();
}

// ─────────────────────────────────────────────────────────────
// DATABASE CLASS
// ─────────────────────────────────────────────────────────────
@DriftDatabase(tables: [
  Exercises,
  Workouts,
  WorkoutExercises,
  WorkoutSets,
  Programs,
  ProgramDays,
  ProgramExercises,
  PersonalRecords,
  ExerciseHistory,
  SyncQueue,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase._() : super(_openConnection());

  static final AppDatabase instance = AppDatabase._();

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _seedBuiltInExercises();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Add migrations here as schema evolves
    },
  );

  Future<void> initialize() async {
    // Trigger lazy initialization
    await customSelect('SELECT 1').get();
  }

  // ─── EXERCISE QUERIES ────────────────────────────────────────
  Future<List<Exercise>> searchExercises({
    String? query,
    String? muscleGroup,
    String? equipment,
    bool? customOnly,
  }) async {
    var q = select(exercises);
    q.where((e) {
      Expression<bool> where = const Constant(true);
      if (query != null && query.isNotEmpty) {
        where = where & e.name.like('%$query%');
      }
      if (muscleGroup != null) {
        where = where & e.primaryMuscle.equals(muscleGroup);
      }
      if (equipment != null) {
        where = where & e.equipment.equals(equipment);
      }
      if (customOnly == true) {
        where = where & e.isCustom.equals(true);
      }
      return where;
    });
    q.orderBy([(e) => OrderingTerm.asc(e.name)]);
    return q.get();
  }

  // ─── WORKOUT QUERIES ─────────────────────────────────────────
  Future<List<Workout>> getWorkoutsForDateRange(
    DateTime start,
    DateTime end,
    String userId,
  ) {
    return (select(workouts)
      ..where((w) =>
        w.userId.equals(userId) &
        w.date.isBetweenValues(start, end) &
        w.isDeleted.equals(false))
      ..orderBy([(w) => OrderingTerm.desc(w.date)]))
    .get();
  }

  Future<Workout?> getActiveWorkout(String userId) {
    return (select(workouts)
      ..where((w) =>
        w.userId.equals(userId) &
        w.status.equals('inProgress'))
      ..limit(1))
    .getSingleOrNull();
  }

  // ─── ANALYTICS QUERIES ───────────────────────────────────────
  Future<List<ExerciseHistory>> getExerciseHistory(
    String exerciseId,
    String userId, {
    int limit = 30,
  }) {
    return (select(exerciseHistory)
      ..where((h) =>
        h.exerciseId.equals(exerciseId) &
        h.userId.equals(userId))
      ..orderBy([(h) => OrderingTerm.desc(h.date)])
      ..limit(limit))
    .get();
  }

  /// Weekly volume by muscle group
  Future<Map<String, double>> getWeeklyVolumeByMuscle(
    String userId,
    DateTime weekStart,
  ) async {
    final weekEnd = weekStart.add(const Duration(days: 7));
    // Complex join query for muscle group volume
    final results = await customSelect(
      '''
      SELECT e.primary_muscle, SUM(ws.logged_weight * ws.logged_reps) as volume
      FROM workout_sets ws
      JOIN workout_exercises we ON ws.workout_exercise_id = we.id
      JOIN workouts w ON we.workout_id = w.id
      JOIN exercises e ON we.exercise_id = e.id
      WHERE w.user_id = ? AND w.date >= ? AND w.date < ? AND ws.completed = 1
      GROUP BY e.primary_muscle
      ''',
      variables: [
        Variable.withString(userId),
        Variable.withDateTime(weekStart),
        Variable.withDateTime(weekEnd),
      ],
    ).get();

    return {
      for (final row in results)
        row.read<String>('primary_muscle'):
          row.read<double?>('volume') ?? 0.0,
    };
  }

  /// Personal record for exercise
  Future<PersonalRecord?> getExercisePR(String exerciseId, String userId) {
    return (select(personalRecords)
      ..where((pr) =>
        pr.exerciseId.equals(exerciseId) &
        pr.userId.equals(userId))
      ..orderBy([(pr) => OrderingTerm.desc(pr.estimated1Rm)])
      ..limit(1))
    .getSingleOrNull();
  }

  // ─── SYNC QUEUE ──────────────────────────────────────────────
  Future<void> addToSyncQueue({
    required String entityType,
    required String entityId,
    required String operation,
    required String payload,
  }) async {
    await into(syncQueue).insert(SyncQueueCompanion(
      entityType: Value(entityType),
      entityId:   Value(entityId),
      operation:  Value(operation),
      payload:    Value(payload),
    ));
  }

  Future<List<SyncQueueData>> getPendingSyncItems() {
    return (select(syncQueue)
      ..where((q) => q.retryCount.isSmallerThanValue(3))
      ..orderBy([(q) => OrderingTerm.asc(q.queuedAt)])
      ..limit(50))
    .get();
  }

  // ─── SEED DATA ───────────────────────────────────────────────
  Future<void> _seedBuiltInExercises() async {
    final builtIn = _getBuiltInExercises();
    await batch((b) {
      b.insertAllOnConflictUpdate(exercises, builtIn);
    });
  }

  List<ExercisesCompanion> _getBuiltInExercises() => [
    // Compound movements
    ExercisesCompanion(
      id: const Value('ex_squat'),
      name: const Value('Barbell Back Squat'),
      primaryMuscle: const Value('quads'),
      secondaryMuscles: const Value('["glutes","hamstrings","abs","traps"]'),
      equipment: const Value('barbell'),
      category: const Value('compound'),
      description: const Value('The king of all exercises. Full leg development.'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_deadlift'),
      name: const Value('Conventional Deadlift'),
      primaryMuscle: const Value('back'),
      secondaryMuscles: const Value('["hamstrings","glutes","traps","abs"]'),
      equipment: const Value('barbell'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_bench'),
      name: const Value('Barbell Bench Press'),
      primaryMuscle: const Value('chest'),
      secondaryMuscles: const Value('["shoulders","triceps"]'),
      equipment: const Value('barbell'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_ohp'),
      name: const Value('Overhead Press'),
      primaryMuscle: const Value('shoulders'),
      secondaryMuscles: const Value('["triceps","traps","abs"]'),
      equipment: const Value('barbell'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_row'),
      name: const Value('Barbell Row'),
      primaryMuscle: const Value('back'),
      secondaryMuscles: const Value('["biceps","lats","traps"]'),
      equipment: const Value('barbell'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_pullup'),
      name: const Value('Pull-up'),
      primaryMuscle: const Value('lats'),
      secondaryMuscles: const Value('["biceps","back"]'),
      equipment: const Value('bodyweight'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_rdl'),
      name: const Value('Romanian Deadlift'),
      primaryMuscle: const Value('hamstrings'),
      secondaryMuscles: const Value('["glutes","back"]'),
      equipment: const Value('barbell'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_dip'),
      name: const Value('Dips'),
      primaryMuscle: const Value('triceps'),
      secondaryMuscles: const Value('["chest","shoulders"]'),
      equipment: const Value('bodyweight'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
    // Isolation movements
    ExercisesCompanion(
      id: const Value('ex_curl'),
      name: const Value('Barbell Curl'),
      primaryMuscle: const Value('biceps'),
      secondaryMuscles: const Value('["forearms"]'),
      equipment: const Value('barbell'),
      category: const Value('isolation'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_lateral_raise'),
      name: const Value('Lateral Raise'),
      primaryMuscle: const Value('shoulders'),
      secondaryMuscles: const Value('[]'),
      equipment: const Value('dumbbell'),
      category: const Value('isolation'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_leg_press'),
      name: const Value('Leg Press'),
      primaryMuscle: const Value('quads'),
      secondaryMuscles: const Value('["glutes","hamstrings"]'),
      equipment: const Value('machine'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_cable_row'),
      name: const Value('Cable Row'),
      primaryMuscle: const Value('back'),
      secondaryMuscles: const Value('["biceps","lats"]'),
      equipment: const Value('cable'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_incline_bench'),
      name: const Value('Incline Dumbbell Press'),
      primaryMuscle: const Value('chest'),
      secondaryMuscles: const Value('["shoulders","triceps"]'),
      equipment: const Value('dumbbell'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_front_squat'),
      name: const Value('Front Squat'),
      primaryMuscle: const Value('quads'),
      secondaryMuscles: const Value('["glutes","abs","back"]'),
      equipment: const Value('barbell'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
    ExercisesCompanion(
      id: const Value('ex_hip_thrust'),
      name: const Value('Hip Thrust'),
      primaryMuscle: const Value('glutes'),
      secondaryMuscles: const Value('["hamstrings"]'),
      equipment: const Value('barbell'),
      category: const Value('compound'),
      isCustom: const Value(false),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────
// DB CONNECTION
// ─────────────────────────────────────────────────────────────
QueryExecutor _openConnection() {
  return driftDatabase(name: 'ironlog_db');
}
