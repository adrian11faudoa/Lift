# ─────────────────────────────────────────────────────────────
# Multi-stage Dockerfile for NestJS API
# ─────────────────────────────────────────────────────────────

# ── Stage 1: Dependencies ─────────────────────────────────────
FROM node:20-alpine AS dependencies
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production && \
    cp -R node_modules /app/node_modules_prod && \
    npm ci

# ── Stage 2: Builder ──────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=dependencies /app/node_modules ./node_modules
COPY . .
RUN npm run build && \
    npm prune --production

# ── Stage 3: Production ───────────────────────────────────────
FROM node:20-alpine AS production
ENV NODE_ENV=production
WORKDIR /app

# Security: run as non-root
RUN addgroup -g 1001 -S nodejs && \
    adduser  -S nestjs -u 1001

# Copy built artifacts
COPY --from=builder --chown=nestjs:nodejs /app/dist    ./dist
COPY --from=builder --chown=nestjs:nodejs /app/node_modules ./node_modules
COPY --chown=nestjs:nodejs package.json ./

USER nestjs
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "dist/main.js"]
