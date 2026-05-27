import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../themes/app_theme.dart';
import '../widgets/ad_banner_widget.dart';
import '../blocs/analytics_notifier.dart';

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPeriod = '3M';
  String? _selectedExerciseId;

  final _periods = ['1M', '3M', '6M', '1Y', 'All'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analyticsProvider);

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ─────────────────────────────────────────
          SliverAppBar(
            title: const Text('Analytics'),
            pinned: true,
            backgroundColor: AppTheme.darkBg,
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Strength'),
                Tab(text: 'Volume'),
                Tab(text: 'Body'),
                Tab(text: 'Muscles'),
              ],
              indicatorColor: AppTheme.primaryBlue,
              labelColor:     AppTheme.primaryBlue,
              unselectedLabelColor: AppTheme.darkSubtext,
            ),
          ),

          // ── Period Selector ──────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: _periods.map((p) {
                  final selected = p == _selectedPeriod;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedPeriod = p);
                      ref.read(analyticsProvider.notifier).setPeriod(p);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color:        selected ? AppTheme.primaryBlue : AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(20),
                        border:       Border.all(
                          color: selected ? AppTheme.primaryBlue : AppTheme.darkBorder,
                        ),
                      ),
                      child: Text(
                        p,
                        style: TextStyle(
                          fontSize:   13,
                          fontWeight: FontWeight.w600,
                          color:      selected ? Colors.white : AppTheme.darkSubtext,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Tab Content ──────────────────────────────────────
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _StrengthTab(state: state),
                _VolumeTab(state: state),
                _BodyTab(state: state),
                _MuscleHeatmapTab(state: state),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STRENGTH TAB
// ─────────────────────────────────────────────────────────────
class _StrengthTab extends ConsumerStatefulWidget {
  const _StrengthTab({required this.state});
  final AnalyticsState state;

  @override
  ConsumerState<_StrengthTab> createState() => _StrengthTabState();
}

class _StrengthTabState extends ConsumerState<_StrengthTab> {
  String _selectedExercise = 'ex_squat';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Exercise selector
        _ExerciseSelector(
          selectedId: _selectedExercise,
          onChanged: (id) {
            setState(() => _selectedExercise = id);
            ref.read(analyticsProvider.notifier).loadExerciseHistory(id);
          },
        ),
        const SizedBox(height: 16),

        // e1RM chart
        _ChartCard(
          title: 'Estimated 1RM Progression',
          subtitle: 'Epley formula',
          child: _E1RMChart(dataPoints: widget.state.e1rmData),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1),

        const SizedBox(height: 16),

        // Max weight chart
        _ChartCard(
          title: 'Max Weight',
          subtitle: 'Heaviest set each session',
          child: _LineChart(
            dataPoints: widget.state.maxWeightData,
            color: AppTheme.primaryOrange,
            unit: 'kg',
          ),
        ).animate().fadeIn(duration: 300.ms, delay: 100.ms).slideY(begin: 0.1),

        const SizedBox(height: 16),

        // PR list
        _PRSection(prs: widget.state.recentPRs),

        const SizedBox(height: 16),

        // Ad for free users
        const AdBannerWidget(placement: AdPlacement.analytics),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// E1RM CHART
// ─────────────────────────────────────────────────────────────
class _E1RMChart extends StatefulWidget {
  const _E1RMChart({required this.dataPoints});
  final List<AnalyticsDataPoint> dataPoints;

  @override
  State<_E1RMChart> createState() => _E1RMChartState();
}

class _E1RMChartState extends State<_E1RMChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.dataPoints.isEmpty) {
      return const _EmptyChartPlaceholder(message: 'Log workouts to see your strength progress');
    }

    final spots = widget.dataPoints.asMap().entries.map((e) =>
      FlSpot(e.key.toDouble(), e.value.value),
    ).toList();

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) * 0.95;
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.05;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          clipData: FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTheme.darkBorder,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (val, meta) => Text(
                  '${val.toStringAsFixed(0)}kg',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.darkSubtext,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (spots.length / 4).ceilToDouble(),
                getTitlesWidget: (val, meta) {
                  final idx = val.toInt();
                  if (idx >= widget.dataPoints.length) return const SizedBox();
                  return Text(
                    _formatDate(widget.dataPoints[idx].date),
                    style: const TextStyle(fontSize: 10, color: AppTheme.darkSubtext),
                  );
                },
              ),
            ),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: AppTheme.darkCard,
              getTooltipItems: (spots) => spots.map((s) {
                final point = widget.dataPoints[s.spotIndex];
                return LineTooltipItem(
                  '${point.value.toStringAsFixed(1)}kg\n${_formatDate(point.date)}',
                  const TextStyle(
                    color: AppTheme.darkText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: AppTheme.primaryBlue,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: AppTheme.primaryBlue,
                  strokeWidth: 2,
                  strokeColor: AppTheme.darkBg,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.primaryBlue.withOpacity(0.3),
                    AppTheme.primaryBlue.withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}';
  }
}

// ─────────────────────────────────────────────────────────────
// VOLUME TAB
// ─────────────────────────────────────────────────────────────
class _VolumeTab extends StatelessWidget {
  const _VolumeTab({required this.state});
  final AnalyticsState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Weekly volume bar chart
        _ChartCard(
          title: 'Weekly Training Volume',
          subtitle: 'Total kg lifted per week',
          child: _WeeklyVolumeChart(data: state.weeklyVolumeData),
        ).animate().fadeIn(duration: 300.ms),

        const SizedBox(height: 16),

        // Volume per muscle group
        _ChartCard(
          title: 'Volume by Muscle Group',
          subtitle: 'This week',
          child: _MuscleVolumeChart(data: state.muscleVolumeData),
        ).animate().fadeIn(duration: 300.ms, delay: 100.ms),

        const SizedBox(height: 16),

        // Workout frequency
        _ChartCard(
          title: 'Training Frequency',
          subtitle: 'Workouts per week',
          child: _FrequencyChart(data: state.frequencyData),
        ).animate().fadeIn(duration: 300.ms, delay: 200.ms),
      ],
    );
  }
}

