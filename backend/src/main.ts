// ─────────────────────────────────────────────────────────────
// src/main.ts
// ─────────────────────────────────────────────────────────────
import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import { ConfigService } from '@nestjs/config';
import helmet from 'helmet';
import compression from 'compression';
import { AppModule } from './app.module';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { TransformInterceptor } from './common/interceptors/transform.interceptor';
import { LoggingInterceptor } from './common/interceptors/logging.interceptor';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    logger: ['log', 'warn', 'error'],
  });

  const config = app.get(ConfigService);
  const port   = config.get<number>('PORT', 3000);
  const logger = new Logger('Bootstrap');

  // Security
  app.use(helmet());
  app.use(compression());
  app.enableCors({
    origin:      config.get('CORS_ORIGIN', '*'),
    credentials: true,
  });

  // Global pipes / filters / interceptors
  app.useGlobalPipes(new ValidationPipe({
    whitelist:        true,
    transform:        true,
    forbidNonWhitelisted: true,
    transformOptions: { enableImplicitConversion: true },
  }));
  app.useGlobalFilters(new HttpExceptionFilter());
  app.useGlobalInterceptors(
    new LoggingInterceptor(),
    new TransformInterceptor(),
  );

  // Swagger
  const swaggerConfig = new DocumentBuilder()
    .setTitle('IronLog API')
    .setDescription('Advanced strength training app REST API')
    .setVersion('1.0')
    .addBearerAuth()
    .build();
  const document = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/docs', app, document);

  await app.listen(port);
  logger.log(`IronLog API running on port ${port}`);
  logger.log(`Swagger docs: http://localhost:${port}/api/docs`);
}
bootstrap();
