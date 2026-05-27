// ─────────────────────────────────────────────────────────────
// auth.entity.ts
// ─────────────────────────────────────────────────────────────
import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn } from 'typeorm';

@Entity('users')
export class UserEntity {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  email: string;

  @Column({ nullable: true })
  passwordHash?: string;

  @Column({ nullable: true })
  displayName?: string;

  @Column({ nullable: true })
  avatarUrl?: string;

  @Column({ nullable: true })
  googleId?: string;

  @Column({ nullable: true })
  appleId?: string;

  @Column({ default: 'free' })
  subscription: string;

  @Column({ nullable: true, type: 'timestamptz' })
  subscriptionExpiry?: Date;

  @Column({ nullable: true })
  revenueCatId?: string;

  @Column({ nullable: true, type: 'float' })
  bodyweight?: number;

  @Column({ nullable: true })
  activeProgramId?: string;

  @Column({ default: 1 })
  activeProgramWeek: number;

  @Column({ default: 1 })
  activeProgramDay: number;

  @Column({ default: false })
  isPublicProfile: boolean;

  @Column({ nullable: true, type: 'timestamptz' })
  lastSyncAt?: Date;

  @CreateDateColumn()
  createdAt: Date;
}

// ─────────────────────────────────────────────────────────────
// auth.dto.ts
// ─────────────────────────────────────────────────────────────
import { IsEmail, IsString, MinLength, IsOptional } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class RegisterDto {
  @ApiProperty({ example: 'user@example.com' })
  @IsEmail()
  email: string;

  @ApiProperty({ example: 'SecurePass123!', minLength: 8 })
  @IsString()
  @MinLength(8)
  password: string;

  @ApiPropertyOptional({ example: 'John Doe' })
  @IsOptional()
  @IsString()
  displayName?: string;
}

export class LoginDto {
  @ApiProperty() @IsEmail()    email:    string;
  @ApiProperty() @IsString()   password: string;
}

export class GoogleAuthDto {
  @ApiProperty() @IsString() idToken: string;
}

export class AppleAuthDto {
  @ApiProperty() @IsString()    identityToken: string;
  @ApiPropertyOptional() @IsOptional() @IsString() displayName?: string;
}

export class RefreshTokenDto {
  @ApiProperty() @IsString() refreshToken: string;
}

export class AuthResponseDto {
  accessToken:  string;
  refreshToken: string;
  user: {
    id:           string;
    email:        string;
    displayName?: string;
    avatarUrl?:   string;
    subscription: string;
  };
}

