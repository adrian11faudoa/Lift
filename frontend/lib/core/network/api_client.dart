import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.instance);

// ─────────────────────────────────────────────────────────────
// API CLIENT
// Dio-based HTTP client with:
// - Auth interceptor (auto-attach JWT)
// - Token refresh on 401
// - Retry on network errors
// - Request/response logging in debug
// ─────────────────────────────────────────────────────────────
class ApiClient {
  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl:        _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout:    const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept':       'application/json',
      },
    ));
    _setupInterceptors();
  }

  static final ApiClient instance = ApiClient._();
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  // ── CONFIG ──────────────────────────────────────────────────
  static const _baseUrl     = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );
  static const _accessKey   = 'access_token';
  static const _refreshKey  = 'refresh_token';

  bool _isRefreshing = false;
  final _failedQueue = <_QueuedRequest>[];

  // ── INTERCEPTORS ─────────────────────────────────────────────
  void _setupInterceptors() {
    // Auth
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError:   _onError,
    ));

    // Logging (debug only)
    assert(() {
      _dio.interceptors.add(LogInterceptor(
        requestBody:  true,
        responseBody: false, // Too verbose
        logPrint:     (obj) => debugPrint('[API] $obj'),
      ));
      return true;
    }());
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.read(key: _accessKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // 401 → refresh token
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshed = await _refreshAccessToken();
        if (refreshed) {
          // Retry original request
          final opts = err.requestOptions;
          final token = await _storage.read(key: _accessKey);
          opts.headers['Authorization'] = 'Bearer $token';
          final response = await _dio.request(
            opts.path,
            options: Options(method: opts.method, headers: opts.headers),
            data:    opts.data,
          );
          handler.resolve(response);
          // Retry queued requests
          for (final req in _failedQueue) {
            req.resolve();
          }
          _failedQueue.clear();
          return;
        }
      } catch (_) {
        // Refresh failed → logout
        await _clearTokens();
      } finally {
        _isRefreshing = false;
      }
    }

    // Network errors — return offline-friendly error
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.receiveTimeout) {
      handler.reject(DioException(
        requestOptions: err.requestOptions,
        type:           DioExceptionType.connectionError,
        message:        'offline',
      ));
      return;
    }

    handler.next(err);
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = await _storage.read(key: _refreshKey);
    if (refreshToken == null) return false;

    try {
      final response = await Dio().post(
        '$_baseUrl/api/v1/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final newAccessToken = response.data['accessToken'] as String?;
      if (newAccessToken == null) return false;
      await _storage.write(key: _accessKey, value: newAccessToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearTokens() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  // ── TOKEN MANAGEMENT ─────────────────────────────────────────
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey,  value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<bool> get isAuthenticated async {
    final token = await _storage.read(key: _accessKey);
    return token != null;
  }

  Future<void> logout() async {
    await _clearTokens();
  }

  // ── API ENDPOINTS ─────────────────────────────────────────────

  // Auth
  Future<Map<String, dynamic>> login(String email, String password) async {
    final r = await _dio.post('/api/v1/auth/login', data: {
      'email': email, 'password': password,
    });
    return r.data;
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final r = await _dio.post('/api/v1/auth/register', data: {
      'email': email, 'password': password,
      if (displayName != null) 'displayName': displayName,
    });
    return r.data;
  }

  Future<Map<String, dynamic>> googleAuth(String idToken) async {
    final r = await _dio.post('/api/v1/auth/google', data: {'idToken': idToken});
    return r.data;
  }

  Future<Map<String, dynamic>> appleAuth({
    required String identityToken,
    String? displayName,
  }) async {
    final r = await _dio.post('/api/v1/auth/apple', data: {
      'identityToken': identityToken,
      if (displayName != null) 'displayName': displayName,
    });
    return r.data;
  }

  // Workouts (sync)
  Future<Map<String, dynamic>> syncWorkouts(Map<String, dynamic> body) async {
    final r = await _dio.post('/api/v1/workouts/sync', data: body);
    return r.data;
  }

  Future<void> deleteWorkout(String id) async {
    await _dio.delete('/api/v1/workouts/$id');
  }

  Future<List<dynamic>> getWorkouts({String? startDate, String? endDate}) async {
    final r = await _dio.get('/api/v1/workouts', queryParameters: {
      if (startDate != null) 'startDate': startDate,
      if (endDate   != null) 'endDate':   endDate,
    });
    return r.data['workouts'] as List;
  }

  // Exercises
  Future<void> upsertExercise(Map<String, dynamic> exercise) async {
    await _dio.post('/api/v1/exercises', data: exercise);
  }

  Future<void> deleteExercise(String id) async {
    await _dio.delete('/api/v1/exercises/$id');
  }

  Future<List<dynamic>> getExercises({
    String? search, String? muscle, String? equipment,
  }) async {
    final r = await _dio.get('/api/v1/exercises', queryParameters: {
      if (search    != null) 'search':    search,
      if (muscle    != null) 'muscle':    muscle,
      if (equipment != null) 'equipment': equipment,
    });
    return r.data as List;
  }

  // Programs
  Future<void> upsertProgram(Map<String, dynamic> program) async {
    await _dio.post('/api/v1/programs', data: program);
  }

  Future<void> deleteProgram(String id) async {
    await _dio.delete('/api/v1/programs/$id');
  }

  Future<List<dynamic>> getPublicPrograms({
    String? type, String? search, int page = 1,
  }) async {
    final r = await _dio.get('/api/v1/programs/public', queryParameters: {
      if (type   != null) 'type':   type,
      if (search != null) 'search': search,
      'page': page,
    });
    return r.data['programs'] as List;
  }

  // Analytics
  Future<List<dynamic>> getExerciseHistory(
    String exerciseId, {int limit = 30}
  ) async {
    final r = await _dio.get(
      '/api/v1/workouts/analytics/exercise/$exerciseId',
      queryParameters: {'limit': limit},
    );
    return r.data as List;
  }

  Future<List<dynamic>> getVolumeByMuscle(
    String startDate, String endDate,
  ) async {
    final r = await _dio.get(
      '/api/v1/workouts/analytics/volume-by-muscle',
      queryParameters: {'startDate': startDate, 'endDate': endDate},
    );
    return r.data as List;
  }

  // AI
  Future<Map<String, dynamic>> getAIRecommendations() async {
    final r = await _dio.get('/api/v1/ai/recommendations');
    return r.data;
  }

  Future<Map<String, dynamic>> generateAIProgram({
    required String goal,
    required int daysPerWeek,
  }) async {
    final r = await _dio.post('/api/v1/ai/generate-program', data: {
      'goal': goal, 'daysPerWeek': daysPerWeek,
    });
    return r.data;
  }

  // User profile
  Future<Map<String, dynamic>> getProfile() async {
    final r = await _dio.get('/api/v1/auth/me');
    return r.data;
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final r = await _dio.post('/api/v1/auth/me', data: data);
    return r.data;
  }

  // Health check
  Future<bool> healthCheck() async {
    try {
      final r = await _dio.get('/health');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

class _QueuedRequest {
  final void Function() resolve;
  _QueuedRequest(this.resolve);
}
