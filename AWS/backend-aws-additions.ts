// ─────────────────────────────────────────────────────────────
// src/common/redis/redis.module.ts
// Redis client for caching, rate limiting, and session storage
// ─────────────────────────────────────────────────────────────
import { Module, Global } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, RedisClientType } from 'redis';

export const REDIS_CLIENT = 'REDIS_CLIENT';

@Global()
@Module({
  providers: [
    {
      provide: REDIS_CLIENT,
      useFactory: async (config: ConfigService): Promise<RedisClientType> => {
        const client = createClient({
          socket: {
            host: config.get('REDIS_HOST', 'localhost'),
            port: config.get<number>('REDIS_PORT', 6379),
            tls:  config.get('REDIS_TLS') === 'true',
          },
          password: config.get('REDIS_AUTH_TOKEN'),
        }) as RedisClientType;

        client.on('error', (err) => console.error('[Redis] Error:', err));
        client.on('connect', () => console.log('[Redis] Connected'));

        await client.connect();
        return client;
      },
      inject: [ConfigService],
    },
  ],
  exports: [REDIS_CLIENT],
})
export class RedisModule {}

// ─────────────────────────────────────────────────────────────
// src/common/cache/cache.service.ts
// Typed Redis cache wrapper
// ─────────────────────────────────────────────────────────────
import { Injectable, Inject } from '@nestjs/common';
import { RedisClientType } from 'redis';

@Injectable()
export class CacheService {
  constructor(
    @Inject(REDIS_CLIENT) private readonly redis: RedisClientType,
  ) {}

  async get<T>(key: string): Promise<T | null> {
    const value = await this.redis.get(key);
    if (!value) return null;
    try {
      return JSON.parse(value) as T;
    } catch {
      return value as unknown as T;
    }
  }

  async set(key: string, value: unknown, ttlSeconds?: number): Promise<void> {
    const serialized = JSON.stringify(value);
    if (ttlSeconds) {
      await this.redis.setEx(key, ttlSeconds, serialized);
    } else {
      await this.redis.set(key, serialized);
    }
  }

  async del(key: string): Promise<void> {
    await this.redis.del(key);
  }

  async delPattern(pattern: string): Promise<void> {
    const keys = await this.redis.keys(pattern);
    if (keys.length > 0) {
      await this.redis.del(keys);
    }
  }

  async incr(key: string, ttlSeconds?: number): Promise<number> {
    const value = await this.redis.incr(key);
    if (ttlSeconds && value === 1) {
      await this.redis.expire(key, ttlSeconds);
    }
    return value;
  }

  async hSet(key: string, field: string, value: unknown): Promise<void> {
    await this.redis.hSet(key, field, JSON.stringify(value));
  }

  async hGet<T>(key: string, field: string): Promise<T | null> {
    const val = await this.redis.hGet(key, field);
    if (!val) return null;
    return JSON.parse(val) as T;
  }
}

// ─────────────────────────────────────────────────────────────
// src/common/storage/s3.service.ts
// AWS S3 service for media uploads (profile pics, exercise videos)
// ─────────────────────────────────────────────────────────────
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
  HeadObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import * as path from 'path';
import * as crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';

@Injectable()
export class S3Service {
  private readonly s3: S3Client;
  private readonly bucket: string;
  private readonly cdnDomain: string;

  constructor(private readonly config: ConfigService) {
    this.s3 = new S3Client({
      region: config.get('AWS_REGION', 'us-east-1'),
    });
    this.bucket    = config.get('S3_MEDIA_BUCKET', 'ironlog-dev-media');
    this.cdnDomain = config.get('CDN_DOMAIN', '');
  }

  // ── PRESIGNED UPLOAD URL (client uploads directly to S3) ──
  async getUploadUrl(params: {
    userId:      string;
    category:    'avatars' | 'exercises' | 'exports';
    filename:    string;
    contentType: string;
    maxSizeMB?:  number;
  }): Promise<{ uploadUrl: string; key: string; publicUrl: string }> {
    const ext = path.extname(params.filename).toLowerCase();
    const key = `${params.category}/${params.userId}/${uuidv4()}${ext}`;

    const command = new PutObjectCommand({
      Bucket:      this.bucket,
      Key:         key,
      ContentType: params.contentType,
      Metadata: {
        userId:      params.userId,
        originalName:params.filename,
        uploadedAt:  new Date().toISOString(),
      },
    });

    const uploadUrl = await getSignedUrl(this.s3, command, {
      expiresIn: 300,    // 5 minutes to upload
    });

    return {
      uploadUrl,
      key,
      publicUrl: this.getPublicUrl(key),
    };
  }

