import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/entities.dart';
import '../../data/repositories/workout_repository.dart';
import '../../core/storage/database.dart';

// ─────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────
class AnalyticsDataPoint {
  const AnalyticsDataPoint({required this.date, required this.value, this.label});
  final DateTime date;
  final double value;
  final String? label;
}

// ─────────────────────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────────────────────
class AnalyticsState {
  const AnalyticsState({
    this.e1rmData           = const [],
    this.maxWeightData      = const [],
    this.weeklyVolumeData   = const [],
    this.frequencyData      = const [],
    this.bodyweightData     = const [],
    this.muscleVolumeData   = const {},
    this.muscleSetCounts    = const {},
    this.recentPRs          = const [],
    this.workoutDates       = const [],
    this.totalWorkouts      = 0,
    this.totalVolume        = 0,
    this.avgDurationMinutes = 0,
    this.monthlyPRCount     = 0,
    this.upperBodyRecovery  = 1.0,
    this.lowerBodyRecovery  = 1.0,
    this.isLoading          = false,
    this.selectedPeriod     = '3M',
    this.selectedExerciseId,
  });

  final List<AnalyticsDataPoint> e1rmData;
  final List<AnalyticsDataPoint> maxWeightData;
  final List<AnalyticsDataPoint> weeklyVolumeData;
  final List<AnalyticsDataPoint> frequencyData;
  final List<AnalyticsDataPoint> bodyweightData;
  final Map<String, double>      muscleVolumeData;
  final Map<String, int>         muscleSetCounts;
  final List<PersonalRecord>     recentPRs;
  final List<DateTime>           workoutDates;
  final int    totalWorkouts;
  final double totalVolume;
  final int    avgDurationMinutes;
  final int    monthlyPRCount;
  final double upperBodyRecovery;
  final double lowerBodyRecovery;
  final bool   isLoading;
  final String selectedPeriod;
  final String? selectedExerciseId;

  AnalyticsState copyWith({
    List<AnalyticsDataPoint>? e1rmData,
    List<AnalyticsDataPoint>? maxWeightData,
    List<AnalyticsDataPoint>? weeklyVolumeData,
    List<AnalyticsDataPoint>? frequencyData,
    List<AnalyticsDataPoint>? bodyweightData,
    Map<String, double>?      muscleVolumeData,
    Map<String, int>?         muscleSetCounts,
    List<PersonalRecord>?     recentPRs,
    List<DateTime>?           workoutDates,
    int?    totalWorkouts,
    double? totalVolume,
    int?    avgDurationMinutes,
    int?    monthlyPRCount,
    double? upperBodyRecovery,
    double? lowerBodyRecovery,
    bool?   isLoading,
    String? selectedPeriod,
    String? selectedExerciseId,
  }) => AnalyticsState(
    e1rmData:           e1rmData           ?? this.e1rmData,
    maxWeightData:      maxWeightData      ?? this.maxWeightData,
    weeklyVolumeData:   weeklyVolumeData   ?? this.weeklyVolumeData,
    frequencyData:      frequencyData      ?? this.frequencyData,
    bodyweightData:     bodyweightData     ?? this.bodyweightData,
    muscleVolumeData:   muscleVolumeData   ?? this.muscleVolumeData,
    muscleSetCounts:    muscleSetCounts    ?? this.muscleSetCounts,
    recentPRs:          recentPRs          ?? this.recentPRs,
    workoutDates:       workoutDates       ?? this.workoutDates,
    totalWorkouts:      totalWorkouts      ?? this.totalWorkouts,
    totalVolume:        totalVolume        ?? this.totalVolume,
    avgDurationMinutes: avgDurationMinutes ?? this.avgDurationMinutes,
    monthlyPRCount:     monthlyPRCount     ?? this.monthlyPRCount,
    upperBodyRecovery:  upperBodyRecovery  ?? this.upperBodyRecovery,
    lowerBodyRecovery:  lowerBodyRecovery  ?? this.lowerBodyRecovery,
    isLoading:          isLoading          ?? this.isLoading,
    selectedPeriod:     selectedPeriod     ?? this.selectedPeriod,
    selectedExerciseId: selectedExerciseId ?? this.selectedExerciseId,
  );
}

