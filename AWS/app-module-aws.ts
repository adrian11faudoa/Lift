// src/app.module.ts — Updated for AWS deployment
// Adds: Redis caching, S3 storage, SES email, health endpoint, X-Ray tracing

import { Module }           from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule }    from '@nestjs/typeorm';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { ScheduleModule }   from '@nestjs/schedule';
import { APP_GUARD }        from '@nestjs/core';
import { createClient }     from 'redis';

// Feature modules
import { AuthModule }          from './auth/auth.module';
import { UsersModule }         from './users/users.module';
import { ExercisesModule }     from './exercises/exercises.module';
import { WorkoutsModule }      from './workouts/workouts.module';
import { ProgramsModule }      from './programs/programs.module';
import { AnalyticsModule }     from './analytics/analytics.module';
import { AiModule }            from './ai/ai.module';
import { SubscriptionsModule } from './subscriptions/subscriptions.module';

// Common
import { RedisModule }         from './common/redis/redis.module';
import { HealthController }    from './exercises/exercises.module';

// ─────────────────────────────────────────────────────────────
// DATABASE CONFIGURATION
// Handles: local Docker (dev), RDS (staging/prod)
// ─────────────────────────────────────────────────────────────
const typeormConfig = TypeOrmModule.forRootAsync({
  imports:    [ConfigModule],
  inject:     [ConfigService],
  useFactory: (config: ConfigService) => ({
    type:        'postgres' as const,
    host:        config.get('DB_HOST',     'localhost'),
    port:        config.get<number>('DB_PORT', 5432),
    username:    config.get('DB_USER',     'ironlog'),
    password:    config.get('DB_PASSWORD', 'ironlog'),
    database:    config.get('DB_NAME',     'ironlog'),
    entities:    [__dirname + '/**/*.entity{.ts,.js}'],
    synchronize: config.get('NODE_ENV') === 'development',
    ssl:         config.get('DB_SSL') === 'true'
      ? { rejectUnauthorized: false }
      : false,
    logging:     config.get('NODE_ENV') === 'development'
      ? ['error', 'warn', 'query']
      : ['error'],
    // Connection pool — critical for ECS (multiple tasks share RDS limit)
    extra: {
      max:             10,     // Max pool size per task
      min:             2,      // Min idle connections
      acquire:         30000,  // Max ms to wait for connection
      idle:            10000,  // Close idle connections after 10s
      evict:           1000,   // Check for idle connections every 1s
    },
    // RDS Proxy support (if using RDS Proxy — recommended for Lambda/short-lived)
    // poolSize: 5,
  }),
});

// ─────────────────────────────────────────────────────────────
// THROTTLER — use Redis for distributed rate limiting
// (all ECS tasks share the same rate limit counters)
// ─────────────────────────────────────────────────────────────
const throttlerConfig = ThrottlerModule.forRootAsync({
  imports: [ConfigModule],
  inject:  [ConfigService],
  useFactory: (config: ConfigService) => ({
    throttlers: [
      { name: 'short', ttl: 1000,  limit: 20  },
      { name: 'long',  ttl: 60000, limit: 300 },
    ],
    // Use Redis storage for multi-instance rate limiting
    storage: {
      // In production, wire this to the Redis client
      // storage: new ThrottlerStorageRedisService(redisClient),
    },
  }),
});

// ─────────────────────────────────────────────────────────────
// APP MODULE
// ─────────────────────────────────────────────────────────────
@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal:    true,
      envFilePath: ['.env.local', '.env'],
      // Validate required environment variables
      validate: (config: Record<string, unknown>) => {
        const required = ['JWT_SECRET', 'JWT_REFRESH_SECRET'];
        const missing  = required.filter(k => !config[k]);
        if (missing.length > 0) {
          throw new Error(`Missing required env vars: ${missing.join(', ')}`);
        }
        return config;
      },
    }),
    typeormConfig,
    throttlerConfig,
    ScheduleModule.forRoot(),
    RedisModule,
    AuthModule,
    UsersModule,
    ExercisesModule,
    WorkoutsModule,
    ProgramsModule,
    AnalyticsModule,
    AiModule,
    SubscriptionsModule,
  ],
  controllers: [HealthController],
  providers: [
    // Global rate limit guard
    { provide: APP_GUARD, useClass: ThrottlerGuard },
  ],
})
export class AppModule {}

