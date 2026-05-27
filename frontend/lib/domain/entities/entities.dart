// ─────────────────────────────────────────────────────────────
// EXERCISE ENTITY
// ─────────────────────────────────────────────────────────────
import 'package:freezed_annotation/freezed_annotation.dart';

part 'entities.freezed.dart';

enum MuscleGroup {
  chest, back, shoulders, biceps, triceps, forearms,
  quads, hamstrings, glutes, calves, abs, traps, lats,
  fullBody, cardio,
}

enum Equipment {
  barbell, dumbbell, machine, cable, bodyweight,
  kettlebell, bands, ezBar, trapBar, smith, other,
}

enum ExerciseCategory {
  compound, isolation, cardio, plyometric, stretch,
}

@freezed
class Exercise with _$Exercise {
  const factory Exercise({
    required String id,
    required String name,
    required MuscleGroup primaryMuscle,
    required List<MuscleGroup> secondaryMuscles,
    required Equipment equipment,
    required ExerciseCategory category,
    String? description,
    String? videoUrl,
    String? thumbnailUrl,
    String? instructions,
    @Default(false) bool isCustom,
    @Default(false) bool isFavorite,
    String? userId,       // null = global exercise
    DateTime? createdAt,
  }) = _Exercise;
}

// ─────────────────────────────────────────────────────────────
// SET ENTITY
// ─────────────────────────────────────────────────────────────
enum SetType {
  normal,
  warmup,
  dropSet,
  amrap,     // As many reps as possible
  myoRep,
  cluster,
  superset,
}

@freezed
class WorkoutSet with _$WorkoutSet {
  const factory WorkoutSet({
    required String id,
    required String workoutExerciseId,
    required int setNumber,
    required SetType type,
    double? targetWeight,    // kg
    int? targetReps,
    double? targetRpe,       // 1-10
    int? targetRir,          // Reps in reserve
    String? tempo,           // e.g. "3-1-2-0" (eccentric-pause-concentric-pause)
    int? targetDuration,     // seconds, for timed sets
    // Logged values
    double? loggedWeight,
    int? loggedReps,
    double? loggedRpe,
    bool? completed,
    int? restSeconds,
    DateTime? completedAt,
    String? notes,
  }) = _WorkoutSet;

  const WorkoutSet._();

  /// Estimated 1RM using Epley formula
  double? get estimated1RM {
    if (loggedWeight == null || loggedReps == null || loggedReps! <= 0) return null;
    if (loggedReps == 1) return loggedWeight;
    return loggedWeight! * (1 + loggedReps! / 30.0);
  }

  /// Volume load for this set
  double? get volume {
    if (loggedWeight == null || loggedReps == null) return null;
    return loggedWeight! * loggedReps!;
  }
}

// ─────────────────────────────────────────────────────────────
// WORKOUT EXERCISE ENTITY
// ─────────────────────────────────────────────────────────────
@freezed
class WorkoutExercise with _$WorkoutExercise {
  const factory WorkoutExercise({
    required String id,
    required String workoutId,
    required Exercise exercise,
    required int order,
    required List<WorkoutSet> sets,
    int? restSeconds,
    String? notes,
    String? supersetGroupId,   // Groups exercises into supersets
  }) = _WorkoutExercise;

  const WorkoutExercise._();

  double get totalVolume => sets
      .where((s) => s.volume != null)
      .fold(0.0, (sum, s) => sum + s.volume!);

  WorkoutSet? get bestSet => sets
      .where((s) => s.estimated1RM != null)
      .reduce((a, b) => (a.estimated1RM ?? 0) > (b.estimated1RM ?? 0) ? a : b);
}

// ─────────────────────────────────────────────────────────────
// WORKOUT ENTITY
// ─────────────────────────────────────────────────────────────
enum WorkoutStatus { planned, inProgress, completed, skipped }

@freezed
class Workout with _$Workout {
  const factory Workout({
    required String id,
    required String userId,
    required String name,
    required WorkoutStatus status,
    required DateTime date,
    required List<WorkoutExercise> exercises,
    String? programId,
    int? programDay,
    int? durationSeconds,
    String? notes,
    double? bodyweight,    // logged bodyweight that day
    int? perceivedDifficulty,  // 1-10
    DateTime? startedAt,
    DateTime? completedAt,
  }) = _Workout;

