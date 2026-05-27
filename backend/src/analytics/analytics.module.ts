// ─────────────────────────────────────────────────────────────
// health.controller.ts
// ─────────────────────────────────────────────────────────────
import { Controller, Get } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import { ApiTags } from '@nestjs/swagger';

@ApiTags('system')
@Controller()
export class HealthController {
  constructor(@InjectDataSource() private readonly dataSource: DataSource) {}

  @Get('health')
  async health() {
    const dbOk = this.dataSource.isInitialized;
    return {
      status:    dbOk ? 'ok' : 'degraded',
      timestamp: new Date().toISOString(),
      version:   process.env.npm_package_version ?? '1.0.0',
      database:  dbOk ? 'connected' : 'disconnected',
    };
  }
}

// ─────────────────────────────────────────────────────────────
// exercises.module.ts
// ─────────────────────────────────────────────────────────────
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import {
  Entity, PrimaryGeneratedColumn, Column,
  CreateDateColumn, UpdateDateColumn,
} from 'typeorm';
import {
  Controller, Get, Post, Put, Delete, Body, Param, Query,
  UseGuards, Request, HttpCode, HttpStatus,
} from '@nestjs/common';
import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Like, ILike } from 'typeorm';
import { IsString, IsOptional, IsBoolean, IsArray } from 'class-validator';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// Entity
@Entity('exercises')
export class ExerciseEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  name: string;

  @Column()
  primaryMuscle: string;

  @Column('text', { array: true, default: [] })
  secondaryMuscles: string[];

  @Column()
  equipment: string;

  @Column()
  category: string;

  @Column({ nullable: true, type: 'text' })
  description?: string;

  @Column({ nullable: true })
  videoUrl?: string;

  @Column({ nullable: true })
  thumbnailUrl?: string;

  @Column({ nullable: true, type: 'text' })
  instructions?: string;

  @Column({ default: false })
  isCustom: boolean;

  @Column({ nullable: true })
  userId?: string;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}

// DTOs
class CreateExerciseDto {
  @IsString()  name:            string;
  @IsString()  primaryMuscle:   string;
  @IsArray()   @IsOptional() secondaryMuscles?: string[];
  @IsString()  equipment:       string;
  @IsString()  category:        string;
  @IsOptional() @IsString() description?: string;
  @IsOptional() @IsString() videoUrl?:    string;
  @IsOptional() @IsString() instructions?:string;
}

// Service
@Injectable()
export class ExercisesService {
  constructor(
    @InjectRepository(ExerciseEntity)
    private readonly repo: Repository<ExerciseEntity>,
  ) {}

  async findAll(params: {
    search?:    string;
    muscle?:    string;
    equipment?: string;
    userId?:    string;
    customOnly?:boolean;
    limit?:     number;
    offset?:    number;
  }) {
    const qb = this.repo.createQueryBuilder('e')
      .where('e.userId IS NULL OR e.userId = :userId', { userId: params.userId ?? '' });

    if (params.search) {
      qb.andWhere('e.name ILIKE :search', { search: `%${params.search}%` });
    }
    if (params.muscle) {
      qb.andWhere('e.primaryMuscle = :muscle', { muscle: params.muscle });
    }
    if (params.equipment) {
      qb.andWhere('e.equipment = :equipment', { equipment: params.equipment });
    }
    if (params.customOnly) {
      qb.andWhere('e.isCustom = true');
    }

    qb.orderBy('e.name', 'ASC')
      .skip(params.offset ?? 0)
      .take(params.limit ?? 50);

    const [exercises, total] = await qb.getManyAndCount();
    return { exercises, total };
  }

  async findOne(id: string): Promise<ExerciseEntity> {
    const exercise = await this.repo.findOne({ where: { id } });
    if (!exercise) throw new NotFoundException(`Exercise ${id} not found`);
    return exercise;
  }

  async create(dto: CreateExerciseDto, userId: string): Promise<ExerciseEntity> {
    return this.repo.save({
      ...dto,
      isCustom: true,
      userId,
      secondaryMuscles: dto.secondaryMuscles ?? [],
    });
  }

  async update(id: string, dto: Partial<CreateExerciseDto>, userId: string): Promise<ExerciseEntity> {
    const exercise = await this.repo.findOne({ where: { id, userId } });
    if (!exercise) throw new NotFoundException();
    Object.assign(exercise, dto);
    return this.repo.save(exercise);
  }

  async delete(id: string, userId: string): Promise<void> {
    const exercise = await this.repo.findOne({ where: { id, userId, isCustom: true } });
    if (!exercise) throw new NotFoundException('Custom exercise not found');
    await this.repo.delete(id);
  }

