import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../presentation/pages/active_workout_page.dart';
import '../presentation/pages/analytics_page.dart';
import '../presentation/pages/program_builder_page.dart';
import '../presentation/blocs/active_workout_notifier.dart';

// ─────────────────────────────────────────────────────────────
// ROUTE NAMES
// ─────────────────────────────────────────────────────────────
class Routes {
  Routes._();
  static const splash          = '/';
  static const onboarding      = '/onboarding';
  static const login           = '/login';
  static const register        = '/register';
  static const dashboard       = '/dashboard';
  static const activeWorkout   = '/workout/active';
  static const workoutComplete = '/workout/complete';
  static const workoutHistory  = '/history';
  static const workoutDetail   = '/history/:id';
  static const exercises       = '/exercises';
  static const exerciseDetail  = '/exercises/:id';
  static const programs        = '/programs';
  static const programDetail   = '/programs/:id';
  static const programBuilder  = '/programs/builder';
  static const analytics       = '/analytics';
  static const profile         = '/profile';
  static const settings        = '/settings';
  static const subscription    = '/subscription';
  static const plateCalc       = '/tools/plate-calculator';
}

// ─────────────────────────────────────────────────────────────
// ROUTER PROVIDER
// ─────────────────────────────────────────────────────────────
final appRouterProvider = Provider<GoRouter>((ref) {
  final workoutState = ref.watch(activeWorkoutProvider);

  return GoRouter(
    initialLocation: Routes.dashboard,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      // If there's an active workout and user is navigating away from it,
      // we don't intercept — they can background it
      return null;
    },
    routes: [
      // ── Shell with bottom nav ─────────────────────────────
      ShellRoute(
        builder: (context, state, child) => _AppShell(child: child),
        routes: [
          GoRoute(
            path:    Routes.dashboard,
            name:    'dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path:    Routes.workoutHistory,
            name:    'history',
            builder: (context, state) => const WorkoutHistoryPage(),
            routes: [
              GoRoute(
                path:    ':id',
                builder: (context, state) => WorkoutDetailPage(
                  workoutId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path:    Routes.programs,
            name:    'programs',
            builder: (context, state) => const ProgramsPage(),
            routes: [
              GoRoute(
                path:    ':id',
                builder: (context, state) => ProgramDetailPage(
                  programId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path:    Routes.analytics,
            name:    'analytics',
            builder: (context, state) => const AnalyticsPage(),
          ),
          GoRoute(
            path:    Routes.profile,
            name:    'profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),

      // ── Full-screen routes (no shell) ─────────────────────
      GoRoute(
        path:    Routes.activeWorkout,
        name:    'activeWorkout',
        builder: (context, state) => const ActiveWorkoutPage(),
      ),
      GoRoute(
        path:    Routes.workoutComplete,
        name:    'workoutComplete',
        builder: (context, state) => WorkoutCompletePage(
          workout: state.extra as dynamic,
        ),
      ),
      GoRoute(
        path:    Routes.programBuilder,
        name:    'programBuilder',
        builder: (context, state) => ProgramBuilderPage(
          existingProgram: state.extra as dynamic,
        ),
      ),
      GoRoute(
        path:    Routes.exercises,
        name:    'exercises',
        builder: (context, state) => const ExerciseLibraryPage(),
        routes: [
          GoRoute(
            path:    ':id',
            builder: (context, state) => ExerciseDetailPage(
              exerciseId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path:    Routes.subscription,
        name:    'subscription',
        builder: (context, state) => const PaywallPage(),
      ),
      GoRoute(
        path:    Routes.settings,
        name:    'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path:    Routes.plateCalc,
        name:    'plateCalculator',
        builder: (context, state) => const PlateCalculatorPage(),
      ),
      GoRoute(
        path:    Routes.login,
        name:    'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path:    Routes.register,
        name:    'register',
        builder: (context, state) => const RegisterPage(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );
});

// ─────────────────────────────────────────────────────────────
// APP SHELL WITH BOTTOM NAV + ACTIVE WORKOUT BANNER
// ─────────────────────────────────────────────────────────────
class _AppShell extends ConsumerWidget {
  const _AppShell({required this.child});
  final Widget child;

  static const _tabs = [
    (icon: Icons.home_outlined,       activeIcon: Icons.home,             label: 'Home',     path: Routes.dashboard),
    (icon: Icons.history_outlined,    activeIcon: Icons.history,          label: 'History',  path: Routes.workoutHistory),
    (icon: Icons.space_dashboard_outlined, activeIcon: Icons.space_dashboard, label: 'Programs', path: Routes.programs),
    (icon: Icons.bar_chart_outlined,  activeIcon: Icons.bar_chart,        label: 'Analytics',path: Routes.analytics),
    (icon: Icons.person_outline,      activeIcon: Icons.person,           label: 'Profile',  path: Routes.profile),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location     = GoRouterState.of(context).uri.toString();
    final workoutState = ref.watch(activeWorkoutProvider);
    final currentIndex = _getCurrentIndex(location);

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: child),
          // ── Active Workout Banner ──────────────────────────
          if (workoutState.isActive && workoutState.workout != null)
            _ActiveWorkoutBanner(
              workoutName:    workoutState.workout!.name,
              elapsedSeconds: workoutState.elapsedSeconds,
              onTap:          () => context.go(Routes.activeWorkout),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex:  currentIndex,
        onDestinationSelected: (index) => context.go(_tabs[index].path),
        destinations: _tabs.map((tab) => NavigationDestination(
          icon:          Icon(tab.icon),
          selectedIcon:  Icon(tab.activeIcon),
          label:         tab.label,
        )).toList(),
      ),
    );
  }

  int _getCurrentIndex(String location) {
    for (var i = _tabs.length - 1; i >= 0; i--) {
      if (location.startsWith(_tabs[i].path)) return i;
    }
    return 0;
  }
}

// ─────────────────────────────────────────────────────────────
// ACTIVE WORKOUT BANNER
// ─────────────────────────────────────────────────────────────
class _ActiveWorkoutBanner extends StatelessWidget {
  const _ActiveWorkoutBanner({
    required this.workoutName,
    required this.elapsedSeconds,
    required this.onTap,
  });

  final String   workoutName;
  final int      elapsedSeconds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = elapsedSeconds ~/ 3600;
    final m = (elapsedSeconds % 3600) ~/ 60;
    final s = elapsedSeconds % 60;
    final timeStr = h > 0
        ? '${h}h ${m.toString().padLeft(2, '0')}m'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width:   double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E40AF), Color(0xFF2563EB)],
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            // Pulsing dot
            _PulsingDot(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize:       MainAxisSize.min,
                children: [
                  const Text(
                    'WORKOUT IN PROGRESS',
                    style: TextStyle(
                      fontSize:      10,
                      fontWeight:    FontWeight.w700,
                      color:         Colors.white70,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    workoutName,
                    style: const TextStyle(
                      fontSize:   14,
                      fontWeight: FontWeight.w700,
                      color:      Colors.white,
                    ),
                    maxLines:  1,
                    overflow:  TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              timeStr,
              style: const TextStyle(
                fontSize:   16,
                fontWeight: FontWeight.w800,
                color:      Colors.white,
                fontVariations: [FontVariation('wght', 700)],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder:   (_, __) => Opacity(
      opacity: _anim.value,
      child:   Container(
        width:  8, height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF4ADE80),
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// PLACEHOLDER PAGES (to be implemented)
// ─────────────────────────────────────────────────────────────
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutActive = ref.watch(activeWorkoutProvider).isActive;

    return Scaffold(
      appBar: AppBar(
        title: const Text('IronLog'),
        actions: [
          const SyncStatusIndicator(),
          const SizedBox(width: 8),
          IconButton(
            icon:      const Icon(Icons.settings_outlined),
            onPressed: () => context.go(Routes.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Quick start card
          _QuickStartCard(isWorkoutActive: workoutActive),
          const SizedBox(height: 16),
          // Recent workouts summary
          const _RecentWorkoutsCard(),
          const SizedBox(height: 16),
          // Active program progress
          const _ProgramProgressCard(),
          const SizedBox(height: 16),
          // AI recommendations
          const _AIRecommendationsCard(),
          const SizedBox(height: 8),
          // Banner ad (not during workout)
          if (!workoutActive)
            const AdBannerWidget(placement: AdPlacement.dashboard),
        ],
      ),
    );
  }
}

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard({required this.isWorkoutActive});
  final bool isWorkoutActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E40AF), Color(0xFF2563EB)],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isWorkoutActive ? 'Workout in Progress' : _getGreeting(),
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            isWorkoutActive ? 'Continue where you left off' : "Let's train!",
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => context.go(
                    isWorkoutActive ? Routes.activeWorkout : Routes.activeWorkout,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF2563EB),
                    minimumSize:    const Size(0, 48),
                  ),
                  child: Text(
                    isWorkoutActive ? 'Resume Workout' : 'Start Workout',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (!isWorkoutActive) ...[
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => context.go(Routes.programs),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('Programs'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning 💪';
    if (hour < 17) return 'Good afternoon 🏋️';
    return 'Good evening 🌙';
  }
}

class _RecentWorkoutsCard extends StatelessWidget {
  const _RecentWorkoutsCard();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        const Color(0xFF1A1A25),
      borderRadius: BorderRadius.circular(16),
      border:       Border.all(color: const Color(0xFF2A2A35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent Workouts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
            TextButton(onPressed: () => context.go(Routes.workoutHistory), child: const Text('See all')),
          ],
        ),
        const SizedBox(height: 8),
        const Text('No workouts yet. Start training!', style: TextStyle(color: Color(0xFF8B8B9A), fontSize: 13)),
      ],
    ),
  );
}

class _ProgramProgressCard extends StatelessWidget {
  const _ProgramProgressCard();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        const Color(0xFF1A1A25),
      borderRadius: BorderRadius.circular(16),
      border:       Border.all(color: const Color(0xFF2A2A35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Active Program', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.go(Routes.programs),
                icon:  const Icon(Icons.add, size: 16),
                label: const Text('Start a Program'),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2563EB), side: const BorderSide(color: Color(0xFF2563EB))),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _AIRecommendationsCard extends StatelessWidget {
  const _AIRecommendationsCard();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color:        const Color(0xFF1A1A25),
      borderRadius: BorderRadius.circular(16),
      border:       Border.all(color: const Color(0xFF2A2A35)),
    ),
    child: Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color:        const Color(0xFF7C3AED).withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.psychology_outlined, color: Color(0xFF7C3AED), size: 24),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI Coach', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              Text('Log more workouts for personalized recommendations.', style: TextStyle(fontSize: 12, color: Color(0xFF8B8B9A))),
            ],
          ),
        ),
      ],
    ),
  );
}

// Stub pages
class WorkoutHistoryPage extends StatelessWidget {
  const WorkoutHistoryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('History')), body: const AdBannerWidget(placement: AdPlacement.workoutHistory));
}
class WorkoutDetailPage extends StatelessWidget {
  const WorkoutDetailPage({super.key, required this.workoutId});
  final String workoutId;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('Workout $workoutId')));
}
class ProgramsPage extends StatelessWidget {
  const ProgramsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Programs')));
}
class ProgramDetailPage extends StatelessWidget {
  const ProgramDetailPage({super.key, required this.programId});
  final String programId;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('Program $programId')));
}
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Profile')));
}
class WorkoutCompletePage extends StatelessWidget {
  const WorkoutCompletePage({super.key, this.workout});
  final dynamic workout;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Workout Complete!')),
    body: const AdBannerWidget(placement: AdPlacement.workoutComplete),
  );
}
class ExerciseLibraryPage extends StatelessWidget {
  const ExerciseLibraryPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Exercises')),
    body: const AdBannerWidget(placement: AdPlacement.exerciseLibrary),
  );
}
class ExerciseDetailPage extends StatelessWidget {
  const ExerciseDetailPage({super.key, required this.exerciseId});
  final String exerciseId;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('Exercise $exerciseId')));
}
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Settings')));
}
class PlateCalculatorPage extends StatelessWidget {
  const PlateCalculatorPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Plate Calculator')));
}
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Sign In')));
}
class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Create Account')));
}