  // ── PRESIGNED DOWNLOAD URL (for private files) ────────────
  async getDownloadUrl(key: string, expiresInSeconds = 3600): Promise<string> {
    const command = new GetObjectCommand({
      Bucket: this.bucket,
      Key:    key,
    });
    return getSignedUrl(this.s3, command, { expiresIn: expiresInSeconds });
  }

  // ── DELETE OBJECT ─────────────────────────────────────────
  async deleteObject(key: string): Promise<void> {
    await this.s3.send(new DeleteObjectCommand({
      Bucket: this.bucket,
      Key:    key,
    }));
  }

  // ── CHECK OBJECT EXISTS ───────────────────────────────────
  async objectExists(key: string): Promise<boolean> {
    try {
      await this.s3.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
      return true;
    } catch {
      return false;
    }
  }

  // ── PUBLIC URL ────────────────────────────────────────────
  getPublicUrl(key: string): string {
    if (this.cdnDomain) {
      return `https://${this.cdnDomain}/${key}`;
    }
    return `https://${this.bucket}.s3.amazonaws.com/${key}`;
  }
}

// ─────────────────────────────────────────────────────────────
// src/common/email/email.service.ts
// AWS SES email sending for auth emails and receipts
// ─────────────────────────────────────────────────────────────
import { SESv2Client, SendEmailCommand } from '@aws-sdk/client-sesv2';

@Injectable()
export class EmailService {
  private readonly ses: SESv2Client;
  private readonly fromEmail: string;
  private readonly fromName:  string;

  constructor(private readonly config: ConfigService) {
    this.ses = new SESv2Client({
      region: config.get('AWS_REGION', 'us-east-1'),
    });
    this.fromEmail = config.get('FROM_EMAIL', 'noreply@ironlog.app');
    this.fromName  = 'IronLog';
  }

  async sendWelcomeEmail(to: string, displayName: string): Promise<void> {
    await this._send({
      to,
      subject: '💪 Welcome to IronLog!',
      html: `
        <div style="font-family: Inter, sans-serif; max-width: 600px; margin: 0 auto; background: #0A0A0F; color: #F1F1F3; padding: 40px; border-radius: 12px;">
          <h1 style="color: #2563EB;">Welcome to IronLog, ${displayName}!</h1>
          <p>Your strength training journey starts now.</p>
          <p>Log your first workout to track your progress and start building your training history.</p>
          <a href="https://app.ironlog.app" style="display: inline-block; background: #2563EB; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; font-weight: 700;">Start Training</a>
          <hr style="border-color: #2A2A35; margin: 32px 0;">
          <p style="color: #8B8B9A; font-size: 12px;">IronLog · <a href="https://ironlog.app/unsubscribe" style="color: #8B8B9A;">Unsubscribe</a></p>
        </div>
      `,
    });
  }

  async sendPasswordResetEmail(to: string, resetToken: string): Promise<void> {
    const resetUrl = `https://app.ironlog.app/reset-password?token=${resetToken}`;
    await this._send({
      to,
      subject: '🔐 Reset your IronLog password',
      html: `
        <div style="font-family: Inter, sans-serif; max-width: 600px; margin: 0 auto; padding: 40px;">
          <h2>Password Reset</h2>
          <p>Click the button below to reset your password. This link expires in 1 hour.</p>
          <a href="${resetUrl}" style="display: inline-block; background: #2563EB; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none;">Reset Password</a>
          <p style="color: #6B7280; font-size: 12px; margin-top: 24px;">If you didn't request this, ignore this email.</p>
        </div>
      `,
    });
  }

