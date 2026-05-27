import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

// ─────────────────────────────────────────────────────────────
// AI COACHING ENGINE
// Handles: progression suggestions, plateau detection,
// deload recommendations, program generation, recovery advice
// ─────────────────────────────────────────────────────────────

export interface TrainingProfile {
  userId:         string;
  trainingAge:    number;    // Years
  mainGoal:       'strength' | 'hypertrophy' | 'endurance' | 'weightloss';
  daysPerWeek:    number;
  recentWorkouts: RecentWorkout[];
  exercisePRs:    Record<string, ExercisePR>;
}

export interface RecentWorkout {
  date:          Date;
  exercises:     WorkoutExerciseSummary[];
  durationMin:   number;
  rpe?:          number;
}

export interface WorkoutExerciseSummary {
  exerciseId:   string;
  exerciseName: string;
  muscleGroup:  string;
  sets:         number;
  maxWeight:    number;
  totalVolume:  number;
  avgRpe?:      number;
}

export interface ExercisePR {
  weight:       number;
  reps:         number;
  estimated1RM: number;
  date:         Date;
}

export interface ProgressionSuggestion {
  exerciseId:     string;
  exerciseName:   string;
  recommendation: 'increase_weight' | 'increase_reps' | 'deload' | 'maintain' | 'plateau_detected';
  currentWeight:  number;
  suggestedWeight?: number;
  currentReps?:   number;
  suggestedReps?: number;
  reason:         string;
  confidence:     number;   // 0-1
}

export interface ProgramTemplate {
  name:         string;
  description:  string;
  daysPerWeek:  number;
  weeks:        number;
  days:         ProgramDay[];
}

export interface ProgramDay {
  name:       string;
  focus:      string;
  exercises:  ProgramExercise[];
}

export interface ProgramExercise {
  name:        string;
  sets:        number;
  repsScheme:  string;
  weightScheme: string;
  rest:        number;
  notes?:      string;
}

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────
@Injectable()
export class AiCoachingService {
  private readonly logger = new Logger(AiCoachingService.name);

  constructor(private readonly config: ConfigService) {}

  // ── PROGRESSION SUGGESTIONS ──────────────────────────────────
  async getProgressionSuggestions(
    profile: TrainingProfile,
  ): Promise<ProgressionSuggestion[]> {
    const suggestions: ProgressionSuggestion[] = [];

    for (const [exerciseId, pr] of Object.entries(profile.exercisePRs)) {
      const suggestion = await this._analyzeExerciseProgression(
        exerciseId, pr, profile,
      );
      if (suggestion) suggestions.push(suggestion);
    }

    return suggestions.sort((a, b) => b.confidence - a.confidence);
  }

  private async _analyzeExerciseProgression(
    exerciseId: string,
    pr: ExercisePR,
    profile: TrainingProfile,
  ): Promise<ProgressionSuggestion | null> {
    // Get recent sessions for this exercise
    const recentSessions = profile.recentWorkouts
      .flatMap(w => w.exercises)
      .filter(e => e.exerciseId === exerciseId)
      .slice(0, 8);

    if (recentSessions.length < 2) return null;

    const exerciseName = recentSessions[0].exerciseName;
    const recentVolumes = recentSessions.map(s => s.totalVolume);
    const recentMaxWeights = recentSessions.map(s => s.maxWeight);

    // Detect plateau: no meaningful progress in 3+ sessions
    const isPlateaued = this._detectPlateau(recentMaxWeights);
    const volumeTrend  = this._calculateTrend(recentVolumes);

    // Training age modifier: beginners progress faster
    const weightIncrement = this._getWeightIncrement(
      profile.trainingAge, pr.weight,
    );

    if (isPlateaued) {
      // Check if deload is needed (high RPE + plateau)
      const avgRpe = recentSessions
        .filter(s => s.avgRpe != null)
        .reduce((sum, s, _, arr) => sum + (s.avgRpe ?? 0) / arr.length, 0);

      if (avgRpe > 8.5) {
        return {
          exerciseId,
          exerciseName,
          recommendation: 'deload',
          currentWeight:  pr.weight,
          suggestedWeight: pr.weight * 0.7,
          reason: `High RPE (${avgRpe.toFixed(1)}) with no progress. Deload week recommended.`,
          confidence: 0.85,
        };
      }

      return {
        exerciseId,
        exerciseName,
        recommendation: 'plateau_detected',
        currentWeight:  pr.weight,
        reason: `No weight increase in last ${recentSessions.length} sessions. Consider technique review or variation.`,
        confidence: 0.75,
      };
    }

    // Volume increasing → ready to add weight
    if (volumeTrend > 0.05 && pr.reps >= 5) {
      return {
        exerciseId,
        exerciseName,
        recommendation: 'increase_weight',
        currentWeight:  pr.weight,
        suggestedWeight: pr.weight + weightIncrement,
        reason: `Consistent volume increase (+${(volumeTrend * 100).toFixed(0)}% trend). Add ${weightIncrement}kg.`,
        confidence: 0.80,
      };
    }

    // Reps at top of range → increase weight
    if (pr.reps >= 12 && profile.mainGoal === 'hypertrophy') {
      return {
        exerciseId,
        exerciseName,
        recommendation: 'increase_weight',
        currentWeight:  pr.weight,
        suggestedWeight: pr.weight + weightIncrement,
        reason: `Hitting 12+ reps. Increase weight by ${weightIncrement}kg and aim for 8-10 reps.`,
        confidence: 0.90,
      };
    }

    return {
      exerciseId,
      exerciseName,
      recommendation: 'maintain',
      currentWeight:  pr.weight,
      reason: 'Continue with current load. Aim for perfect form.',
      confidence: 0.60,
    };
  }

