import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/api_client.dart';
import '../core/storage/database.dart';

// ─────────────────────────────────────────────────────────────
// SYNC STATUS
// ─────────────────────────────────────────────────────────────
enum SyncStatus { idle, syncing, synced, failed, offline }

class SyncState {
  const SyncState({
    this.status         = SyncStatus.idle,
    this.lastSyncAt,
    this.pendingCount   = 0,
    this.failedCount    = 0,
    this.error,
  });

  final SyncStatus  status;
  final DateTime?   lastSyncAt;
  final int         pendingCount;
  final int         failedCount;
  final String?     error;

  SyncState copyWith({
    SyncStatus? status,
    DateTime?   lastSyncAt,
    int?        pendingCount,
    int?        failedCount,
    String?     error,
  }) => SyncState(
    status:       status       ?? this.status,
    lastSyncAt:   lastSyncAt   ?? this.lastSyncAt,
    pendingCount: pendingCount ?? this.pendingCount,
    failedCount:  failedCount  ?? this.failedCount,
    error:        error,
  );

  bool get isSyncing  => status == SyncStatus.syncing;
  bool get isOffline  => status == SyncStatus.offline;
  bool get hasPending => pendingCount > 0;
}

// ─────────────────────────────────────────────────────────────
// PROVIDER
// ─────────────────────────────────────────────────────────────
final syncServiceProvider = StateNotifierProvider<SyncService, SyncState>((ref) {
  return SyncService(
    db:     AppDatabase.instance,
    client: ref.watch(apiClientProvider),
  );
});

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────
class SyncService extends StateNotifier<SyncState> {
  SyncService({required this.db, required this.client})
      : super(const SyncState()) {
    _initialize();
  }

  final AppDatabase _db = db;
  final ApiClient   _client = client;

  final AppDatabase db;
  final ApiClient   client;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicSyncTimer;

  static const _syncIntervalMinutes = 5;
  static const _maxRetries = 3;

  // ─── INIT ─────────────────────────────────────────────────────
  Future<void> _initialize() async {
    // Listen to connectivity changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    // Check initial connectivity
    final result = await Connectivity().checkConnectivity();
    if (!result.contains(ConnectivityResult.none)) {
      _startPeriodicSync();
      _syncNow(); // Sync on startup
    } else {
      state = state.copyWith(status: SyncStatus.offline);
    }

    // Load pending count
    await _updatePendingCount();
  }