  async sendPRNotificationEmail(to: string, exerciseName: string, weight: number, reps: number): Promise<void> {
    await this._send({
      to,
      subject: `🏆 New PR: ${exerciseName}!`,
      html: `
        <div style="font-family: Inter, sans-serif; max-width: 600px; margin: 0 auto; padding: 40px;">
          <h2 style="color: #FFD700;">🏆 New Personal Record!</h2>
          <p>You just set a new PR on <strong>${exerciseName}</strong>:</p>
          <div style="background: #111118; padding: 20px; border-radius: 8px; margin: 20px 0;">
            <span style="font-size: 32px; font-weight: 800; color: #2563EB;">${weight}kg × ${reps} reps</span>
          </div>
          <a href="https://app.ironlog.app/analytics" style="background: #2563EB; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none;">View Analytics</a>
        </div>
      `,
    });
  }

  private async _send(params: {
    to:      string;
    subject: string;
    html:    string;
    text?:   string;
  }): Promise<void> {
    const command = new SendEmailCommand({
      FromEmailAddress: `${this.fromName} <${this.fromEmail}>`,
      Destination: { ToAddresses: [params.to] },
      Content: {
        Simple: {
          Subject: { Data: params.subject, Charset: 'UTF-8' },
          Body: {
            Html: { Data: params.html,          Charset: 'UTF-8' },
            Text: { Data: params.text ?? '',    Charset: 'UTF-8' },
          },
        },
      },
    });

    try {
      await this.ses.send(command);
    } catch (error) {
      console.error('[EmailService] Failed to send email:', error);
      // Don't throw — email failures shouldn't break the API
    }
  }
}