  private _detectPlateau(weights: number[]): boolean {
    if (weights.length < 3) return false;
    const recent = weights.slice(0, 3);
    const variation = (Math.max(...recent) - Math.min(...recent)) / (Math.max(...recent) || 1);
    return variation < 0.02; // Less than 2% variation = plateau
  }

  private _calculateTrend(values: number[]): number {
    if (values.length < 2) return 0;
    // Simple linear regression slope
    const n    = values.length;
    const sumX  = values.reduce((_, __, i) => _ + i, 0);
    const sumY  = values.reduce((a, b) => a + b, 0);
    const sumXY = values.reduce((a, b, i) => a + i * b, 0);
    const sumX2 = values.reduce((a, _, i) => a + i * i, 0);
    const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    const avgY  = sumY / n;
    return avgY > 0 ? slope / avgY : 0;
  }

  private _getWeightIncrement(trainingAge: number, currentWeight: number): number {
    // Beginners: larger jumps. Advanced: smaller increments
    if (trainingAge < 1)  return currentWeight > 100 ? 5   : 2.5;
    if (trainingAge < 3)  return currentWeight > 100 ? 2.5 : 1.25;
    return 1.25; // Advanced lifters: micro-loading
  }

  // ── DELOAD DETECTION ─────────────────────────────────────────
  analyzeDeloadNeed(profile: TrainingProfile): {
    needsDeload: boolean;
    urgency:     'immediate' | 'planned' | 'none';
    reasons:     string[];
  } {
    const reasons: string[] = [];
    let score = 0;

    // Check average RPE trend (increasing = fatigue accumulation)
    const recentRPEs = profile.recentWorkouts
      .filter(w => w.rpe != null)
      .map(w => w.rpe!)
      .slice(0, 6);

    if (recentRPEs.length >= 3) {
      const avgRPE = recentRPEs.reduce((a, b) => a + b, 0) / recentRPEs.length;
      if (avgRPE > 9.0) {
        score += 3;
        reasons.push('Very high average RPE — systemic fatigue likely');
      } else if (avgRPE > 8.0) {
        score += 1;
        reasons.push('Elevated RPE trend over recent sessions');
      }
    }

    // Consecutive training days
    const sortedDates = profile.recentWorkouts
      .map(w => w.date)
      .sort((a, b) => b.getTime() - a.getTime());

    let consecutiveDays = 1;
    for (let i = 1; i < Math.min(sortedDates.length, 8); i++) {
      const diff = (sortedDates[i - 1].getTime() - sortedDates[i].getTime()) / 86400000;
      if (diff <= 1) consecutiveDays++;
      else break;
    }
    if (consecutiveDays >= 6) {
      score += 2;
      reasons.push(`${consecutiveDays} consecutive training days — recovery needed`);
    }

    // Training weeks since last deload (every 4-6 weeks recommended)
    const weeksOfData = profile.recentWorkouts.length / (profile.daysPerWeek || 3);
    if (weeksOfData >= 6) {
      score += 1;
      reasons.push('6+ training weeks without structured deload');
    }

    return {
      needsDeload: score >= 2,
      urgency:     score >= 4 ? 'immediate' : score >= 2 ? 'planned' : 'none',
      reasons,
    };
  }