  // ─── CONNECTIVITY ─────────────────────────────────────────────
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final isOnline = !results.contains(ConnectivityResult.none);
    if (isOnline) {
      state = state.copyWith(status: SyncStatus.idle);
      _startPeriodicSync();
      _syncNow();   // Sync immediately when reconnected
    } else {
      state = state.copyWith(status: SyncStatus.offline);
      _periodicSyncTimer?.cancel();
    }
  }

  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(
      Duration(minutes: _syncIntervalMinutes),
      (_) => _syncNow(),
    );
  }

  // ─── SYNC TRIGGER ─────────────────────────────────────────────
  Future<void> triggerSync() => _syncNow();

  Future<void> _syncNow() async {
    if (state.isSyncing) return;

    final pending = await _db.getPendingSyncItems();
    if (pending.isEmpty) {
      state = state.copyWith(
        status:     SyncStatus.synced,
        lastSyncAt: DateTime.now(),
        pendingCount: 0,
      );
      return;
    }

    state = state.copyWith(
      status:       SyncStatus.syncing,
      pendingCount: pending.length,
    );

    int synced  = 0;
    int failed  = 0;

    for (final item in pending) {
      final success = await _processSyncItem(item);
      if (success) {
        synced++;
        // Remove from queue
        await (_db.delete(_db.syncQueue)
          ..where((q) => q.id.equals(item.id)))
            .go();
      } else {
        failed++;
        // Increment retry count
        await (_db.update(_db.syncQueue)
          ..where((q) => q.id.equals(item.id)))
            .write(SyncQueueCompanion(
              retryCount: Value(item.retryCount + 1),
            ));
      }
    }

    state = state.copyWith(
      status:      failed == 0 ? SyncStatus.synced : SyncStatus.failed,
      lastSyncAt:  DateTime.now(),
      pendingCount: failed,
      failedCount:  failed,
      error:       failed > 0 ? '$failed items failed to sync' : null,
    );
  }

  // ─── PROCESS SINGLE ITEM ──────────────────────────────────────
  Future<bool> _processSyncItem(SyncQueueData item) async {
    if (item.retryCount >= _maxRetries) {
      // Give up after max retries — don't block other items
      return true; // Remove from queue
    }

    try {
      final payload = jsonDecode(item.payload) as Map<String, dynamic>;

      switch (item.entityType) {
        case 'workout':
          return await _syncWorkout(item.operation, item.entityId, payload);
        case 'exercise':
          return await _syncExercise(item.operation, item.entityId, payload);
        case 'program':
          return await _syncProgram(item.operation, item.entityId, payload);
        default:
          return true; // Unknown type — remove
      }
    } catch (e) {
      return false;
    }
  }

  Future<bool> _syncWorkout(
    String operation,
    String id,
    Map<String, dynamic> payload,
  ) async {
    try {
      switch (operation) {
        case 'create':
        case 'update':
          final lastSync = state.lastSyncAt?.toIso8601String()
              ?? DateTime(2020).toIso8601String();
          await _client.syncWorkouts({
            'workouts':   [payload],
            'lastSyncAt': lastSync,
          });
          return true;
        case 'delete':
          await _client.deleteWorkout(id);
          return true;
        default:
          return true;
      }
    } catch (e) {
      return false;
    }
  }

  Future<bool> _syncExercise(
    String operation,
    String id,
    Map<String, dynamic> payload,
  ) async {
    try {
      if (operation == 'create' || operation == 'update') {
        await _client.upsertExercise(payload);
      } else if (operation == 'delete') {
        await _client.deleteExercise(id);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _syncProgram(
    String operation,
    String id,
    Map<String, dynamic> payload,
  ) async {
    try {
      if (operation == 'create' || operation == 'update') {
        await _client.upsertProgram(payload);
      } else if (operation == 'delete') {
        await _client.deleteProgram(id);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // ─── QUEUE HELPERS ────────────────────────────────────────────
  Future<void> queueWorkoutSync(String workoutId, Map<String, dynamic> payload) async {
    await _db.addToSyncQueue(
      entityType: 'workout',
      entityId:   workoutId,
      operation:  'update',
      payload:    jsonEncode(payload),
    );
    await _updatePendingCount();
    _syncNow(); // Try to sync immediately
  }

  Future<void> queueWorkoutDelete(String workoutId) async {
    await _db.addToSyncQueue(
      entityType: 'workout',
      entityId:   workoutId,
      operation:  'delete',
      payload:    '{}',
    );
    _syncNow();
  }

  // ─── SERVER → LOCAL MERGE ────────────────────────────────────
  /// Pull server changes and merge into local database.
  /// Conflict resolution: server wins for multi-device, client wins for single-device.
  Future<void> pullServerChanges() async {
    final lastSync = state.lastSyncAt?.toIso8601String()
        ?? DateTime(2020).toIso8601String();

    try {
      final response = await _client.syncWorkouts({
        'workouts':   [],   // No client uploads, just pull
        'lastSyncAt': lastSync,
      });

      final serverWorkouts = (response['serverChanges'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      for (final workoutData in serverWorkouts) {
        await _mergeServerWorkout(workoutData);
      }
    } catch (e) {
      // Silent fail — will retry
    }
  }

  Future<void> _mergeServerWorkout(Map<String, dynamic> data) async {
    // Check if local version is newer (user edited offline)
    final localWorkout = await (_db.select(_db.workouts)
      ..where((w) => w.id.equals(data['id'] as String)))
      .getSingleOrNull();

    if (localWorkout != null && !localWorkout.isSynced) {
      // Local is dirty — don't overwrite with server version
      return;
    }

    // Server version wins — update local
    await _db.into(_db.workouts).insertOnConflictUpdate(
      WorkoutsCompanion(
        id:        Value(data['id']),
        name:      Value(data['name']),
        status:    Value(data['status']),
        date:      Value(DateTime.parse(data['date'])),
        userId:    Value(data['userId']),
        isSynced:  const Value(true),
      ),
    );
  }

  // ─── HELPERS ─────────────────────────────────────────────────
  Future<void> _updatePendingCount() async {
    final pending = await _db.getPendingSyncItems();
    state = state.copyWith(pendingCount: pending.length);
  }

  // ─── SYNC INDICATOR WIDGET ────────────────────────────────────
  @override
  void dispose() {
    _connectivitySub?.cancel();
    _periodicSyncTimer?.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────
// SYNC STATUS INDICATOR WIDGET
// ─────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../presentation/themes/app_theme.dart';

class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncServiceProvider);

    return GestureDetector(
      onTap: () => ref.read(syncServiceProvider.notifier).triggerSync(),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (sync.status) {
          SyncStatus.syncing => const SizedBox(
              key: ValueKey('syncing'),
              width: 14, height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primaryBlue,
              ),
            ),
          SyncStatus.synced => const Icon(
              Icons.cloud_done_outlined,
              key: ValueKey('synced'),
              size: 18,
              color: AppTheme.accentGreen,
            ),
          SyncStatus.failed => const Icon(
              Icons.cloud_off_outlined,
              key: ValueKey('failed'),
              size: 18,
              color: AppTheme.accentRed,
            ),
          SyncStatus.offline => const Icon(
              Icons.wifi_off_rounded,
              key: ValueKey('offline'),
              size: 18,
              color: AppTheme.darkSubtext,
            ),
          _ => sync.hasPending
              ? Badge(
                  key: const ValueKey('pending'),
                  label: Text('${sync.pendingCount}'),
                  child: const Icon(Icons.cloud_upload_outlined, size: 18, color: AppTheme.darkSubtext),
                )
              : const Icon(
                  Icons.cloud_outlined,
                  key: ValueKey('idle'),
                  size: 18,
                  color: AppTheme.darkSubtext,
                ),
        },
      ),
    );
  }
}
