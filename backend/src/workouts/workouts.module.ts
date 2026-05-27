// ─────────────────────────────────────────────────────────────
// WORKOUT ENTITY
// ─────────────────────────────────────────────────────────────
import {
  Entity, PrimaryColumn, Column, ManyToOne, OneToMany,
  CreateDateColumn, UpdateDateColumn, JoinColumn, Index,
} from 'typeorm';

export enum WorkoutStatus {
  PLANNED    = 'planned',
  IN_PROGRESS= 'inProgress',
  COMPLETED  = 'completed',
  SKIPPED    = 'skipped',
}

@Entity('workouts')
@Index(['userId', 'date'])
@Index(['userId', 'status'])
export class WorkoutEntity {
  @PrimaryColumn('uuid')
  id: string;

  @Column('uuid')
  userId: string;

  @Column()
  name: string;

  @Column({ type: 'enum', enum: WorkoutStatus, default: WorkoutStatus.PLANNED })
  status: WorkoutStatus;

  @Column('date')
  date: Date;

  @Column({ nullable: true })
  programId?: string;

  @Column({ nullable: true })
  programDay?: number;

  @Column({ nullable: true })
  durationSeconds?: number;

  @Column({ nullable: true, type: 'text' })
  notes?: string;

  @Column({ nullable: true, type: 'float' })
  bodyweight?: number;

  @Column({ nullable: true })
  perceivedDifficulty?: number;

  @Column({ nullable: true, type: 'timestamp' })
  startedAt?: Date;

  @Column({ nullable: true, type: 'timestamp' })
  completedAt?: Date;

  @Column({ default: false })
  isDeleted: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;

  @OneToMany(() => WorkoutExerciseEntity, (we) => we.workout, {
    cascade: true, eager: true,
  })
  exercises: WorkoutExerciseEntity[];
}

@Entity('workout_exercises')
export class WorkoutExerciseEntity {
  @PrimaryColumn('uuid')
  id: string;

  @Column('uuid')
  workoutId: string;

  @ManyToOne(() => WorkoutEntity, (w) => w.exercises)
  @JoinColumn({ name: 'workoutId' })
  workout: WorkoutEntity;

  @Column('uuid')
  exerciseId: string;

  @Column()
  orderIndex: number;

  @Column({ nullable: true })
  restSeconds?: number;

  @Column({ nullable: true, type: 'text' })
  notes?: string;

  @Column({ nullable: true })
  supersetGroupId?: string;

  @OneToMany(() => WorkoutSetEntity, (s) => s.workoutExercise, {
    cascade: true, eager: true,
  })
  sets: WorkoutSetEntity[];
}

@Entity('workout_sets')
export class WorkoutSetEntity {
  @PrimaryColumn('uuid')
  id: string;

  @Column('uuid')
  workoutExerciseId: string;

  @ManyToOne(() => WorkoutExerciseEntity, (we) => we.sets)
  @JoinColumn({ name: 'workoutExerciseId' })
  workoutExercise: WorkoutExerciseEntity;

  @Column()
  setNumber: number;

  @Column({ default: 'normal' })
  setType: string;

  @Column({ nullable: true, type: 'float' })
  targetWeight?: number;

  @Column({ nullable: true })
  targetReps?: number;

  @Column({ nullable: true, type: 'float' })
  targetRpe?: number;

  @Column({ nullable: true })
  targetRir?: number;

  @Column({ nullable: true })
  tempo?: string;

  @Column({ nullable: true, type: 'float' })
  loggedWeight?: number;

  @Column({ nullable: true })
  loggedReps?: number;

  @Column({ nullable: true, type: 'float' })
  loggedRpe?: number;

  @Column({ nullable: true })
  completed?: boolean;

  @Column({ nullable: true })
  restSeconds?: number;

  @Column({ nullable: true, type: 'timestamp' })
  completedAt?: Date;

  @Column({ nullable: true, type: 'text' })
  notes?: string;
}