  // ── PROGRAM GENERATION ───────────────────────────────────────
  async generateProgram(
    profile: TrainingProfile,
  ): Promise<ProgramTemplate> {
    const { daysPerWeek, mainGoal } = profile;

    // Select template based on goal and frequency
    if (mainGoal === 'strength') {
      return daysPerWeek <= 3
        ? this._generateStrongLifts(profile)
        : this._generatePowerlifting(profile);
    }

    if (mainGoal === 'hypertrophy') {
      return daysPerWeek <= 4
        ? this._generateUpperLower(profile)
        : this._generatePPL(profile);
    }

    return this._generateGeneralFitness(profile);
  }

  private _generateStrongLifts(profile: TrainingProfile): ProgramTemplate {
    return {
      name:        'AI StrongLifts 5×5',
      description: `AI-generated 5×5 program for ${profile.trainingAge < 1 ? 'beginners' : 'intermediate'} lifters`,
      daysPerWeek: 3,
      weeks:       12,
      days: [
        {
          name:  'Workout A',
          focus: 'Squat, Bench, Row',
          exercises: [
            { name: 'Barbell Back Squat', sets: 5, repsScheme: '5', weightScheme: '+2.5kg', rest: 180 },
            { name: 'Barbell Bench Press', sets: 5, repsScheme: '5', weightScheme: '+2.5kg', rest: 120 },
            { name: 'Barbell Row', sets: 5, repsScheme: '5', weightScheme: '+2.5kg', rest: 120 },
          ],
        },
        {
          name:  'Workout B',
          focus: 'Squat, OHP, Deadlift',
          exercises: [
            { name: 'Barbell Back Squat',  sets: 5, repsScheme: '5', weightScheme: '+2.5kg', rest: 180 },
            { name: 'Overhead Press',       sets: 5, repsScheme: '5', weightScheme: '+1.25kg', rest: 120 },
            { name: 'Conventional Deadlift', sets: 1, repsScheme: '5', weightScheme: '+5kg', rest: 240 },
          ],
        },
      ],
    };
  }

  private _generatePPL(profile: TrainingProfile): ProgramTemplate {
    return {
      name:        'AI Push Pull Legs',
      description: 'AI-optimized 6-day PPL for hypertrophy',
      daysPerWeek: 6,
      weeks:       8,
      days: [
        {
          name:  'Push A (Chest Focus)',
          focus: 'Chest, Shoulders, Triceps',
          exercises: [
            { name: 'Barbell Bench Press', sets: 4, repsScheme: '6-8', weightScheme: 'RPE 8', rest: 120 },
            { name: 'Incline Dumbbell Press', sets: 3, repsScheme: '8-12', weightScheme: 'RPE 8', rest: 90 },
            { name: 'Overhead Press', sets: 3, repsScheme: '8-10', weightScheme: 'RPE 8', rest: 90 },
            { name: 'Lateral Raise', sets: 4, repsScheme: '12-15', weightScheme: 'RPE 8', rest: 60 },
            { name: 'Tricep Pushdown', sets: 3, repsScheme: '10-15', weightScheme: 'RPE 8', rest: 60 },
          ],
        },
        {
          name:  'Pull A (Back Focus)',
          focus: 'Back, Biceps',
          exercises: [
            { name: 'Pull-up', sets: 4, repsScheme: '6-10', weightScheme: 'Bodyweight / Weighted', rest: 120 },
            { name: 'Barbell Row', sets: 4, repsScheme: '6-8', weightScheme: 'RPE 8', rest: 120 },
            { name: 'Cable Row', sets: 3, repsScheme: '10-12', weightScheme: 'RPE 8', rest: 90 },
            { name: 'Barbell Curl', sets: 3, repsScheme: '10-12', weightScheme: 'RPE 8', rest: 60 },
          ],
        },
        {
          name:  'Legs A (Quad Focus)',
          focus: 'Quads, Hamstrings, Glutes',
          exercises: [
            { name: 'Barbell Back Squat', sets: 4, repsScheme: '6-8', weightScheme: 'RPE 8', rest: 180 },
            { name: 'Romanian Deadlift', sets: 3, repsScheme: '8-10', weightScheme: 'RPE 8', rest: 120 },
            { name: 'Leg Press', sets: 3, repsScheme: '10-15', weightScheme: 'RPE 8', rest: 90 },
            { name: 'Hip Thrust', sets: 3, repsScheme: '10-12', weightScheme: 'RPE 8', rest: 90 },
          ],
        },
      ],
    };
  }

