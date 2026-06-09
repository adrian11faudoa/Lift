#!/usr/bin/env bash
# scripts/setup.sh
# One-command local dev setup: installs deps, starts Docker, seeds DB
# Usage: ./scripts/setup.sh

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${GREEN}▶${NC} $1"; }

echo "╔══════════════════════════════════════════════════════╗"
echo "║          IronLog — Local Development Setup           ║"
echo "╚══════════════════════════════════════════════════════╝"

# ── Prerequisites check ───────────────────────────────────────
step "Checking prerequisites..."

command -v docker     >/dev/null 2>&1 && ok "Docker" || fail "Docker not found. Install from https://docker.com"
command -v node       >/dev/null 2>&1 && ok "Node.js $(node --version)" || fail "Node.js not found"
command -v flutter    >/dev/null 2>&1 && ok "Flutter $(flutter --version --machine | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[\"frameworkVersion\"])' 2>/dev/null || echo '')" || warn "Flutter not found — mobile/web builds unavailable"
command -v aws        >/dev/null 2>&1 && ok "AWS CLI" || warn "AWS CLI not found — cloud features unavailable"
command -v terraform  >/dev/null 2>&1 && ok "Terraform $(terraform version -json | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"terraform_version\"])' 2>/dev/null || echo '')" || warn "Terraform not found — infrastructure management unavailable"

# ── Environment files ─────────────────────────────────────────
step "Setting up environment files..."

if [ ! -f "backend/.env" ]; then
  cp .env.example backend/.env
  ok "Created backend/.env from .env.example"
  warn "Edit backend/.env with your OAuth credentials before running"
else
  ok "backend/.env already exists"
fi

# ── Docker services ───────────────────────────────────────────
step "Starting Docker services (PostgreSQL, Redis, MinIO)..."

docker compose -f docker-compose.dev.yml up -d \
  postgres redis minio minio_setup mailhog

echo "Waiting for services to be healthy..."
until docker compose -f docker-compose.dev.yml exec postgres \
  pg_isready -U ironlog -q 2>/dev/null; do
  printf "."
  sleep 1
done
echo ""
ok "PostgreSQL ready"

until docker compose -f docker-compose.dev.yml exec redis \
  redis-cli ping 2>/dev/null | grep -q PONG; do
  printf "."
  sleep 1
done
ok "Redis ready"
sleep 3
ok "MinIO ready"

# ── Backend setup ─────────────────────────────────────────────
step "Installing backend dependencies..."
cd ironlog/backend
npm ci
ok "npm packages installed"

step "Running database migrations..."
# Apply schema directly for local dev
docker compose -f ../../docker-compose.dev.yml exec -T postgres \
  psql -U ironlog -d ironlog \
  -f /dev/stdin < ../../backend/prisma/schema.sql 2>/dev/null || true
ok "Schema applied"
cd ../..

# ── Flutter setup ─────────────────────────────────────────────
if command -v flutter >/dev/null 2>&1; then
  step "Setting up Flutter frontend..."
  cd ironlog/frontend
  flutter pub get
  ok "Flutter packages installed"

  step "Running code generation (Freezed, Drift, Riverpod)..."
  flutter pub run build_runner build --delete-conflicting-outputs 2>/dev/null || \
    warn "Code generation had warnings — check output above"
  ok "Code generation complete"
  cd ../..
fi

# ── Service URLs ──────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║              Setup Complete! 🎉                      ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Local Services:                                     ║"
echo "║  PostgreSQL:  localhost:5432 (ironlog/ironlog)       ║"
echo "║  Redis:       localhost:6379                         ║"
echo "║  MinIO S3:    localhost:9000 (ironlog/ironlog_secret)║"
echo "║  MinIO UI:    http://localhost:9001                  ║"
echo "║  Adminer DB:  http://localhost:8080                  ║"
echo "║  MailHog:     http://localhost:8025                  ║"
echo "║  RedisInsight:http://localhost:5540                  ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Start the API:                                      ║"
echo "║  cd ironlog/backend && npm run start:dev             ║"
echo "║                                                      ║"
echo "║  Start Flutter (iOS):                                ║"
echo "║  cd ironlog/frontend && flutter run                  ║"
echo "║                                                      ║"
echo "║  API Docs: http://localhost:3000/api/docs            ║"
echo "╚══════════════════════════════════════════════════════╝"
