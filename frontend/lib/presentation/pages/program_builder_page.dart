import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/entities/entities.dart';
import '../themes/app_theme.dart';
import '../widgets/ad_banner_widget.dart';

// ─────────────────────────────────────────────────────────────
// PROGRAM BUILDER PAGE
// ─────────────────────────────────────────────────────────────
class ProgramBuilderPage extends ConsumerStatefulWidget {
  const ProgramBuilderPage({super.key, this.existingProgram});
  final Program? existingProgram;

  @override
  ConsumerState<ProgramBuilderPage> createState() => _ProgramBuilderPageState();
}

class _ProgramBuilderPageState extends ConsumerState<ProgramBuilderPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Program state
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  ProgramType  _type         = ProgramType.custom;
  int          _daysPerWeek  = 3;
  int          _durationWeeks = 8;
  List<ProgramDay> _days     = [];
  bool         _isScriptMode = false;
  String       _globalScript = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.existingProgram != null) {
      _loadExistingProgram();
    } else {
      _initDefaultDays();
    }
  }

  void _loadExistingProgram() {
    final p = widget.existingProgram!;
    _nameCtrl.text    = p.name;
    _descCtrl.text    = p.description;
    _type             = p.type;
    _daysPerWeek      = p.daysPerWeek;
    _durationWeeks    = p.durationWeeks;
    _days             = p.days.toList();
    _globalScript     = p.progressionScript ?? '';
  }

  void _initDefaultDays() {
    _days = List.generate(_daysPerWeek, (i) => ProgramDay(
      id:         'day_${i + 1}',
      programId:  '',
      dayNumber:  i + 1,
      name:       'Day ${i + 1}',
      exercises:  [],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        title: Text(widget.existingProgram != null ? 'Edit Program' : 'New Program'),
        actions: [
          // Script mode toggle (premium)
          Consumer(builder: (context, ref, _) {
            final isPremium = ref.watch(isPremiumProvider);
            return IconButton(
              icon: Icon(
                _isScriptMode ? Icons.view_list : Icons.code,
                color: _isScriptMode ? AppTheme.primaryBlue : AppTheme.darkSubtext,
              ),
              tooltip: isPremium ? 'Toggle Script Mode' : 'Script Mode (Pro)',
              onPressed: () {
                if (!isPremium) {
                  _showUpgradePrompt();
                  return;
                }
                setState(() => _isScriptMode = !_isScriptMode);
              },
            );
          }),
          // Save
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Setup'), Tab(text: 'Days')],
          indicatorColor: AppTheme.primaryBlue,
          labelColor:     AppTheme.primaryBlue,
          unselectedLabelColor: AppTheme.darkSubtext,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _SetupTab(
            nameCtrl:       _nameCtrl,
            descCtrl:       _descCtrl,
            type:           _type,
            daysPerWeek:    _daysPerWeek,
            durationWeeks:  _durationWeeks,
            onTypeChanged:  (t) => setState(() => _type = t),
            onDaysChanged:  (d) {
              setState(() {
                _daysPerWeek = d;
                _initDefaultDays();
              });
            },
            onWeeksChanged: (w) => setState(() => _durationWeeks = w),
          ),
          _DaysTab(
            days:           _days,
            isScriptMode:   _isScriptMode,
            globalScript:   _globalScript,
            onDaysChanged:  (days) => setState(() => _days = days),
            onScriptChanged:(s)    => setState(() => _globalScript = s),
          ),
        ],
      ),
    );
  }

  void _save() {
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Program name is required')),
      );
      return;
    }
    // Save via repository
    Navigator.pop(context);
  }

  void _showUpgradePrompt() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UpgradePromptSheet(
        feature: 'Custom Scripting',
        description: 'Write custom progression formulas to auto-adjust weight, reps, and sets.',
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SETUP TAB
// ─────────────────────────────────────────────────────────────
class _SetupTab extends StatelessWidget {
  const _SetupTab({
    required this.nameCtrl,
    required this.descCtrl,
    required this.type,
    required this.daysPerWeek,
    required this.durationWeeks,
    required this.onTypeChanged,
    required this.onDaysChanged,
    required this.onWeeksChanged,
  });

  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final ProgramType  type;
  final int          daysPerWeek;
  final int          durationWeeks;
  final ValueChanged<ProgramType> onTypeChanged;
  final ValueChanged<int>         onDaysChanged;
  final ValueChanged<int>         onWeeksChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Program Name',
            hintText:  'e.g. My 5x5 Program',
            prefixIcon: Icon(Icons.fitness_center_rounded),
          ),
        ).animate().fadeIn(duration: 200.ms),
        const SizedBox(height: 16),
        TextField(
          controller: descCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description',
            hintText:  'What is this program for?',
            prefixIcon: Icon(Icons.notes_rounded),
          ),
        ).animate().fadeIn(duration: 200.ms, delay: 50.ms),
        const SizedBox(height: 24),

        // Program type
        const _SectionHeader('Program Type'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: ProgramType.values.map((t) {
            final selected = t == type;
            return FilterChip(
              label:    Text(_programTypeLabel(t)),
              selected: selected,
              onSelected: (_) => onTypeChanged(t),
              selectedColor: AppTheme.primaryBlue.withOpacity(0.2),
              checkmarkColor: AppTheme.primaryBlue,
              labelStyle: TextStyle(
                color:      selected ? AppTheme.primaryBlue : AppTheme.darkText,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            );
          }).toList(),
        ).animate().fadeIn(duration: 200.ms, delay: 100.ms),
        const SizedBox(height: 24),

        // Days per week
        const _SectionHeader('Days Per Week'),
        const SizedBox(height: 12),
        Row(
          children: List.generate(7, (i) {
            final d = i + 1;
            final selected = d == daysPerWeek;
            return Expanded(
              child: GestureDetector(
                onTap: () => onDaysChanged(d),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 44,
                  decoration: BoxDecoration(
                    color:        selected ? AppTheme.primaryBlue : AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(8),
                    border:       Border.all(
                      color: selected ? AppTheme.primaryBlue : AppTheme.darkBorder,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$d',
                      style: TextStyle(
                        fontSize:   15,
                        fontWeight: FontWeight.w700,
                        color:      selected ? Colors.white : AppTheme.darkSubtext,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ).animate().fadeIn(duration: 200.ms, delay: 150.ms),
        const SizedBox(height: 24),

        // Duration
        const _SectionHeader('Duration (weeks)'),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('0', style: TextStyle(color: AppTheme.darkSubtext, fontSize: 13)),
            Expanded(
              child: Slider(
                value:    durationWeeks.toDouble(),
                min:      0,
                max:      52,
                divisions: 52,
                activeColor: AppTheme.primaryBlue,
                inactiveColor: AppTheme.darkBorder,
                onChanged: (v) => onWeeksChanged(v.round()),
              ),
            ),
            Text(
              durationWeeks == 0 ? '∞' : '${durationWeeks}w',
              style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ).animate().fadeIn(duration: 200.ms, delay: 200.ms),

        const SizedBox(height: 24),
        const AdBannerWidget(placement: AdPlacement.dashboard),
      ],
    );
  }

  String _programTypeLabel(ProgramType t) => switch (t) {
    ProgramType.powerlifting     => '🏋️ Powerlifting',
    ProgramType.bodybuilding     => '💪 Bodybuilding',
    ProgramType.strengthEndurance=> '⚡ Strength+Endurance',
    ProgramType.hiit             => '🔥 HIIT',
    ProgramType.generalFitness   => '🏃 General Fitness',
    ProgramType.olympic          => '🥇 Olympic',
    ProgramType.custom           => '✏️ Custom',
  };
}

// ─────────────────────────────────────────────────────────────
// DAYS TAB
// ─────────────────────────────────────────────────────────────
class _DaysTab extends StatefulWidget {
  const _DaysTab({
    required this.days,
    required this.isScriptMode,
    required this.globalScript,
    required this.onDaysChanged,
    required this.onScriptChanged,
  });

  final List<ProgramDay> days;
  final bool             isScriptMode;
  final String           globalScript;
  final ValueChanged<List<ProgramDay>> onDaysChanged;
  final ValueChanged<String>           onScriptChanged;

  @override
  State<_DaysTab> createState() => _DaysTabState();
}

class _DaysTabState extends State<_DaysTab> {
  int _selectedDay = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.days.isEmpty) {
      return const Center(
        child: Text('Configure days per week in Setup tab', style: TextStyle(color: AppTheme.darkSubtext)),
      );
    }

    return Column(
      children: [
        // Day selector
        _DaySelector(
          days:        widget.days,
          selectedDay: _selectedDay,
          onDaySelected: (i) => setState(() => _selectedDay = i),
        ),

        // Day content
        Expanded(
          child: IndexedStack(
            index: _selectedDay,
            children: widget.days.asMap().entries.map((entry) {
              return _DayEditor(
                day:            entry.value,
                isScriptMode:   widget.isScriptMode,
                globalScript:   widget.globalScript,
                onDayChanged:   (updatedDay) {
                  final days = [...widget.days];
                  days[entry.key] = updatedDay;
                  widget.onDaysChanged(days);
                },
                onScriptChanged: widget.onScriptChanged,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.days,
    required this.selectedDay,
    required this.onDaySelected,
  });

  final List<ProgramDay> days;
  final int              selectedDay;
  final ValueChanged<int> onDaySelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color:  AppTheme.darkSurface,
      child:  ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: days.length,
        itemBuilder: (_, i) {
          final day      = days[i];
          final selected = i == selectedDay;
          return GestureDetector(
            onTap: () => onDaySelected(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color:        selected ? AppTheme.primaryBlue : AppTheme.darkCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  day.isRestDay == true ? '😴 Rest' : day.name,
                  style: TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w600,
                    color:      selected ? Colors.white : AppTheme.darkSubtext,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DayEditor extends StatelessWidget {
  const _DayEditor({
    required this.day,
    required this.isScriptMode,
    required this.globalScript,
    required this.onDayChanged,
    required this.onScriptChanged,
  });

  final ProgramDay day;
  final bool       isScriptMode;
  final String     globalScript;
  final ValueChanged<ProgramDay>    onDayChanged;
  final ValueChanged<String>        onScriptChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Day name editor
        _DayNameRow(
          day:         day,
          onChanged:   (name) => onDayChanged(day.copyWith(name: name)),
          onRestToggle:() => onDayChanged(day.copyWith(isRestDay: !(day.isRestDay ?? false))),
        ),
        const SizedBox(height: 16),

        if (day.isRestDay != true) ...[
          // Exercise list
          ...day.exercises.asMap().entries.map((entry) => _ProgramExerciseCard(
            exercise:   entry.value,
            isScriptMode: isScriptMode,
            onChanged:  (updated) {
              final exercises = [...day.exercises];
              exercises[entry.key] = updated;
              onDayChanged(day.copyWith(exercises: exercises));
            },
            onRemove: () {
              final exercises = [...day.exercises]..removeAt(entry.key);
              onDayChanged(day.copyWith(exercises: exercises));
            },
          ).animate().fadeIn(duration: 200.ms, delay: (entry.key * 50).ms)),

          const SizedBox(height: 12),

          // Add exercise button
          OutlinedButton.icon(
            onPressed: () {}, // Open exercise picker
            icon:  const Icon(Icons.add, size: 18),
            label: const Text('Add Exercise'),
            style: OutlinedButton.styleFrom(
              minimumSize:    const Size(double.infinity, 48),
              foregroundColor: AppTheme.primaryBlue,
              side:           const BorderSide(color: AppTheme.primaryBlue),
            ),
          ),

          // Global script editor (premium)
          if (isScriptMode) ...[
            const SizedBox(height: 20),
            _ScriptEditor(
              script:    globalScript,
              onChanged: onScriptChanged,
            ),
          ],
        ] else ...[
          // Rest day message
          const Center(
            child: Column(
              children: [
                SizedBox(height: 40),
                Icon(Icons.hotel_rounded, size: 48, color: AppTheme.darkSubtext),
                SizedBox(height: 12),
                Text('Rest Day', style: TextStyle(color: AppTheme.darkSubtext, fontSize: 18)),
                SizedBox(height: 8),
                Text('Recovery is part of the program!', style: TextStyle(color: AppTheme.darkSubtext, fontSize: 13)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DayNameRow extends StatelessWidget {
  const _DayNameRow({
    required this.day,
    required this.onChanged,
    required this.onRestToggle,
  });

  final ProgramDay      day;
  final ValueChanged<String> onChanged;
  final VoidCallback    onRestToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: TextEditingController(text: day.name),
            decoration: const InputDecoration(
              hintText: 'Day name (e.g. Squat Day)',
              prefixIcon: Icon(Icons.edit_rounded, size: 18),
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        // Rest day toggle
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          child: IconButton.outlined(
            onPressed: onRestToggle,
            icon: Icon(
              Icons.hotel_rounded,
              color: day.isRestDay == true ? AppTheme.primaryBlue : AppTheme.darkSubtext,
            ),
            style: IconButton.styleFrom(
              side: BorderSide(
                color: day.isRestDay == true ? AppTheme.primaryBlue : AppTheme.darkBorder,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgramExerciseCard extends StatelessWidget {
  const _ProgramExerciseCard({
    required this.exercise,
    required this.isScriptMode,
    required this.onChanged,
    required this.onRemove,
  });

  final ProgramExercise exercise;
  final bool            isScriptMode;
  final ValueChanged<ProgramExercise> onChanged;
  final VoidCallback    onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.exercise.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.darkText),
                ),
              ),
              IconButton(
                icon:      const Icon(Icons.delete_outline, size: 18),
                color:     AppTheme.darkSubtext,
                onPressed: onRemove,
                padding:   EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Sets/Reps/Weight row
          Row(
            children: [
              _CompactField(
                label: 'Sets',
                value: '${exercise.sets}',
                onChanged: (v) => onChanged(exercise.copyWith(sets: int.tryParse(v) ?? exercise.sets)),
              ),
              const SizedBox(width: 8),
              _CompactField(
                label: 'Reps',
                value: exercise.repsScheme,
                onChanged: (v) => onChanged(exercise.copyWith(repsScheme: v)),
                isText: true,
              ),
              const SizedBox(width: 8),
              _CompactField(
                label: 'Load',
                value: exercise.weightScheme ?? 'RPE 8',
                onChanged: (v) => onChanged(exercise.copyWith(weightScheme: v)),
                isText: true,
              ),
              const SizedBox(width: 8),
              _CompactField(
                label: 'Rest',
                value: '${exercise.restSeconds ?? 90}s',
                onChanged: (v) => onChanged(exercise.copyWith(
                  restSeconds: int.tryParse(v.replaceAll('s', '')) ?? exercise.restSeconds,
                )),
              ),
            ],
          ),
          // Script mode: show per-exercise script
          if (isScriptMode) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showScriptEditor(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color:        AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border:       Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.code, size: 14, color: AppTheme.primaryBlue),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        exercise.progressionScript?.isNotEmpty == true
                            ? exercise.progressionScript!.split('\n').first
                            : 'Add progression script...',
                        style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showScriptEditor(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScriptEditorSheet(
        exerciseName: exercise.exercise.name,
        script:       exercise.progressionScript ?? '',
        onSave:       (s) => onChanged(exercise.copyWith(progressionScript: s)),
      ),
    );
  }
}

class _CompactField extends StatelessWidget {
  const _CompactField({required this.label, required this.value, required this.onChanged, this.isText = false});
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool isText;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.darkSubtext, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller:  TextEditingController(text: value),
            onChanged:   onChanged,
            style:       const TextStyle(fontSize: 13, color: AppTheme.darkText),
            keyboardType: isText ? TextInputType.text : TextInputType.number,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScriptEditor extends StatelessWidget {
  const _ScriptEditor({required this.script, required this.onChanged});
  final String script;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Global Progression Script'),
        const SizedBox(height: 4),
        const Text(
          'Runs after every session. Variables: weight, sets, reps, completedReps, failedSets, week, rpe',
          style: TextStyle(fontSize: 11, color: AppTheme.darkSubtext),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.darkBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: TextField(
            controller: TextEditingController(text: script),
            onChanged:  onChanged,
            maxLines:   8,
            style: const TextStyle(
              fontSize: 13,
              color:    AppTheme.darkText,
              fontFamily: 'monospace',
            ),
            decoration: const InputDecoration(
              hintText: '// if (completedReps >= reps) { weight += 2.5; }',
              hintStyle: TextStyle(color: AppTheme.darkSubtext, fontFamily: 'monospace'),
              border:   InputBorder.none,
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScriptEditorSheet extends StatefulWidget {
  const _ScriptEditorSheet({
    required this.exerciseName,
    required this.script,
    required this.onSave,
  });
  final String exerciseName;
  final String script;
  final ValueChanged<String> onSave;

  @override
  State<_ScriptEditorSheet> createState() => _ScriptEditorSheetState();
}

class _ScriptEditorSheetState extends State<_ScriptEditorSheet> {
  late TextEditingController _ctrl;
  String _selectedPreset = '';

  final _presets = [
    ('Linear +2.5kg', 'if (completedReps >= reps && completedSets >= sets) {\n  weight += 2.5;\n}'),
    ('Double Progression', 'if (completedReps >= 12) {\n  weight += 2.5; reps = 8;\n} else if (completedReps >= reps) {\n  reps += 1;\n}'),
    ('Wave (75/80/85%)', 'var pcts = [0.75, 0.80, 0.85, 0.60];\nweight = roundToPlates(percentOf1RM(pcts[(week - 1) % 4]));'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.script);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Script: ${widget.exerciseName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.darkText)),
          const SizedBox(height: 12),
          // Presets
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _presets.map((p) => GestureDetector(
                onTap: () { setState(() { _ctrl.text = p.$2; _selectedPreset = p.$1; }); },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _selectedPreset == p.$1 ? AppTheme.primaryBlue.withOpacity(0.2) : AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _selectedPreset == p.$1 ? AppTheme.primaryBlue : AppTheme.darkBorder),
                  ),
                  child: Text(p.$1, style: const TextStyle(fontSize: 12, color: AppTheme.darkText)),
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines:   6,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: AppTheme.darkText),
            decoration: const InputDecoration(
              hintText: '// Write your progression formula here...',
              hintStyle: TextStyle(color: AppTheme.darkSubtext, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              widget.onSave(_ctrl.text);
              Navigator.pop(context);
            },
            child: const Text('Save Script'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.darkText),
  );
}

class _UpgradePromptSheet extends StatelessWidget {
  const _UpgradePromptSheet({required this.feature, required this.description});
  final String feature;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color:        AppTheme.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium, size: 48, color: Color(0xFFFFD700)),
          const SizedBox(height: 12),
          Text('Unlock $feature', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.darkText)),
          const SizedBox(height: 8),
          Text(description, style: const TextStyle(fontSize: 14, color: AppTheme.darkSubtext), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to paywall
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1A1AFF)),
            child: const Text('Upgrade to Pro'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not now', style: TextStyle(color: AppTheme.darkSubtext)),
          ),
        ],
      ),
    );
  }
}