// ─────────────────────────────────────────────────────────────
// DTOs
// ─────────────────────────────────────────────────────────────
import { IsString, IsOptional, IsNumber, IsDateString, IsArray, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class LogSetDto {
  @ApiProperty()  @IsString()   id: string;
  @ApiProperty()  @IsNumber()   setNumber: number;
  @ApiProperty()  @IsString()   setType: string;
  @ApiPropertyOptional() @IsOptional() @IsNumber() targetWeight?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() targetReps?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() loggedWeight?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() loggedReps?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() loggedRpe?: number;
  @ApiPropertyOptional() @IsOptional()             completed?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsNumber() restSeconds?: number;
  @ApiPropertyOptional() @IsOptional() @IsString() notes?: string;
}

export class WorkoutExerciseDto {
  @ApiProperty()  @IsString()  id: string;
  @ApiProperty()  @IsString()  exerciseId: string;
  @ApiProperty()  @IsNumber()  orderIndex: number;
  @ApiProperty({ type: [LogSetDto] }) @IsArray() @ValidateNested({ each: true }) @Type(() => LogSetDto)
  sets: LogSetDto[];
  @ApiPropertyOptional() @IsOptional() @IsNumber() restSeconds?: number;
  @ApiPropertyOptional() @IsOptional() @IsString() notes?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() supersetGroupId?: string;
}

export class SyncWorkoutDto {
  @ApiProperty()  @IsString()      id: string;
  @ApiProperty()  @IsString()      name: string;
  @ApiProperty()  @IsString()      status: string;
  @ApiProperty()  @IsDateString()  date: string;
  @ApiPropertyOptional() @IsOptional() @IsString() programId?: string;
  @ApiPropertyOptional() @IsOptional() @IsNumber() programDay?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() durationSeconds?: number;
  @ApiPropertyOptional() @IsOptional() @IsString() notes?: string;
  @ApiPropertyOptional() @IsOptional() @IsNumber() bodyweight?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() perceivedDifficulty?: number;
  @ApiProperty({ type: [WorkoutExerciseDto] })
  @IsArray() @ValidateNested({ each: true }) @Type(() => WorkoutExerciseDto)
  exercises: WorkoutExerciseDto[];
}

export class SyncBatchDto {
  @ApiProperty({ type: [SyncWorkoutDto] })
  @IsArray() @ValidateNested({ each: true }) @Type(() => SyncWorkoutDto)
  workouts: SyncWorkoutDto[];

  @ApiProperty()
  @IsDateString()
  lastSyncAt: string;
}

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────
import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, Between, MoreThan } from 'typeorm';

@Injectable()
export class WorkoutsService {
  constructor(
    @InjectRepository(WorkoutEntity)
    private readonly workoutsRepo: Repository<WorkoutEntity>,
    @InjectRepository(WorkoutExerciseEntity)
    private readonly exercisesRepo: Repository<WorkoutExerciseEntity>,
    @InjectRepository(WorkoutSetEntity)
    private readonly setsRepo: Repository<WorkoutSetEntity>,
  ) {}

  // ── CRUD ─────────────────────────────────────────────────────
  async findAll(userId: string, params: {
    startDate?: string;
    endDate?:   string;
    limit?:     number;
    offset?:    number;
  }) {
    const where: any = { userId, isDeleted: false };
    if (params.startDate && params.endDate) {
      where.date = Between(new Date(params.startDate), new Date(params.endDate));
    }
    const [workouts, total] = await this.workoutsRepo.findAndCount({
      where,
      order:  { date: 'DESC' },
      take:   params.limit  ?? 20,
      skip:   params.offset ?? 0,
    });
    return { workouts, total };
  }

  async findOne(id: string, userId: string): Promise<WorkoutEntity> {
    const workout = await this.workoutsRepo.findOne({ where: { id, userId } });
    if (!workout) throw new NotFoundException(`Workout ${id} not found`);
    return workout;
  }

  async delete(id: string, userId: string): Promise<void> {
    await this.workoutsRepo.update({ id, userId }, { isDeleted: true });
  }

  // ── SYNC (offline-first) ─────────────────────────────────────
  async syncBatch(userId: string, dto: SyncBatchDto): Promise<{
    synced: number;
    conflicts: string[];
    serverChanges: WorkoutEntity[];
  }> {
    const conflicts: string[] = [];
    let synced = 0;

    for (const workoutDto of dto.workouts) {
      try {
        const existing = await this.workoutsRepo.findOne({
          where: { id: workoutDto.id },
        });

        if (existing && existing.userId !== userId) {
          // Ownership mismatch — skip
          conflicts.push(workoutDto.id);
          continue;
        }

        if (existing) {
          // Conflict resolution: last-write-wins (client wins for own data)
          await this._upsertWorkout(userId, workoutDto);
        } else {
          await this._upsertWorkout(userId, workoutDto);
        }
        synced++;
      } catch (err) {
        conflicts.push(workoutDto.id);
      }
    }

    // Return server changes since client's last sync
    const serverChanges = await this.workoutsRepo.find({
      where: {
        userId,
        updatedAt: MoreThan(new Date(dto.lastSyncAt)),
        isDeleted: false,
      },
      order: { updatedAt: 'ASC' },
    });

    return { synced, conflicts, serverChanges };
  }