  private _generateUpperLower(_profile: TrainingProfile): ProgramTemplate {
    return {
      name: 'AI Upper/Lower',
      description: '4-day upper/lower hypertrophy split',
      daysPerWeek: 4,
      weeks: 8,
      days: [
        { name: 'Upper A', focus: 'Horizontal Push/Pull', exercises: [
          { name: 'Barbell Bench Press', sets: 4, repsScheme: '6-8', weightScheme: 'RPE 8', rest: 120 },
          { name: 'Barbell Row', sets: 4, repsScheme: '6-8', weightScheme: 'RPE 8', rest: 120 },
          { name: 'Overhead Press', sets: 3, repsScheme: '8-10', weightScheme: 'RPE 8', rest: 90 },
          { name: 'Barbell Curl', sets: 3, repsScheme: '10-12', weightScheme: 'RPE 8', rest: 60 },
        ]},
        { name: 'Lower A', focus: 'Squat Pattern', exercises: [
          { name: 'Barbell Back Squat', sets: 4, repsScheme: '6-8', weightScheme: 'RPE 8', rest: 180 },
          { name: 'Romanian Deadlift', sets: 3, repsScheme: '8-10', weightScheme: 'RPE 8', rest: 120 },
          { name: 'Leg Press', sets: 3, repsScheme: '10-15', weightScheme: 'RPE 8', rest: 90 },
        ]},
      ],
    };
  }

  private _generatePowerlifting(profile: TrainingProfile): ProgramTemplate {
    return {
      name: 'AI Powerlifting',
      description: 'Percentage-based powerlifting program',
      daysPerWeek: 4, weeks: 12,
      days: [
        { name: 'Squat Day', focus: 'Squat + accessories', exercises: [
          { name: 'Barbell Back Squat', sets: 5, repsScheme: '5', weightScheme: '75%1RM', rest: 180,
            notes: 'Week 1: 75%, Week 2: 80%, Week 3: 85%, Week 4: Deload 60%' },
          { name: 'Front Squat', sets: 3, repsScheme: '5', weightScheme: '65%1RM', rest: 120 },
          { name: 'Romanian Deadlift', sets: 3, repsScheme: '8', weightScheme: 'RPE 8', rest: 120 },
        ]},
        { name: 'Bench Day', focus: 'Bench + accessories', exercises: [
          { name: 'Barbell Bench Press', sets: 5, repsScheme: '5', weightScheme: '75%1RM', rest: 150 },
          { name: 'Overhead Press', sets: 3, repsScheme: '5', weightScheme: '65%1RM', rest: 120 },
          { name: 'Barbell Row', sets: 3, repsScheme: '8', weightScheme: 'RPE 8', rest: 90 },
        ]},
        { name: 'Deadlift Day', focus: 'Deadlift + accessories', exercises: [
          { name: 'Conventional Deadlift', sets: 4, repsScheme: '4', weightScheme: '78%1RM', rest: 240 },
          { name: 'Hip Thrust', sets: 3, repsScheme: '8', weightScheme: 'RPE 8', rest: 120 },
          { name: 'Barbell Row', sets: 3, repsScheme: '6', weightScheme: 'RPE 8', rest: 120 },
        ]},
      ],
    };
  }

  private _generateGeneralFitness(_profile: TrainingProfile): ProgramTemplate {
    return {
      name: 'AI General Fitness',
      description: 'Balanced strength and conditioning',
      daysPerWeek: 3, weeks: 8,
      days: [
        { name: 'Full Body A', focus: 'Compound movements', exercises: [
          { name: 'Barbell Back Squat', sets: 3, repsScheme: '8-10', weightScheme: 'RPE 7', rest: 120 },
          { name: 'Barbell Bench Press', sets: 3, repsScheme: '8-10', weightScheme: 'RPE 7', rest: 90 },
          { name: 'Barbell Row', sets: 3, repsScheme: '8-10', weightScheme: 'RPE 7', rest: 90 },
        ]},
      ],
    };
  }

  // ── RECOVERY ADVICE ──────────────────────────────────────────
  getRecoveryRecommendations(profile: TrainingProfile): string[] {
    const advice: string[] = [];
    const deloadAnalysis   = this.analyzeDeloadNeed(profile);

    if (deloadAnalysis.needsDeload) {
      advice.push(`🔴 ${deloadAnalysis.reasons[0]}`);
      advice.push('Consider a deload week: reduce weights by 40-50% and focus on technique.');
    }

    const recentVolumes = profile.recentWorkouts
      .slice(0, 4)
      .map(w => w.exercises.reduce((sum, e) => sum + e.totalVolume, 0));

    const volumeTrend = this._calculateTrend(recentVolumes);
    if (volumeTrend > 0.15) {
      advice.push('📈 Volume increasing rapidly. Monitor recovery and sleep quality.');
    }

    advice.push('💤 Aim for 7-9 hours of sleep for optimal muscle protein synthesis.');
    advice.push('🥩 Ensure 1.6-2.2g protein per kg of bodyweight daily.');

    return advice;
  }
}