class _WeeklyVolumeChart extends StatelessWidget {
  const _WeeklyVolumeChart({required this.data});
  final List<AnalyticsDataPoint> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const _EmptyChartPlaceholder(message: 'Log workouts to see volume data');
    }

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: data.map((d) => d.value).reduce((a, b) => a > b ? a : b) * 1.2,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTheme.darkBorder, strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                getTitlesWidget: (val, _) => Text(
                  '${(val / 1000).toStringAsFixed(0)}k',
                  style: const TextStyle(fontSize: 10, color: AppTheme.darkSubtext),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (val, _) {
                  final idx = val.toInt();
                  if (idx >= data.length) return const SizedBox();
                  return Text(
                    'W${idx + 1}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.darkSubtext),
                  );
                },
              ),
            ),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: data.asMap().entries.map((e) => BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.value,
                color: AppTheme.primaryBlue,
                width: 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: data.map((d) => d.value).reduce((a, b) => a > b ? a : b) * 1.2,
                  color: AppTheme.darkCard,
                ),
              ),
            ],
          )).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MUSCLE HEATMAP TAB
// ─────────────────────────────────────────────────────────────
class _MuscleHeatmapTab extends StatelessWidget {
  const _MuscleHeatmapTab({required this.state});
  final AnalyticsState state;

  static const _muscles = [
    ('Quads',      MuscleGroup.quads,       Icons.accessibility_new),
    ('Hamstrings', MuscleGroup.hamstrings,  Icons.accessibility_new),
    ('Glutes',     MuscleGroup.glutes,      Icons.accessibility_new),
    ('Back',       MuscleGroup.back,        Icons.accessibility_new),
    ('Chest',      MuscleGroup.chest,       Icons.accessibility_new),
    ('Shoulders',  MuscleGroup.shoulders,   Icons.accessibility_new),
    ('Biceps',     MuscleGroup.biceps,      Icons.accessibility_new),
    ('Triceps',    MuscleGroup.triceps,     Icons.accessibility_new),
    ('Abs',        MuscleGroup.abs,         Icons.accessibility_new),
    ('Calves',     MuscleGroup.calves,      Icons.accessibility_new),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Weekly Volume by Muscle',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.darkText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Recommended: 10-20 sets per muscle per week',
          style: TextStyle(fontSize: 13, color: AppTheme.darkSubtext),
        ),
        const SizedBox(height: 20),
        ..._muscles.map((m) {
          final sets = state.muscleSetCounts[m.$2.name] ?? 0;
          return _MuscleVolumeBar(
            muscle: m.$1,
            sets: sets,
          ).animate().fadeIn(duration: 250.ms, delay: (_muscles.indexOf(m) * 40).ms);
        }),