  private async _upsertWorkout(userId: string, dto: SyncWorkoutDto): Promise<void> {
    // Save workout header
    await this.workoutsRepo.save({
      id:                   dto.id,
      userId,
      name:                 dto.name,
      status:               dto.status as WorkoutStatus,
      date:                 new Date(dto.date),
      programId:            dto.programId,
      programDay:           dto.programDay,
      durationSeconds:      dto.durationSeconds,
      notes:                dto.notes,
      bodyweight:           dto.bodyweight,
      perceivedDifficulty:  dto.perceivedDifficulty,
    });

    // Save exercises and sets
    for (const exDto of dto.exercises) {
      await this.exercisesRepo.save({
        id:             exDto.id,
        workoutId:      dto.id,
        exerciseId:     exDto.exerciseId,
        orderIndex:     exDto.orderIndex,
        restSeconds:    exDto.restSeconds,
        notes:          exDto.notes,
        supersetGroupId:exDto.supersetGroupId,
      });

      for (const setDto of exDto.sets) {
        await this.setsRepo.save({
          id:                 setDto.id,
          workoutExerciseId:  exDto.id,
          setNumber:          setDto.setNumber,
          setType:            setDto.setType,
          targetWeight:       setDto.targetWeight,
          targetReps:         setDto.targetReps,
          loggedWeight:       setDto.loggedWeight,
          loggedReps:         setDto.loggedReps,
          loggedRpe:          setDto.loggedRpe,
          completed:          setDto.completed,
          restSeconds:        setDto.restSeconds,
          notes:              setDto.notes,
        });
      }
    }
  }

  // ── ANALYTICS ────────────────────────────────────────────────
  async getVolumeByMuscle(userId: string, startDate: Date, endDate: Date) {
    const result = await this.workoutsRepo.manager.query(`
      SELECT
        e.primary_muscle,
        SUM(ws.logged_weight * ws.logged_reps) as volume,
        COUNT(ws.id) as total_sets
      FROM workout_sets ws
      JOIN workout_exercises we ON ws.workout_exercise_id = we.id
      JOIN workouts w           ON we.workout_id = w.id
      JOIN exercises e          ON we.exercise_id = e.id
      WHERE w.user_id = $1
        AND w.date BETWEEN $2 AND $3
        AND ws.completed = true
        AND w.is_deleted = false
      GROUP BY e.primary_muscle
      ORDER BY volume DESC
    `, [userId, startDate, endDate]);
    return result;
  }

  async getExerciseHistory(userId: string, exerciseId: string, limit = 30) {
    return this.workoutsRepo.manager.query(`
      SELECT
        w.date,
        MAX(ws.logged_weight) as max_weight,
        MAX(ws.logged_reps)   as max_reps,
        MAX(ws.logged_weight * (1 + ws.logged_reps::float / 30)) as estimated_1rm,
        SUM(ws.logged_weight * ws.logged_reps) as total_volume,
        COUNT(ws.id) as total_sets
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
}

// ─────────────────────────────────────────────────────────────
// CONTROLLER
// ─────────────────────────────────────────────────────────────
import {
  Controller, Get, Post, Delete, Body, Param, Query,
  UseGuards, Request, HttpCode, HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ThrottlerGuard } from '@nestjs/throttler';

@ApiTags('workouts')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, ThrottlerGuard)
@Controller('api/v1/workouts')
export class WorkoutsController {
  constructor(private readonly workoutsService: WorkoutsService) {}

  @Get()
  @ApiOperation({ summary: 'List workouts with date filtering' })
  async findAll(
    @Request() req: any,
    @Query('startDate') startDate?: string,
    @Query('endDate')   endDate?: string,
    @Query('limit')     limit?: number,
    @Query('offset')    offset?: number,
  ) {
    return this.workoutsService.findAll(req.user.id, {
      startDate, endDate,
      limit:  limit  ? Number(limit)  : 20,
      offset: offset ? Number(offset) : 0,
    });
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get single workout' })
  async findOne(@Param('id') id: string, @Request() req: any) {
    return this.workoutsService.findOne(id, req.user.id);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Soft-delete workout' })
  async delete(@Param('id') id: string, @Request() req: any) {
    return this.workoutsService.delete(id, req.user.id);
  }

  @Post('sync')
  @ApiOperation({
    summary: 'Offline-first sync — upload local changes, receive server changes',
  })
  @ApiResponse({ status: 200, description: 'Sync complete' })
  async sync(@Body() dto: SyncBatchDto, @Request() req: any) {
    return this.workoutsService.syncBatch(req.user.id, dto);
  }

  @Get('analytics/volume-by-muscle')
  @ApiOperation({ summary: 'Volume breakdown by muscle group' })
  async volumeByMuscle(
    @Request() req: any,
    @Query('startDate') startDate: string,
    @Query('endDate')   endDate:   string,
  ) {
    return this.workoutsService.getVolumeByMuscle(
      req.user.id,
      new Date(startDate),
      new Date(endDate),
    );
  }

  @Get('analytics/exercise/:exerciseId')
  @ApiOperation({ summary: 'Exercise history for strength progression charts' })
  async exerciseHistory(
    @Request() req: any,
    @Param('exerciseId') exerciseId: string,
    @Query('limit') limit?: number,
  ) {
    return this.workoutsService.getExerciseHistory(
      req.user.id, exerciseId, limit ? Number(limit) : 30,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MODULE
// ─────────────────────────────────────────────────────────────
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';

@Module({
  imports: [TypeOrmModule.forFeature([
    WorkoutEntity, WorkoutExerciseEntity, WorkoutSetEntity,
  ])],
  providers:   [WorkoutsService],
  controllers: [WorkoutsController],
  exports:     [WorkoutsService],
})
export class WorkoutsModule {}