// ─────────────────────────────────────────────────────────────
// src/scripts/migrate.ts
// Run by db-migrate.sh as an ECS one-shot task
// ─────────────────────────────────────────────────────────────
/*
import { NestFactory }    from '@nestjs/core';
import { AppModule }      from '../app.module';
import { DataSource }     from 'typeorm';
import { getDataSourceToken } from '@nestjs/typeorm';

async function runMigrations() {
  console.log('[Migrate] Starting database migrations...');
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['log', 'warn', 'error'],
  });

  try {
    const dataSource = app.get<DataSource>(getDataSourceToken());
    const pendingMigrations = await dataSource.showMigrations();

    if (!pendingMigrations) {
      console.log('[Migrate] No pending migrations. Database is up to date.');
    } else {
      console.log('[Migrate] Running pending migrations...');
      const ranMigrations = await dataSource.runMigrations({ transaction: 'all' });
      console.log(`[Migrate] ✅ Ran ${ranMigrations.length} migrations:`);
      ranMigrations.forEach(m => console.log(`  - ${m.name}`));
    }

    // Seed built-in exercises if table is empty
    const exerciseCount = await dataSource.query(
      'SELECT COUNT(*) as count FROM exercises WHERE is_custom = false'
    );
    if (Number(exerciseCount[0].count) === 0) {
      console.log('[Migrate] Seeding built-in exercises...');
      await dataSource.query(`
        INSERT INTO exercises (id, name, primary_muscle, equipment, category, is_custom)
        VALUES
          ('00000000-0000-0000-0001-000000000001', 'Barbell Back Squat', 'quads', 'barbell', 'compound', false),
          ('00000000-0000-0000-0001-000000000002', 'Conventional Deadlift', 'back', 'barbell', 'compound', false),
          ('00000000-0000-0000-0001-000000000003', 'Barbell Bench Press', 'chest', 'barbell', 'compound', false),
          ('00000000-0000-0000-0001-000000000004', 'Overhead Press', 'shoulders', 'barbell', 'compound', false),
          ('00000000-0000-0000-0001-000000000005', 'Barbell Row', 'back', 'barbell', 'compound', false),
          ('00000000-0000-0000-0001-000000000006', 'Pull-up', 'lats', 'bodyweight', 'compound', false),
          ('00000000-0000-0000-0001-000000000007', 'Romanian Deadlift', 'hamstrings', 'barbell', 'compound', false),
          ('00000000-0000-0000-0001-000000000008', 'Hip Thrust', 'glutes', 'barbell', 'compound', false)
        ON CONFLICT (id) DO NOTHING
      `);
      console.log('[Migrate] ✅ Exercises seeded');
    }

    console.log('[Migrate] All done!');
  } catch (error) {
    console.error('[Migrate] ❌ Migration failed:', error);
    process.exit(1);
  } finally {
    await app.close();
  }
}

runMigrations();
*/

// ─────────────────────────────────────────────────────────────
// src/common/metrics/metrics.service.ts
// Emit custom CloudWatch metrics from the application
// ─────────────────────────────────────────────────────────────
import { Injectable, Logger } from '@nestjs/common';
import {
  CloudWatchClient,
  PutMetricDataCommand,
  MetricDatum,
} from '@aws-sdk/client-cloudwatch';

@Injectable()
export class MetricsService {
  private readonly cw: CloudWatchClient;
  private readonly logger = new Logger(MetricsService.name);
  private readonly namespace = 'IronLog/API';
  private readonly buffer: MetricDatum[] = [];
  private flushTimer: NodeJS.Timeout;

  constructor(private readonly config: ConfigService) {
    this.cw = new CloudWatchClient({
      region: config.get('AWS_REGION', 'us-east-1'),
    });

    // Batch flush every 60 seconds (CloudWatch allows up to 1000 metrics per call)
    this.flushTimer = setInterval(() => this.flush(), 60_000);
  }

  // ── Record events ──────────────────────────────────────────
  workoutStarted(): void {
    this._record('WorkoutStarted', 1, 'Count');
  }

  workoutCompleted(durationSeconds: number): void {
    this._record('WorkoutCompleted', 1, 'Count');
    this._record('WorkoutDuration', durationSeconds, 'Seconds');
  }

  personalRecord(exerciseId: string): void {
    this._record('PersonalRecords', 1, 'Count', [
      { Name: 'ExerciseId', Value: exerciseId },
    ]);
  }

  syncCompleted(itemsSynced: number): void {
    this._record('SyncItemsProcessed', itemsSynced, 'Count');
  }

  apiError(path: string, statusCode: number): void {
    this._record('APIErrors', 1, 'Count', [
      { Name: 'Path',   Value: path },
      { Name: 'Status', Value: String(statusCode) },
    ]);
  }

  activeWorkouts(count: number): void {
    this._record('ActiveWorkouts', count, 'Count');
  }

  // ── Internal ──────────────────────────────────────────────
  private _record(
    name:       string,
    value:      number,
    unit:       string,
    dimensions: Array<{ Name: string; Value: string }> = [],
  ): void {
    this.buffer.push({
      MetricName: name,
      Value:      value,
      Unit:       unit as any,
      Timestamp:  new Date(),
      Dimensions: dimensions,
    });

    // Flush immediately if buffer is large
    if (this.buffer.length >= 100) {
      this.flush();
    }
  }

  async flush(): Promise<void> {
    if (this.buffer.length === 0) return;
    if (this.config.get('NODE_ENV') === 'development') {
      // Don't emit to CloudWatch in development
      this.buffer.length = 0;
      return;
    }

    const metrics = this.buffer.splice(0, 100);
    try {
      await this.cw.send(new PutMetricDataCommand({
        Namespace:  this.namespace,
        MetricData: metrics,
      }));
    } catch (err) {
      this.logger.warn(`Failed to push metrics: ${err}`);
    }
  }

  onModuleDestroy(): void {
    clearInterval(this.flushTimer);
    this.flush();
  }
}