        const SizedBox(height: 24),

        // Recovery status
        _RecoverySection(state: state),
      ],
    );
  }
}

class _MuscleVolumeBar extends StatelessWidget {
  const _MuscleVolumeBar({required this.muscle, required this.sets});
  final String muscle;
  final int sets;

  @override
  Widget build(BuildContext context) {
    const optimal = 15.0; // sets per week
    final pct = (sets / optimal).clamp(0.0, 1.5);
    final color = pct < 0.5
        ? AppTheme.accentRed.withOpacity(0.8)
        : pct < 0.8
            ? AppTheme.primaryOrange
            : pct <= 1.0
                ? AppTheme.accentGreen
                : AppTheme.primaryOrange; // Overreaching

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                muscle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.darkText,
                ),
              ),
              Text(
                '$sets sets',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:            pct.clamp(0.0, 1.0),
              backgroundColor:  AppTheme.darkCard,
              valueColor:       AlwaysStoppedAnimation(color),
              minHeight:        8,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BODY TAB
// ─────────────────────────────────────────────────────────────
class _BodyTab extends StatelessWidget {
  const _BodyTab({required this.state});
  final AnalyticsState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ChartCard(
          title: 'Bodyweight',
          subtitle: 'kg over time',
          child: _LineChart(
            dataPoints: state.bodyweightData,
            color: AppTheme.accentGreen,
            unit: 'kg',
          ),
        ).animate().fadeIn(duration: 300.ms),
        const SizedBox(height: 16),

        // Stats summary
        _StatsSummaryGrid(state: state)
            .animate().fadeIn(duration: 300.ms, delay: 100.ms),

        const SizedBox(height: 16),

        // Training consistency calendar heatmap
        _ConsistencyCalendar(workoutDates: state.workoutDates)
            .animate().fadeIn(duration: 300.ms, delay: 200.ms),

        const SizedBox(height: 16),
        const AdBannerWidget(placement: AdPlacement.analytics),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STATS SUMMARY GRID
// ─────────────────────────────────────────────────────────────
class _StatsSummaryGrid extends StatelessWidget {
  const _StatsSummaryGrid({required this.state});
  final AnalyticsState state;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 1.4,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _StatCard(
          label: 'Total Workouts',
          value: '${state.totalWorkouts}',
          icon: Icons.fitness_center,
          color: AppTheme.primaryBlue,
        ),
        _StatCard(
          label: 'Total Volume',
          value: '${(state.totalVolume / 1000).toStringAsFixed(1)}t',
          icon: Icons.trending_up,
          color: AppTheme.accentGreen,
        ),
        _StatCard(
          label: 'Avg Duration',
          value: '${state.avgDurationMinutes}m',
          icon: Icons.timer_outlined,
          color: AppTheme.primaryOrange,
        ),
        _StatCard(
          label: 'PRs This Month',
          value: '${state.monthlyPRCount}',
          icon: Icons.emoji_events_outlined,
          color: AppTheme.accentPurple,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.darkSubtext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CONSISTENCY CALENDAR
// ─────────────────────────────────────────────────────────────
class _ConsistencyCalendar extends StatelessWidget {
  const _ConsistencyCalendar({required this.workoutDates});
  final List<DateTime> workoutDates;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Training Consistency',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.darkText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${workoutDates.length} workouts in the last 12 weeks',
            style: const TextStyle(fontSize: 12, color: AppTheme.darkSubtext),
          ),
          const SizedBox(height: 16),
          // GitHub-style contribution grid
          _ContributionGrid(workoutDates: workoutDates),
        ],
      ),
    );
  }
}

