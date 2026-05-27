import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ThrottlerModule } from '@nestjs/throttler';
import { ScheduleModule } from '@nestjs/schedule';
import { BullModule } from '@nestjs/bull';

import { AuthModule }          from './auth/auth.module';
import { UsersModule }         from './users/users.module';
import { ExercisesModule }     from './exercises/exercises.module';
import { WorkoutsModule }      from './workouts/workouts.module';
import { ProgramsModule }      from './programs/programs.module';
import { AnalyticsModule }     from './analytics/analytics.module';
import { AiModule }            from './ai/ai.module';
import { SubscriptionsModule } from './subscriptions/subscriptions.module';

@Module({
  imports: [
    // ── Config ────────────────────────────────────────────────
    ConfigModule.forRoot({
      isGlobal:   true,
      envFilePath: ['.env.local', '.env'],
    }),

    // ── Database (PostgreSQL) ─────────────────────────────────
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (config: ConfigService) => ({
        type:        'postgres',
        host:        config.get('DB_HOST', 'localhost'),
        port:        config.get<number>('DB_PORT', 5432),
        username:    config.get('DB_USER', 'ironlog'),
        password:    config.get('DB_PASSWORD', 'ironlog'),
        database:    config.get('DB_NAME', 'ironlog'),
        entities:    [__dirname + '/**/*.entity{.ts,.js}'],
        synchronize: config.get('NODE_ENV') !== 'production',
        ssl:         config.get('DB_SSL') === 'true'
          ? { rejectUnauthorized: false }
          : false,
        logging:     config.get('NODE_ENV') === 'development',
      }),
      inject: [ConfigService],
    }),

    // ── Rate limiting ─────────────────────────────────────────
    ThrottlerModule.forRoot([{
      name:   'short',
      ttl:    1000,
      limit:  10,
    }, {
      name:   'long',
      ttl:    60000,
      limit:  200,
    }]),

    // ── Scheduler (for analytics jobs) ───────────────────────
    ScheduleModule.forRoot(),

    // ── Feature modules ───────────────────────────────────────
    AuthModule,
    UsersModule,
    ExercisesModule,
    WorkoutsModule,
    ProgramsModule,
    AnalyticsModule,
    AiModule,
    SubscriptionsModule,
  ],
})
export class AppModule {}
