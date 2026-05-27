// ─────────────────────────────────────────────────────────────
// PROGRESSION SCRIPTING ENGINE
// Liftosaur-inspired DSL for custom workout progression logic.
//
// Example scripts:
//   if (completedReps >= targetReps) { weight += 2.5; }
//   if (failedSets >= 2) { weight = weight * 0.9; }
//   sets = completedReps >= targetReps * 0.9 ? sets + 1 : sets;
// ─────────────────────────────────────────────────────────────

export interface ScriptContext {
  // Current session
  weight:         number;
  sets:           number;
  reps:           number;        // Target reps
  completedReps:  number;        // Actual reps in last set
  completedSets:  number;        // Sets completed this session
  failedSets:     number;        // Sets where reps < target
  rpe?:           number;        // Logged RPE

  // Program variables (persist between sessions)
  week:           number;        // Current program week
  day:            number;        // Current program day
  sessionCount:   number;        // Total sessions for this exercise

  // History
  lastWeight:     number;        // Weight used last session
  lastReps:       number;        // Reps achieved last session
  lastSets:       number;        // Sets completed last session
  pr1RM:          number;        // Personal record estimated 1RM

  // Helpers
  percentOf1RM:   (pct: number) => number;
  roundToPlates:  (weight: number, barWeight?: number) => number;
  deloadWeight:   (pct?: number) => number;
}

export interface ScriptResult {
  weight:  number;
  sets:    number;
  reps:    number;
  notes?:  string;
  error?:  string;
}

export interface ScriptValidation {
  valid:    boolean;
  errors:   string[];
  warnings: string[];
}

// ─────────────────────────────────────────────────────────────
// BUILT-IN PROGRESSION SCRIPTS
// ─────────────────────────────────────────────────────────────
export const BUILT_IN_SCRIPTS: Record<string, string> = {
  linear_progression: `
// Linear Progression: Add weight each successful session
if (completedReps >= reps && completedSets >= sets) {
  weight = weight + 2.5;
  notes = "Great work! Added 2.5kg.";
} else if (failedSets >= 2) {
  weight = weight * 0.9;
  notes = "Reduced load for recovery.";
}`,

  double_progression: `
// Double Progression: Increase reps first, then weight
if (completedReps >= 12 && completedSets >= sets) {
  weight = weight + 2.5;
  reps = 8;
  notes = "Top of rep range hit! Increased weight.";
} else if (completedReps >= reps && completedSets >= sets) {
  reps = reps + 1;
  notes = "Add 1 rep next session.";
}`,

  rpe_based: `
// RPE-Based: Adjust weight to hit target RPE of 8
if (rpe != null) {
  if (rpe > 9.0) {
    weight = weight * 0.95;
    notes = "High RPE — reducing load slightly.";
  } else if (rpe < 7.0) {
    weight = weight * 1.05;
    notes = "Low RPE — ready for more weight!";
  }
}`,

  percentage_wave: `
// Wave Loading: Cycle through percentages each week
var pct = 0;
if (week % 4 == 1) { pct = 0.75; }
else if (week % 4 == 2) { pct = 0.80; }
else if (week % 4 == 3) { pct = 0.85; }
else { // Deload week
  pct = 0.60;
  notes = "Deload week — focus on technique.";
}
weight = roundToPlates(percentOf1RM(pct));`,

  daily_undulating: `
// Daily Undulating Periodization (DUP)
if (day == 1) {
  reps = 5;
  weight = roundToPlates(percentOf1RM(0.80));
  notes = "Heavy day (80% 1RM)";
} else if (day == 2) {
  reps = 8;
  weight = roundToPlates(percentOf1RM(0.72));
  notes = "Moderate day (72% 1RM)";
} else {
  reps = 12;
  weight = roundToPlates(percentOf1RM(0.65));
  notes = "Volume day (65% 1RM)";
}`,

  texas_method: `
// Texas Method: Volume, Recovery, Intensity cycle
if (day == 1) {
  // Volume Day: 5×5 at 90% of intensity weight
  sets = 5;
  reps = 5;
  weight = roundToPlates(lastWeight * 0.90);
  notes = "Volume Day — 5x5 at 90%";
} else if (day == 2) {
  // Recovery Day: 2×5 at 80%
  sets = 2;
  reps = 5;
  weight = roundToPlates(lastWeight * 0.80);
  notes = "Recovery Day — light work";
} else {
  // Intensity Day: 1×5 PR attempt
  sets = 1;
  reps = 5;
  weight = completedReps >= 5 ? lastWeight + 2.5 : lastWeight;
  notes = "Intensity Day — PR attempt";
}`,

  531: `
// 5/3/1 Program by Jim Wendler
var trainingMax = percentOf1RM(0.90);
var pct = 0;
var targetReps = 0;
if (week % 4 == 1) { pct = 0.65; targetReps = 5; }
else if (week % 4 == 2) { pct = 0.70; targetReps = 3; }
else if (week % 4 == 3) { pct = 0.75; targetReps = 5; }
else { // Deload
  pct = 0.60; targetReps = 5;
  notes = "5/3/1 Deload week";
}
// Last set is AMRAP
if (completedSets == sets - 1) {
  reps = 0; // AMRAP — go for max
  notes = (notes || "") + " — AMRAP on last set!";
} else {
  reps = targetReps;
}
weight = roundToPlates(trainingMax * pct);`,
};