// ─────────────────────────────────────────────────────────────
// src/common/interceptors/logging.interceptor.ts
// Structured request/response logging for CloudWatch
// ─────────────────────────────────────────────────────────────
import {
  Injectable, NestInterceptor, ExecutionContext, CallHandler, Logger,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { Request, Response } from 'express';

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  private readonly logger = new Logger('HTTP');

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const req:    Request  = context.switchToHttp().getRequest();
    const res:    Response = context.switchToHttp().getResponse();
    const start = Date.now();

    return next.handle().pipe(
      tap({
        next: () => {
          const duration = Date.now() - start;
          this.logger.log(JSON.stringify({
            type:     'request',
            method:   req.method,
            path:     req.path,
            status:   res.statusCode,
            duration: `${duration}ms`,
            userId:   (req as any).user?.id,
            ip:       req.ip,
          }));
        },
        error: (err) => {
          const duration = Date.now() - start;
          this.logger.error(JSON.stringify({
            type:     'error',
            method:   req.method,
            path:     req.path,
            status:   err.status ?? 500,
            duration: `${duration}ms`,
            error:    err.message,
            userId:   (req as any).user?.id,
          }));
        },
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// src/common/interceptors/transform.interceptor.ts
// Standardize all API responses
// ─────────────────────────────────────────────────────────────
import { map } from 'rxjs/operators';

export interface ApiResponse<T> {
  success: boolean;
  data:    T;
  meta?:   Record<string, unknown>;
}

@Injectable()
export class TransformInterceptor<T>
  implements NestInterceptor<T, ApiResponse<T>>
{
  intercept(
    context: ExecutionContext,
    next: CallHandler,
  ): Observable<ApiResponse<T>> {
    return next.handle().pipe(
      map((data) => ({
        success: true,
        data:    data ?? null,
      })),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// src/common/filters/http-exception.filter.ts
// Standardize error responses
// ─────────────────────────────────────────────────────────────
import {
  ExceptionFilter, Catch, ArgumentsHost, HttpException, HttpStatus,
} from '@nestjs/common';

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx  = host.switchToHttp();
    const res  = ctx.getResponse<Response>();
    const req  = ctx.getRequest<Request>();

    const status = exception instanceof HttpException
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    const message = exception instanceof HttpException
      ? (exception.getResponse() as any).message ?? exception.message
      : 'Internal server error';

    const errorBody = {
      success:   false,
      error:     message,
      status,
      path:      (req as any).url,
      timestamp: new Date().toISOString(),
    };

    if (status >= 500) {
      this.logger.error(`${status} ${(req as any).url}: ${JSON.stringify(exception)}`);
    }

    (res as any).status(status).json(errorBody);
  }
}

// ─────────────────────────────────────────────────────────────
// src/common/decorators/current-user.decorator.ts
// ─────────────────────────────────────────────────────────────
import { createParamDecorator } from '@nestjs/common';

export const CurrentUser = createParamDecorator(
  (data: string | undefined, ctx: ExecutionContext) => {
    const req = ctx.switchToHttp().getRequest();
    const user = req.user;
    return data ? user?.[data] : user;
  },
);

// Usage: @CurrentUser() user: JwtUser
// Usage: @CurrentUser('id') userId: string

// ─────────────────────────────────────────────────────────────
// src/common/guards/subscription.guard.ts
// Block premium-only endpoints for free-tier users
// ─────────────────────────────────────────────────────────────
import { CanActivate, SetMetadata } from '@nestjs/common';
import { Reflector } from '@nestjs/core';

export const PREMIUM_KEY  = 'premium';
export const RequiresPremium = () => SetMetadata(PREMIUM_KEY, true);

@Injectable()
export class SubscriptionGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiresPremium = this.reflector.getAllAndOverride<boolean>(
      PREMIUM_KEY, [context.getHandler(), context.getClass()],
    );
    if (!requiresPremium) return true;

    const { user } = context.switchToHttp().getRequest();
    const premiumTiers = ['proMonthly', 'proYearly', 'lifetime'];
    return premiumTiers.includes(user?.subscription);
  }
}

// Usage:
// @RequiresPremium()
// @Get('ai/recommendations')
// async getAIRecommendations(@CurrentUser('id') userId: string) { ... }

// ─────────────────────────────────────────────────────────────
// src/subscriptions/subscriptions.controller.ts
// RevenueCat webhook handler for subscription events
// ─────────────────────────────────────────────────────────────
import {
  Controller, Post, Body, Headers, HttpCode, HttpStatus, UnauthorizedException, Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as crypto from 'crypto';

@Controller('api/v1/webhooks')
export class SubscriptionsController {
  private readonly logger = new Logger(SubscriptionsController.name);

  constructor(
    @InjectRepository(UserEntity)
    private readonly usersRepo: Repository<UserEntity>,
    private readonly config: ConfigService,
  ) {}

  @Post('revenuecat')
  @HttpCode(HttpStatus.OK)
  async handleRevenueCatWebhook(
    @Body()    body:      any,
    @Headers() headers:   Record<string, string>,
  ) {
    // Verify webhook signature
    const secret    = this.config.get('REVENUECAT_WEBHOOK_SECRET');
    const signature = headers['x-revenuecat-signature'];
    if (secret && signature) {
      const expected = crypto
        .createHmac('sha256', secret)
        .update(JSON.stringify(body))
        .digest('hex');
      if (expected !== signature) {
        throw new UnauthorizedException('Invalid webhook signature');
      }
    }

    const event = body.event;
    const userId = event?.app_user_id;
    if (!userId) return { received: true };

    this.logger.log(`RevenueCat event: ${event.type} for user ${userId}`);

    switch (event.type) {
      case 'INITIAL_PURCHASE':
      case 'RENEWAL':
      case 'PRODUCT_CHANGE': {
        const tier = this._getTierFromProductId(event.product_id);
        const expiry = event.expiration_at_ms
          ? new Date(event.expiration_at_ms)
          : null;
        await this.usersRepo.update(
          { id: userId },
          { subscription: tier, subscriptionExpiry: expiry ?? undefined },
        );
        this.logger.log(`User ${userId} upgraded to ${tier}`);
        break;
      }

      case 'CANCELLATION':
      case 'EXPIRATION': {
        const expiry = event.expiration_at_ms
          ? new Date(event.expiration_at_ms)
          : null;
        // Don't downgrade immediately — wait for expiry
        if (expiry && expiry < new Date()) {
          await this.usersRepo.update({ id: userId }, { subscription: 'free' });
          this.logger.log(`User ${userId} downgraded to free`);
        }
        break;
      }

      case 'BILLING_ISSUE': {
        this.logger.warn(`Billing issue for user ${userId}`);
        // Optionally send email notification
        break;
      }
    }

    return { received: true };
  }

  private _getTierFromProductId(productId: string): string {
    if (productId.includes('lifetime'))   return 'lifetime';
    if (productId.includes('yearly'))     return 'proYearly';
    if (productId.includes('monthly'))    return 'proMonthly';
    return 'free';
  }
}

@Module({
  imports:     [TypeOrmModule.forFeature([UserEntity])],
  controllers: [SubscriptionsController],
})
export class SubscriptionsModule {}