  async toggleFavorite(id: string, _userId: string): Promise<void> {
    // In production: use a user_exercise_favorites join table
  }
}

// Controller
@ApiTags('exercises')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('api/v1/exercises')
export class ExercisesController {
  constructor(private readonly exercisesService: ExercisesService) {}

  @Get()
  @ApiOperation({ summary: 'List exercises with search/filter' })
  async findAll(
    @Request() req: any,
    @Query('search')    search?: string,
    @Query('muscle')    muscle?: string,
    @Query('equipment') equipment?: string,
    @Query('customOnly') customOnly?: boolean,
    @Query('limit')     limit?: number,
    @Query('offset')    offset?: number,
  ) {
    return this.exercisesService.findAll({
      search, muscle, equipment,
      userId:     req.user.id,
      customOnly: customOnly === true || customOnly === ('true' as any),
      limit:      limit  ? Number(limit)  : 50,
      offset:     offset ? Number(offset) : 0,
    });
  }

  @Get(':id')
  async findOne(@Param('id') id: string) {
    return this.exercisesService.findOne(id);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create custom exercise' })
  async create(@Body() dto: CreateExerciseDto, @Request() req: any) {
    return this.exercisesService.create(dto, req.user.id);
  }

  @Put(':id')
  @ApiOperation({ summary: 'Update custom exercise' })
  async update(
    @Param('id') id: string,
    @Body() dto: Partial<CreateExerciseDto>,
    @Request() req: any,
  ) {
    return this.exercisesService.update(id, dto, req.user.id);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete custom exercise' })
  async delete(@Param('id') id: string, @Request() req: any) {
    return this.exercisesService.delete(id, req.user.id);
  }

  @Post(':id/favorite')
  @HttpCode(HttpStatus.NO_CONTENT)
  async toggleFavorite(@Param('id') id: string, @Request() req: any) {
    return this.exercisesService.toggleFavorite(id, req.user.id);
  }
}

@Module({
  imports:     [TypeOrmModule.forFeature([ExerciseEntity])],
  providers:   [ExercisesService],
  controllers: [ExercisesController, HealthController],
  exports:     [ExercisesService],
})
export class ExercisesModule {}

// ─────────────────────────────────────────────────────────────
// analytics.module.ts
// ─────────────────────────────────────────────────────────────
import { Cron, CronExpression } from '@nestjs/schedule';

@Injectable()
export class AnalyticsService {
  constructor(@InjectDataSource() private readonly dataSource: DataSource) {}

  async getStrengthProgression(userId: string, exerciseId: string, limit = 30) {
    return this.dataSource.query(`
      SELECT
        w.date,
        MAX(ws.estimated_1rm)    AS estimated_1rm,
        MAX(ws.logged_weight)    AS max_weight,
        MAX(ws.logged_reps)      AS max_reps,
        SUM(ws.volume)           AS total_volume,
        COUNT(ws.id)             AS total_sets,
        AVG(ws.logged_rpe)       AS avg_rpe
      FROM workout_sets ws
      JOIN workout_exercises we ON ws.workout_exercise_id = we.id
      JOIN workouts w           ON we.workout_id = w.id
      WHERE w.user_id = $1
        AND we.exercise_id = $2
        AND ws.completed = true
        AND w.is_deleted = false
      GROUP BY w.date
      ORDER BY w.date DESC
      LIMIT $3
    `, [userId, exerciseId, limit]);
  }

  async getWeeklyStats(userId: string, weeks = 12) {
    return this.dataSource.query(`
      SELECT
        DATE_TRUNC('week', w.date)   AS week_start,
        COUNT(DISTINCT w.id)         AS workout_count,
        SUM(ws.volume)               AS total_volume,
        AVG(w.duration_seconds)      AS avg_duration,
        AVG(w.perceived_difficulty)  AS avg_difficulty
      FROM workouts w
      LEFT JOIN workout_exercises we ON we.workout_id = w.id
      LEFT JOIN workout_sets ws      ON ws.workout_exercise_id = we.id AND ws.completed = true
      WHERE w.user_id = $1
        AND w.status = 'completed'
        AND w.is_deleted = false
        AND w.date >= NOW() - ($2 || ' weeks')::interval
      GROUP BY week_start
      ORDER BY week_start DESC
    `, [userId, weeks]);
  }

  async getMuscleVolumeBreakdown(userId: string, startDate: Date, endDate: Date) {
    return this.dataSource.query(`
      SELECT
        e.primary_muscle,
        SUM(ws.volume)   AS total_volume,
        COUNT(ws.id)     AS total_sets,
        COUNT(DISTINCT w.id) AS sessions
      FROM workout_sets ws
      JOIN workout_exercises we ON ws.workout_exercise_id = we.id
      JOIN workouts w           ON we.workout_id = w.id
      JOIN exercises e          ON we.exercise_id = e.id
      WHERE w.user_id = $1
        AND w.date BETWEEN $2 AND $3
        AND ws.completed = true
        AND w.is_deleted = false
      GROUP BY e.primary_muscle
      ORDER BY total_volume DESC
    `, [userId, startDate, endDate]);
  }

  async getPersonalRecords(userId: string) {
    return this.dataSource.query(`
      SELECT
        pr.*,
        e.primary_muscle,
        e.equipment
      FROM personal_records pr
      JOIN exercises e ON pr.exercise_id = e.id
      WHERE pr.user_id = $1
      ORDER BY pr.achieved_at DESC
    `, [userId]);
  }

  async getBodyweightHistory(userId: string, days = 90) {
    return this.dataSource.query(`
      SELECT date, bodyweight
      FROM workouts
      WHERE user_id = $1
        AND bodyweight IS NOT NULL
        AND date >= NOW() - ($2 || ' days')::interval
        AND is_deleted = false
      ORDER BY date ASC
    `, [userId, days]);
  }

  async getTrainingFrequency(userId: string, weeks = 12) {
    return this.dataSource.query(`
      SELECT
        DATE_TRUNC('week', date) AS week,
        COUNT(*) AS workout_count,
        array_agg(DISTINCT TO_CHAR(date, 'Dy')) AS days_trained
      FROM workouts
      WHERE user_id = $1
        AND status = 'completed'
        AND is_deleted = false
        AND date >= NOW() - ($2 || ' weeks')::interval
      GROUP BY week
      ORDER BY week DESC
    `, [userId, weeks]);
  }

  @Cron(CronExpression.EVERY_DAY_AT_MIDNIGHT)
  async refreshMaterializedViews() {
    await this.dataSource.query('SELECT refresh_analytics()');
  }
}

@ApiTags('analytics')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('api/v1/analytics')
export class AnalyticsController {
  constructor(private readonly analyticsService: AnalyticsService) {}

  @Get('strength/:exerciseId')
  @ApiOperation({ summary: 'Strength progression for an exercise' })
  async strengthProgression(
    @Request() req: any,
    @Param('exerciseId') exerciseId: string,
    @Query('limit') limit?: number,
  ) {
    return this.analyticsService.getStrengthProgression(
      req.user.id, exerciseId, limit ? Number(limit) : 30,
    );
  }

  @Get('weekly')
  @ApiOperation({ summary: 'Weekly training stats' })
  async weeklyStats(
    @Request() req: any,
    @Query('weeks') weeks?: number,
  ) {
    return this.analyticsService.getWeeklyStats(
      req.user.id, weeks ? Number(weeks) : 12,
    );
  }

  @Get('muscle-volume')
  @ApiOperation({ summary: 'Volume breakdown by muscle group' })
  async muscleVolume(
    @Request() req: any,
    @Query('startDate') startDate: string,
    @Query('endDate')   endDate:   string,
  ) {
    return this.analyticsService.getMuscleVolumeBreakdown(
      req.user.id, new Date(startDate), new Date(endDate),
    );
  }

  @Get('personal-records')
  @ApiOperation({ summary: 'All personal records' })
  async personalRecords(@Request() req: any) {
    return this.analyticsService.getPersonalRecords(req.user.id);
  }

  @Get('bodyweight')
  @ApiOperation({ summary: 'Bodyweight tracking history' })
  async bodyweight(
    @Request() req: any,
    @Query('days') days?: number,
  ) {
    return this.analyticsService.getBodyweightHistory(
      req.user.id, days ? Number(days) : 90,
    );
  }

  @Get('frequency')
  @ApiOperation({ summary: 'Training frequency calendar' })
  async frequency(
    @Request() req: any,
    @Query('weeks') weeks?: number,
  ) {
    return this.analyticsService.getTrainingFrequency(
      req.user.id, weeks ? Number(weeks) : 12,
    );
  }
}

@Module({
  imports:     [TypeOrmModule.forFeature([])],
  providers:   [AnalyticsService],
  controllers: [AnalyticsController],
  exports:     [AnalyticsService],
})
export class AnalyticsModule {}