// ─────────────────────────────────────────────────────────────
// SCRIPT ENGINE
// ─────────────────────────────────────────────────────────────
export class ProgressionScriptEngine {

  // ── RUN SCRIPT ────────────────────────────────────────────────
  execute(script: string, context: ScriptContext): ScriptResult {
    try {
      const safeContext = this._buildSafeContext(context);
      const wrappedScript = this._wrapScript(script);
      const fn = new Function(...Object.keys(safeContext), wrappedScript);
      fn(...Object.values(safeContext));

      return {
        weight: safeContext._state.weight,
        sets:   safeContext._state.sets,
        reps:   safeContext._state.reps,
        notes:  safeContext._state.notes,
      };
    } catch (err) {
      return {
        weight: context.weight,
        sets:   context.sets,
        reps:   context.reps,
        error:  `Script error: ${err instanceof Error ? err.message : String(err)}`,
      };
    }
  }

  // ── VALIDATE SCRIPT ──────────────────────────────────────────
  validate(script: string): ScriptValidation {
    const errors:   string[] = [];
    const warnings: string[] = [];

    // Check for dangerous patterns
    const DANGEROUS_PATTERNS = [
      /\beval\s*\(/,
      /\bFunction\s*\(/,
      /\brequire\s*\(/,
      /\bimport\s/,
      /\bprocess\./,
      /\b__proto__\b/,
      /\bprototype\b/,
      /\bwindow\b/,
      /\bdocument\b/,
      /\bfetch\b/,
      /\bXMLHttpRequest\b/,
    ];

    for (const pattern of DANGEROUS_PATTERNS) {
      if (pattern.test(script)) {
        errors.push(`Forbidden pattern: ${pattern.source}`);
      }
    }

    // Check for infinite loops (while without break, unbounded for)
    if (/while\s*\(\s*true\s*\)/.test(script) && !/break/.test(script)) {
      errors.push('Potential infinite loop: while(true) without break');
    }

    // Syntax check via Function constructor
    if (errors.length === 0) {
      try {
        const safeContext = this._buildSafeContext(this._defaultContext());
        new Function(...Object.keys(safeContext), this._wrapScript(script));
      } catch (e) {
        errors.push(`Syntax error: ${e instanceof Error ? e.message : String(e)}`);
      }
    }

    // Warnings
    if (!script.includes('weight') && !script.includes('reps') && !script.includes('sets')) {
      warnings.push('Script does not modify weight, reps, or sets');
    }
    if (script.length > 2000) {
      warnings.push('Script is very long — consider breaking into smaller scripts');
    }

    return { valid: errors.length === 0, errors, warnings };
  }

  // ── SIMULATE ─────────────────────────────────────────────────
  simulate(
    script:  string,
    context: ScriptContext,
    weeks:   number = 12,
  ): { week: number; weight: number; sets: number; reps: number; notes?: string }[] {
    const results = [];
    let ctx = { ...context };

    for (let w = 1; w <= weeks; w++) {
      ctx.week = w;
      const result = this.execute(script, ctx);
      results.push({ week: w, ...result });

      // Update context for next week
      ctx.lastWeight    = ctx.weight;
      ctx.lastReps      = ctx.reps;
      ctx.weight        = result.weight;
      ctx.reps          = result.reps;
      ctx.sets          = result.sets;
      ctx.completedReps = result.reps; // Assume successful
      ctx.completedSets = result.sets;
      ctx.failedSets    = 0;
      ctx.sessionCount++;
    }

    return results;
  }

  // ── INTERNAL ─────────────────────────────────────────────────
  private _wrapScript(script: string): string {
    // Wrap in a function that uses a shared state object
    return `
      var weight        = _state.weight;
      var sets          = _state.sets;
      var reps          = _state.reps;
      var completedReps = _state.completedReps;
      var completedSets = _state.completedSets;
      var failedSets    = _state.failedSets;
      var rpe           = _state.rpe;
      var week          = _state.week;
      var day           = _state.day;
      var sessionCount  = _state.sessionCount;
      var lastWeight    = _state.lastWeight;
      var lastReps      = _state.lastReps;
      var lastSets      = _state.lastSets;
      var pr1RM         = _state.pr1RM;
      var notes         = _state.notes;

      ${script}

      _state.weight = weight;
      _state.sets   = sets;
      _state.reps   = reps;
      _state.notes  = notes;
    `;
  }

  private _buildSafeContext(context: ScriptContext) {
    const state = {
      weight:        context.weight,
      sets:          context.sets,
      reps:          context.reps,
      completedReps: context.completedReps,
      completedSets: context.completedSets,
      failedSets:    context.failedSets,
      rpe:           context.rpe ?? null,
      week:          context.week,
      day:           context.day,
      sessionCount:  context.sessionCount,
      lastWeight:    context.lastWeight,
      lastReps:      context.lastReps,
      lastSets:      context.lastSets,
      pr1RM:         context.pr1RM,
      notes:         undefined as string | undefined,
    };

    return {
      _state: state,
      percentOf1RM:  context.percentOf1RM,
      roundToPlates: context.roundToPlates,
      deloadWeight:  context.deloadWeight,
      Math,
      // Utility functions
      clamp: (val: number, min: number, max: number) =>
        Math.min(Math.max(val, min), max),
      lerp: (a: number, b: number, t: number) =>
        a + (b - a) * t,
    };
  }

  private _defaultContext(): ScriptContext {
    return {
      weight: 100, sets: 3, reps: 5,
      completedReps: 5, completedSets: 3, failedSets: 0,
      rpe: 8, week: 1, day: 1, sessionCount: 1,
      lastWeight: 97.5, lastReps: 5, lastSets: 3, pr1RM: 130,
      percentOf1RM: (pct) => 130 * pct,
      roundToPlates: (w) => Math.round(w / 2.5) * 2.5,
      deloadWeight:  (pct = 0.6) => 100 * pct,
    };
  }
}

// ─────────────────────────────────────────────────────────────
// FLUTTER INTEGRATION — Dart version of the engine
// This mirrors the TypeScript logic for offline-first use
// ─────────────────────────────────────────────────────────────
/*
// lib/core/utils/progression_engine.dart

class ProgressionEngine {
  static const builtInScripts = {
    'linear_progression': '''
if (completedReps >= reps && completedSets >= sets) {
  weight = weight + 2.5;
}''',
    'double_progression': '''
if (completedReps >= 12 && completedSets >= sets) {
  weight = weight + 2.5;
  reps = 8;
} else if (completedReps >= reps) {
  reps = reps + 1;
}''',
  };

  /// Execute a progression script against a context.
  /// For safety, we interpret a simplified DSL subset in Dart.
  static ProgressionResult execute(
    String script,
    Map<String, dynamic> context,
  ) {
    // In production: implement a proper DSL parser or use dart_eval
    // For MVP: support a set of predefined patterns
    final result = Map<String, dynamic>.from(context);
    
    // Pattern matching for common progression patterns
    if (script.contains('completedReps >= reps') && script.contains('weight += ')) {
      final regex = RegExp(r'weight \+= ([\d.]+)');
      final match = regex.firstMatch(script);
      if (match != null) {
        final increment = double.parse(match.group(1)!);
        if ((context['completedReps'] as int) >= (context['reps'] as int)) {
          result['weight'] = (context['weight'] as double) + increment;
        }
      }
    }
    
    return ProgressionResult(
      weight: result['weight'],
      sets:   result['sets'],
      reps:   result['reps'],
    );
  }
}

class ProgressionResult {
  final double weight;
  final int sets;
  final int reps;
  final String? notes;
  const ProgressionResult({required this.weight, required this.sets, required this.reps, this.notes});
}
*/