// ─────────────────────────────────────────────────────────────
// auth.service.ts
// ─────────────────────────────────────────────────────────────
import {
  Injectable, UnauthorizedException, ConflictException,
  BadRequestException, Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import * as bcrypt from 'bcryptjs';
import { OAuth2Client } from 'google-auth-library';
import * as appleSignin from 'apple-signin-auth';
import * as crypto from 'crypto';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);
  private readonly googleClient: OAuth2Client;

  constructor(
    @InjectRepository(UserEntity)
    private readonly usersRepo: Repository<UserEntity>,
    private readonly jwtService: JwtService,
    private readonly config: ConfigService,
  ) {
    this.googleClient = new OAuth2Client(
      config.get('GOOGLE_CLIENT_ID'),
    );
  }

  // ── EMAIL / PASSWORD ─────────────────────────────────────────
  async register(dto: RegisterDto): Promise<AuthResponseDto> {
    const existing = await this.usersRepo.findOne({ where: { email: dto.email } });
    if (existing) {
      throw new ConflictException('Email already registered');
    }

    const passwordHash = await bcrypt.hash(dto.password, 12);
    const user = await this.usersRepo.save({
      email:        dto.email,
      passwordHash,
      displayName:  dto.displayName,
      subscription: 'free',
    });

    return this._generateAuthResponse(user);
  }

  async login(dto: LoginDto): Promise<AuthResponseDto> {
    const user = await this.usersRepo.findOne({ where: { email: dto.email } });
    if (!user || !user.passwordHash) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const valid = await bcrypt.compare(dto.password, user.passwordHash);
    if (!valid) {
      throw new UnauthorizedException('Invalid credentials');
    }

    return this._generateAuthResponse(user);
  }

  // ── GOOGLE AUTH ──────────────────────────────────────────────
  async googleAuth(dto: GoogleAuthDto): Promise<AuthResponseDto> {
    let payload: any;
    try {
      const ticket = await this.googleClient.verifyIdToken({
        idToken:  dto.idToken,
        audience: this.config.get('GOOGLE_CLIENT_ID'),
      });
      payload = ticket.getPayload();
    } catch (err) {
      throw new UnauthorizedException('Invalid Google token');
    }

    const { sub: googleId, email, name, picture } = payload;
    if (!email) throw new BadRequestException('Google account has no email');

    let user = await this.usersRepo.findOne({
      where: [{ googleId }, { email }],
    });

    if (user) {
      // Link Google ID if not already linked
      if (!user.googleId) {
        await this.usersRepo.update(user.id, { googleId });
        user.googleId = googleId;
      }
    } else {
      // New user via Google
      user = await this.usersRepo.save({
        email,
        googleId,
        displayName:  name,
        avatarUrl:    picture,
        subscription: 'free',
      });
    }

    return this._generateAuthResponse(user);
  }

  // ── APPLE AUTH ───────────────────────────────────────────────
  async appleAuth(dto: AppleAuthDto): Promise<AuthResponseDto> {
    let applePayload: any;
    try {
      applePayload = await appleSignin.verifyIdToken(dto.identityToken, {
        audience:  this.config.get('APPLE_CLIENT_ID'),
        ignoreExpiration: false,
      });
    } catch (err) {
      throw new UnauthorizedException('Invalid Apple token');
    }

    const { sub: appleId, email } = applePayload;

    let user = await this.usersRepo.findOne({
      where: [{ appleId }, ...(email ? [{ email }] : [])],
    });

    if (user) {
      if (!user.appleId) {
        await this.usersRepo.update(user.id, { appleId });
        user.appleId = appleId;
      }
    } else {
      user = await this.usersRepo.save({
        email:        email || `apple_${appleId}@private.com`,
        appleId,
        displayName:  dto.displayName,
        subscription: 'free',
      });
    }

    return this._generateAuthResponse(user);
  }

  // ── TOKEN REFRESH ────────────────────────────────────────────
  async refreshToken(dto: RefreshTokenDto): Promise<{ accessToken: string }> {
    let payload: any;
    try {
      payload = this.jwtService.verify(dto.refreshToken, {
        secret: this.config.get('JWT_REFRESH_SECRET'),
      });
    } catch {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    const user = await this.usersRepo.findOne({ where: { id: payload.sub } });
    if (!user) throw new UnauthorizedException('User not found');

    const accessToken = this._generateAccessToken(user);
    return { accessToken };
  }

  // ── HELPERS ──────────────────────────────────────────────────
  private _generateAccessToken(user: UserEntity): string {
    return this.jwtService.sign(
      { sub: user.id, email: user.email, subscription: user.subscription },
      { expiresIn: this.config.get('JWT_EXPIRES_IN', '1h') },
    );
  }

  private _generateRefreshToken(user: UserEntity): string {
    return this.jwtService.sign(
      { sub: user.id },
      {
        secret:     this.config.get('JWT_REFRESH_SECRET'),
        expiresIn:  '30d',
      },
    );
  }

  private _generateAuthResponse(user: UserEntity): AuthResponseDto {
    return {
      accessToken:  this._generateAccessToken(user),
      refreshToken: this._generateRefreshToken(user),
      user: {
        id:           user.id,
        email:        user.email,
        displayName:  user.displayName,
        avatarUrl:    user.avatarUrl,
        subscription: user.subscription,
      },
    };
  }

  async getProfile(userId: string): Promise<UserEntity> {
    const user = await this.usersRepo.findOne({ where: { id: userId } });
    if (!user) throw new UnauthorizedException();
    return user;
  }

  async updateProfile(userId: string, updates: Partial<UserEntity>): Promise<UserEntity> {
    // Never allow updating sensitive fields via this method
    const safe = {
      displayName:  updates.displayName,
      avatarUrl:    updates.avatarUrl,
      bodyweight:   updates.bodyweight,
      isPublicProfile: updates.isPublicProfile,
    };
    await this.usersRepo.update(userId, safe);
    return this.getProfile(userId);
  }

  async deleteAccount(userId: string): Promise<void> {
    // GDPR: soft delete — anonymize, then purge after 30 days
    await this.usersRepo.update(userId, {
      email:       `deleted_${userId}@deleted.invalid`,
      passwordHash: undefined,
      googleId:    undefined,
      appleId:     undefined,
      displayName: 'Deleted User',
      avatarUrl:   undefined,
    });
    this.logger.log(`Account deletion requested for user ${userId}`);
  }
}