// ─────────────────────────────────────────────────────────────
// PROVIDER
// ─────────────────────────────────────────────────────────────
final analyticsProvider =
    StateNotifierProvider<AnalyticsNotifier, AnalyticsState>((ref) {
  return AnalyticsNotifier(AppDatabase.instance);
});

// ─────────────────────────────────────────────────────────────
// NOTIFIER
// ─────────────────────────────────────────────────────────────
class AnalyticsNotifier extends StateNotifier<AnalyticsState> {
  AnalyticsNotifier(this._db) : super(const AnalyticsState()) {
    _loadAll();
  }

  final AppDatabase _db;
  static const String _userId = 'local_user';

  // ─── PUBLIC API ──────────────────────────────────────────────
  void setPeriod(String period) {
    state = state.copyWith(selectedPeriod: period);
    _loadAll();
  }

  Future<void> loadExerciseHistory(String exerciseId) async {
    state = state.copyWith(selectedExerciseId: exerciseId, isLoading: true);
    await _loadStrengthData(exerciseId);
    state = state.copyWith(isLoading: false);
  }

  Future<void> refresh() => _loadAll();

  // ─── LOAD ALL DATA ───────────────────────────────────────────
  Future<void> _loadAll() async {
    state = state.copyWith(isLoading: true);

    final start = _periodStart(state.selectedPeriod);
    final end   = DateTime.now();

    await Future.wait([
      _loadWorkoutStats(start, end),
      _loadWeeklyVolume(start, end),
      _loadMuscleData(start, end),
      _loadBodyweightData(start, end),
      _loadRecentPRs(),
      _loadWorkoutDates(start, end),
      if (state.selectedExerciseId != null)
        _loadStrengthData(state.selectedExerciseId!),
    ]);

    state = state.copyWith(isLoading: false);
  }

  // ─── WORKOUT STATS ───────────────────────────────────────────
  Future<void> _loadWorkoutStats(DateTime start, DateTime end) async {
    final workouts = await _db.getWorkoutsForDateRange(start, end, _userId);
    final completed = workouts.where(
      (w) => w.status == WorkoutStatus.completed,
    ).toList();

    final totalVol = completed.fold(0.0, (sum, w) => sum + w.totalVolume);
    final avgDur   = completed.isEmpty
        ? 0
        : completed
              .where((w) => w.durationSeconds != null)
              .map((w) => w.durationMinutes ?? 0)
              .fold(0, (sum, d) => sum + d) ~/
            (completed.where((w) => w.durationSeconds != null).length + 1);

    // Monthly PR count
    final monthStart = DateTime(end.year, end.month, 1);
    final allPRs = await _db.select(_db.personalRecords)
        .get()
        .then((list) => list.where(
              (pr) => pr.achievedAt.isAfter(monthStart),
            ).toList());

    state = state.copyWith(
      totalWorkouts:      completed.length,
      totalVolume:        totalVol,
      avgDurationMinutes: avgDur,
      monthlyPRCount:     allPRs.length,
    );
  }

  // ─── WEEKLY VOLUME ───────────────────────────────────────────
  Future<void> _loadWeeklyVolume(DateTime start, DateTime end) async {
    final weeks = <AnalyticsDataPoint>[];
    var weekStart = start;
    while (weekStart.isBefore(end)) {
      final weekEnd = weekStart.add(const Duration(days: 7));
      final workouts = await _db.getWorkoutsForDateRange(
        weekStart, weekEnd, _userId,
      );
      final vol = workouts.fold(0.0, (sum, w) => sum + w.totalVolume);
      weeks.add(AnalyticsDataPoint(date: weekStart, value: vol));
      weekStart = weekEnd;
    }
    state = state.copyWith(weeklyVolumeData: weeks);
  }