class _ContributionGrid extends StatelessWidget {
  const _ContributionGrid({required this.workoutDates});
  final List<DateTime> workoutDates;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 84)); // 12 weeks
    final workoutSet = workoutDates
        .map((d) => '${d.year}-${d.month}-${d.day}')
        .toSet();

    return Row(
      children: List.generate(12, (weekIdx) {
        return Expanded(
          child: Column(
            children: List.generate(7, (dayIdx) {
              final date = start.add(Duration(days: weekIdx * 7 + dayIdx));
              if (date.isAfter(now)) return const SizedBox(height: 10);
              final key = '${date.year}-${date.month}-${date.day}';
              final hasWorkout = workoutSet.contains(key);
              return Container(
                margin: const EdgeInsets.all(1.5),
                height: 10,
                decoration: BoxDecoration(
                  color: hasWorkout
                      ? AppTheme.primaryBlue
                      : AppTheme.darkBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.darkText)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.darkSubtext)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.dataPoints, required this.color, required this.unit});
  final List<AnalyticsDataPoint> dataPoints;
  final Color color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    if (dataPoints.isEmpty) {
      return const _EmptyChartPlaceholder(message: 'No data yet');
    }
    final spots = dataPoints.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
        .toList();

    return SizedBox(
      height: 180,
      child: LineChart(LineChartData(
        gridData:   FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          leftTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end:   Alignment.bottomCenter,
                colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
              ),
            ),
          ),
        ],
      )),
    );
  }
}

class _EmptyChartPlaceholder extends StatelessWidget {
  const _EmptyChartPlaceholder({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart_rounded, size: 48, color: AppTheme.darkBorder),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: AppTheme.darkSubtext, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _ExerciseSelector extends StatelessWidget {
  const _ExerciseSelector({required this.selectedId, required this.onChanged});
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // Simplified — in production, open exercise picker sheet
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.darkBorder),
        ),
        child: const Row(
          children: [
            Icon(Icons.fitness_center, color: AppTheme.primaryBlue, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Barbell Back Squat',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.darkText),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: AppTheme.darkSubtext),
          ],
        ),
      ),
    );
  }
}

class _PRSection extends StatelessWidget {
  const _PRSection({required this.prs});
  final List<PersonalRecord> prs;

  @override
  Widget build(BuildContext context) {
    if (prs.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 20),
              SizedBox(width: 8),
              Text('Recent PRs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.darkText)),
            ],
          ),
          const SizedBox(height: 12),
          ...prs.take(5).map((pr) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(pr.exerciseName, style: const TextStyle(fontSize: 14, color: AppTheme.darkText))),
                Text(
                  '${pr.weight.toStringAsFixed(1)}kg × ${pr.reps}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFFFD700)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _RecoverySection extends StatelessWidget {
  const _RecoverySection({required this.state});
  final AnalyticsState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recovery Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.darkText)),
          const SizedBox(height: 12),
          const Text('Based on recent training volume and frequency', style: TextStyle(fontSize: 12, color: AppTheme.darkSubtext)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _RecoveryIndicator(muscle: 'Upper Body', status: state.upperBodyRecovery)),
              const SizedBox(width: 12),
              Expanded(child: _RecoveryIndicator(muscle: 'Lower Body', status: state.lowerBodyRecovery)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecoveryIndicator extends StatelessWidget {
  const _RecoveryIndicator({required this.muscle, required this.status});
  final String muscle;
  final double status; // 0-1, 1 = fully recovered

  @override
  Widget build(BuildContext context) {
    final color = status > 0.7 ? AppTheme.accentGreen : status > 0.4 ? AppTheme.primaryOrange : AppTheme.accentRed;
    final label = status > 0.7 ? 'Recovered' : status > 0.4 ? 'Recovering' : 'Fatigued';
    return Column(
      children: [
        Text(muscle, style: const TextStyle(fontSize: 13, color: AppTheme.darkSubtext)),
        const SizedBox(height: 8),
        CircularProgressIndicator(
          value: status,
          backgroundColor: AppTheme.darkBorder,
          valueColor: AlwaysStoppedAnimation(color),
          strokeWidth: 6,
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _MuscleVolumeChart extends StatelessWidget {
  const _MuscleVolumeChart({required this.data});
  final Map<String, double> data;
  @override
  Widget build(BuildContext context) => const SizedBox(height: 100); // Simplified
}

class _FrequencyChart extends StatelessWidget {
  const _FrequencyChart({required this.data});
  final List<AnalyticsDataPoint> data;
  @override
  Widget build(BuildContext context) => const SizedBox(height: 100); // Simplified
}