// ─────────────────────────────────────────────────────────────
// jwt.strategy.ts
// ─────────────────────────────────────────────────────────────
import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest:   ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey:      config.get('JWT_SECRET'),
    });
  }

  async validate(payload: any) {
    return {
      id:           payload.sub,
      email:        payload.email,
      subscription: payload.subscription,
    };
  }
}

// ─────────────────────────────────────────────────────────────
// jwt-auth.guard.ts
// ─────────────────────────────────────────────────────────────
import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}

// ─────────────────────────────────────────────────────────────
// auth.controller.ts
// ─────────────────────────────────────────────────────────────
import {
  Controller, Post, Get, Delete, Body, Request,
  UseGuards, HttpCode, HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';

@ApiTags('auth')
@Controller('api/v1/auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  @Throttle({ short: { limit: 5, ttl: 60000 } })
  @ApiOperation({ summary: 'Register with email/password' })
  async register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  @Post('login')
  @HttpCode(HttpStatus.OK)
  @Throttle({ short: { limit: 10, ttl: 60000 } })
  @ApiOperation({ summary: 'Login with email/password' })
  async login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  @Post('google')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Authenticate with Google ID token' })
  async googleAuth(@Body() dto: GoogleAuthDto) {
    return this.authService.googleAuth(dto);
  }

  @Post('apple')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Authenticate with Apple identity token' })
  async appleAuth(@Body() dto: AppleAuthDto) {
    return this.authService.appleAuth(dto);
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Refresh access token' })
  async refresh(@Body() dto: RefreshTokenDto) {
    return this.authService.refreshToken(dto);
  }

  @Get('me')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @ApiOperation({ summary: 'Get current user profile' })
  async getProfile(@Request() req: any) {
    return this.authService.getProfile(req.user.id);
  }

  @Post('me')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @ApiOperation({ summary: 'Update user profile' })
  async updateProfile(@Request() req: any, @Body() body: any) {
    return this.authService.updateProfile(req.user.id, body);
  }

  @Delete('me')
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Delete account (GDPR)' })
  async deleteAccount(@Request() req: any) {
    return this.authService.deleteAccount(req.user.id);
  }
}

// ─────────────────────────────────────────────────────────────
// auth.module.ts
// ─────────────────────────────────────────────────────────────
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { TypeOrmModule } from '@nestjs/typeorm';

@Module({
  imports: [
    TypeOrmModule.forFeature([UserEntity]),
    PassportModule.register({ defaultStrategy: 'jwt' }),
    JwtModule.registerAsync({
      imports:    [ConfigModule],
      useFactory: (config: ConfigService) => ({
        secret:      config.get('JWT_SECRET'),
        signOptions: { expiresIn: config.get('JWT_EXPIRES_IN', '1h') },
      }),
      inject: [ConfigService],
    }),
  ],
  controllers: [AuthController],
  providers:   [AuthService, JwtStrategy],
  exports:     [AuthService, JwtAuthGuard, JwtStrategy],
})
export class AuthModule {}