  // ─── STRENGTH DATA ───────────────────────────────────────────
  Future<void> _loadStrengthData(String exerciseId) async {
    final history = await _db.getExerciseHistory(exerciseId, _userId);
    final e1rmPoints = history
        .where((h) => h.estimated1Rm != null)
        .map((h) => AnalyticsDataPoint(
              date:  h.date,
              value: h.estimated1Rm!,
            ))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final maxWeightPoints = history
        .where((h) => h.maxWeight != null)
        .map((h) => AnalyticsDataPoint(
              date:  h.date,
              value: h.maxWeight!,
            ))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    state = state.copyWith(
      e1rmData:      e1rmPoints,
      maxWeightData: maxWeightPoints,
    );
  }

  // ─── MUSCLE DATA ─────────────────────────────────────────────
  Future<void> _loadMuscleData(DateTime start, DateTime end) async {
    // Weekly set counts by muscle
    final weekStart = DateTime.now().subtract(const Duration(days: 7));
    final weekVolume = await _db.getWeeklyVolumeByMuscle(_userId, weekStart);

    // Estimate set counts (volume / avg set volume)
    final setCounts = weekVolume.map(
      (muscle, vol) => MapEntry(muscle, (vol / 3000).round()),
    );

    // Recovery estimation (simplistic: based on sets vs recommended)
    const upperMuscles = ['chest', 'back', 'shoulders', 'biceps', 'triceps'];
    const lowerMuscles = ['quads', 'hamstrings', 'glutes', 'calves'];

    final upperSets = upperMuscles
        .map((m) => setCounts[m] ?? 0)
        .fold(0, (a, b) => a + b);
    final lowerSets = lowerMuscles
        .map((m) => setCounts[m] ?? 0)
        .fold(0, (a, b) => a + b);

    // 20 sets/week = overreached, 10 = optimal, 0 = fully recovered
    final upperRecovery = (1.0 - upperSets / 20.0).clamp(0.0, 1.0);
    final lowerRecovery = (1.0 - lowerSets / 20.0).clamp(0.0, 1.0);

    state = state.copyWith(
      muscleVolumeData:  weekVolume,
      muscleSetCounts:   setCounts,
      upperBodyRecovery: upperRecovery,
      lowerBodyRecovery: lowerRecovery,
    );
  }

  // ─── BODYWEIGHT DATA ─────────────────────────────────────────
  Future<void> _loadBodyweightData(DateTime start, DateTime end) async {
    final workouts = await _db.getWorkoutsForDateRange(start, end, _userId);
    final bwPoints = workouts
        .where((w) => w.bodyweight != null)
        .map((w) => AnalyticsDataPoint(date: w.date, value: w.bodyweight!))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    state = state.copyWith(bodyweightData: bwPoints);
  }

  // ─── RECENT PRs ──────────────────────────────────────────────
  Future<void> _loadRecentPRs() async {
    final rows = await (_db.select(_db.personalRecords)
          ..where((pr) => pr.userId.equals(_userId))
          ..orderBy([(pr) => OrderingTerm.desc(pr.achievedAt)])
          ..limit(10))
        .get();

    final prs = rows.map((r) => PersonalRecord(
          id:           r.id,
          userId:       r.userId,
          exerciseId:   r.exerciseId,
          exerciseName: r.exerciseName,
          weight:       r.weight,
          reps:         r.reps,
          estimated1RM: r.estimated1Rm,
          achievedAt:   r.achievedAt,
          workoutId:    r.workoutId,
        )).toList();

    state = state.copyWith(recentPRs: prs);
  }

  // ─── WORKOUT DATES ───────────────────────────────────────────
  Future<void> _loadWorkoutDates(DateTime start, DateTime end) async {
    final workouts = await _db.getWorkoutsForDateRange(start, end, _userId);
    final dates = workouts
        .where((w) => w.status == WorkoutStatus.completed)
        .map((w) => w.date)
        .toList();
    state = state.copyWith(workoutDates: dates);
  }

  // ─── HELPERS ─────────────────────────────────────────────────
  DateTime _periodStart(String period) {
    final now = DateTime.now();
    return switch (period) {
      '1M'  => now.subtract(const Duration(days: 30)),
      '3M'  => now.subtract(const Duration(days: 90)),
      '6M'  => now.subtract(const Duration(days: 180)),
      '1Y'  => now.subtract(const Duration(days: 365)),
      'All' => DateTime(2020),
      _     => now.subtract(const Duration(days: 90)),
    };
  }
}