  const Workout._();

  /// Total training volume (weight × reps across all exercises)
  double get totalVolume => exercises.fold(0.0, (sum, e) => sum + e.totalVolume);

  /// Total sets completed
  int get totalSets => exercises.fold(
    0, (sum, e) => sum + e.sets.where((s) => s.completed == true).length,
  );

  /// Duration in minutes
  int? get durationMinutes {
    if (durationSeconds == null) return null;
    return (durationSeconds! / 60).round();
  }
}

// ─────────────────────────────────────────────────────────────
// PROGRAM ENTITY
// ─────────────────────────────────────────────────────────────
enum ProgramType {
  powerlifting, bodybuilding, strengthEndurance,
  hiit, generalFitness, olympic, custom,
}

enum ProgressionType {
  linear,         // Add weight each session
  doubleProgression, // Progress reps then weight
  rpeBased,       // Based on RPE targets
  percentageBased, // % of 1RM
  waveLoading,    // Wave periodization
  dailyUndulating, // DUP
  blockPeriodization,
  custom,
}

@freezed
class ProgramDay with _$ProgramDay {
  const factory ProgramDay({
    required String id,
    required String programId,
    required int dayNumber,      // 1-indexed
    required String name,        // e.g. "Day A - Squat Focus"
    required List<ProgramExercise> exercises,
    bool? isRestDay,
  }) = _ProgramDay;
}

@freezed
class ProgramExercise with _$ProgramExercise {
  const factory ProgramExercise({
    required String id,
    required String programDayId,
    required Exercise exercise,
    required int order,
    required int sets,
    required String repsScheme,     // e.g. "5", "8-12", "5x5", "AMRAP"
    String? weightScheme,           // e.g. "80%1RM", "+2.5kg", "RPE 8"
    String? progressionScript,      // Custom Liftosaur-style formula
    ProgressionType? progressionType,
    int? restSeconds,
    double? rpeTarget,
    int? rirTarget,
    String? tempo,
    String? notes,
  }) = _ProgramExercise;
}

@freezed
class Program with _$Program {
  const factory Program({
    required String id,
    required String name,
    required String description,
    required ProgramType type,
    required int daysPerWeek,
    required int durationWeeks,   // 0 = indefinite
    required List<ProgramDay> days,
    required String authorId,
    String? authorName,
    ProgramType? category,
    ProgressionType? mainProgressionType,
    String? progressionScript,    // Global script
    @Default(false) bool isPublic,
    @Default(false) bool isPremium,
    @Default(0) int downloads,
    @Default(0.0) double rating,
    int? ratingCount,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) = _Program;
}

// ─────────────────────────────────────────────────────────────
// USER ENTITY
// ─────────────────────────────────────────────────────────────
enum SubscriptionTier { free, proMonthly, proYearly, lifetime }

@freezed
class UserProfile with _$UserProfile {
  const factory UserProfile({
    required String id,
    required String email,
    String? displayName,
    String? avatarUrl,
    double? bodyweight,          // kg
    double? height,              // cm
    DateTime? dateOfBirth,
    SubscriptionTier? subscription,
    DateTime? subscriptionExpiry,
    String? activeProgramId,
    int? activeProgramWeek,
    int? activeProgramDay,
    @Default(false) bool isPublicProfile,
    DateTime? createdAt,
    DateTime? lastSyncAt,
  }) = _UserProfile;
}

// ─────────────────────────────────────────────────────────────
// PERSONAL RECORD ENTITY
// ─────────────────────────────────────────────────────────────
@freezed
class PersonalRecord with _$PersonalRecord {
  const factory PersonalRecord({
    required String id,
    required String userId,
    required String exerciseId,
    required String exerciseName,
    required double weight,
    required int reps,
    required double estimated1RM,
    required DateTime achievedAt,
    String? workoutId,
  }) = _PersonalRecord;
}

// ─────────────────────────────────────────────────────────────
// PROGRESSION SCRIPT ENTITY (Liftosaur-style)
// ─────────────────────────────────────────────────────────────
@freezed
class ProgressionScript with _$ProgressionScript {
  const factory ProgressionScript({
    required String id,
    required String name,
    required String script,          // DSL formula
    String? description,
    @Default(false) bool isBuiltIn,
    String? userId,
  }) = _ProgressionScript;
}
