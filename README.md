# 🏋️ IronLog — Advanced Strength Training App

> A production-grade, offline-first strength training app built with Flutter + NestJS.
> Inspired by Liftosaur, Strong, Hevy, and JuggernautAI.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)](https://flutter.dev)
[![NestJS](https://img.shields.io/badge/NestJS-10.x-red)](https://nestjs.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue)](https://postgresql.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## ✨ Features

| Feature | Status | Notes |
|---------|--------|-------|
| Workout logging | ✅ | One-handed optimized, haptic feedback |
| Progressive overload engine | ✅ | 6 built-in strategies + custom scripting |
| Exercise library | ✅ | 20+ built-in, unlimited custom |
| Analytics & charts | ✅ | e1RM, volume, muscle heatmap, consistency |
| Program builder | ✅ | Visual + scripting mode (Pro) |
| Plate calculator | ✅ | kg/lbs, all bar types, visual display |
| Rest timer | ✅ | Background, haptics, notifications |
| Offline-first sync | ✅ | Works fully offline, syncs when online |
| AdMob integration | ✅ | Never interrupts workouts |
| RevenueCat subscriptions | ✅ | Monthly / Yearly / Lifetime |
| AI coaching | ✅ | Progression analysis, program generation |
| Google / Apple / Email auth | ✅ | JWT + refresh tokens |
| Dark mode | ✅ | Dark-first design |
| Docker deployment | ✅ | One-command setup |

---

## 🏗️ Architecture

```
ironlog/
├── frontend/                    # Flutter app
│   └── lib/
│       ├── core/
│       │   ├── constants/       # App constants
│       │   ├── network/         # Dio API client
│       │   ├── router/          # GoRouter configuration
│       │   └── storage/         # Drift SQLite database
│       ├── data/
│       │   ├── datasources/     # Local (SQLite) + Remote (API)
│       │   ├── models/          # JSON models
│       │   └── repositories/   # Repository implementations
│       ├── domain/
│       │   ├── entities/        # Core domain objects (Freezed)
│       │   ├── repositories/   # Repository interfaces
│       │   └── usecases/       # Business logic
│       ├── presentation/
│       │   ├── blocs/           # Riverpod StateNotifiers
│       │   ├── pages/           # Full screens
│       │   ├── widgets/         # Reusable UI components
│       │   └── themes/          # Material 3 themes
│       └── services/
│           ├── ad_manager.dart      # AdMob with workout-safe rules
│           ├── subscription_service.dart # RevenueCat
│           ├── sync_service.dart    # Offline-first sync
│           └── notification_service.dart
│
├── backend/                     # NestJS API
│   └── src/
│       ├── auth/                # JWT, Google, Apple auth
│       ├── users/               # User profiles
│       ├── exercises/           # Exercise library
│       ├── workouts/            # Workout CRUD + sync
│       ├── programs/            # Program management + scripting
│       ├── analytics/           # Aggregated analytics
│       ├── ai/                  # AI coaching engine
│       ├── subscriptions/       # RevenueCat webhooks
│       └── common/              # Guards, filters, interceptors
│
├── docker/
│   ├── docker-compose.yml
│   └── postgres/
│       └── init.sql
│
└── docs/
    └── API.md
```

---

## 🚀 Quick Start

### Prerequisites

| Tool | Version |
|------|---------|
| Flutter | 3.16+ |
| Dart | 3.2+ |
| Node.js | 20+ |
| Docker | 24+ |
| PostgreSQL | 16+ (via Docker) |

### 1. Clone & Setup

```bash
git clone https://github.com/yourname/ironlog.git
cd ironlog
```

### 2. Start Backend (Docker)

```bash
cd docker
cp ../.env.example .env
# Edit .env with your secrets

docker compose up -d postgres redis
cd ../backend
npm install
npm run migration:run
npm run start:dev
```

### 3. Run Flutter App

```bash
cd frontend
flutter pub get
flutter run
```

### 4. Production Deploy

```bash
# Full stack
cd docker
docker compose --profile production up -d
```

---

## 🔑 Environment Variables

Create `backend/.env`:

```env
# Server
NODE_ENV=development
PORT=3000

# Database
DB_HOST=localhost
DB_PORT=5432
DB_USER=ironlog
DB_PASSWORD=your_secure_password
DB_NAME=ironlog

# Auth
JWT_SECRET=your_jwt_secret_min_32_chars
JWT_REFRESH_SECRET=your_refresh_secret_min_32_chars
JWT_EXPIRES_IN=1h

# OAuth
GOOGLE_CLIENT_ID=your_google_client_id
APPLE_CLIENT_ID=your_apple_bundle_id

# Optional
REDIS_HOST=localhost
REDIS_PORT=6379
CORS_ORIGIN=*
```

---

## 📱 Flutter Configuration

### AdMob Setup

1. Replace test IDs in `lib/services/ad_manager.dart`:
```dart
static String get banner => Platform.isAndroid
    ? 'ca-app-pub-XXXX/XXXX'   // Your Android banner ID
    : 'ca-app-pub-XXXX/XXXX';  // Your iOS banner ID
```

2. Add App ID to `AndroidManifest.xml`:
```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX"/>
```

3. Add to `Info.plist` (iOS):
```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX</string>
```

### RevenueCat Setup

1. Create products in App Store Connect / Google Play Console
2. Set up RevenueCat dashboard
3. Update API key in app initialization:
```dart
await SubscriptionService.instance.initialize(
  revenueCatApiKey: 'appl_XXXX', // or 'goog_XXXX'
  userId: currentUser.id,
);
```

### Google Sign In

1. Add `google-services.json` to `android/app/`
2. Add `GoogleService-Info.plist` to `ios/Runner/`

---

## 💰 Monetization Strategy

### Ad Placement Rules (STRICT)

```
✅ ALLOWED:           ❌ NEVER:
Dashboard             Active workout screen
Workout history       Set logging
Analytics             Rest timer
Exercise library      Any modal during workout
Workout complete      
Program marketplace   
```

The `AdManager` enforces these rules programmatically:
```dart
// This check runs BEFORE every ad display
if (isWorkoutActive) {
  debugPrint('[AdManager] Ad blocked: workout active');
  return false;
}
```

### Subscription Tiers

| Tier | Price | Key Features |
|------|-------|-------------|
| Free | $0 | Basic logging, 3 programs, ads |
| Pro Monthly | $9.99/mo | All features, no ads |
| Pro Yearly | $59.99/yr | All features, save 50% |
| Lifetime | $149.99 | All features forever |

### Premium Features

- ❌ Ads removed
- 🤖 AI coaching & program generation
- 📊 Advanced analytics (muscle heatmap, fatigue scores)
- ☁️ Unlimited cloud backup
- 📤 Export (CSV, PDF)
- 📚 Premium program library
- 💻 Custom progression scripting
- 💪 Recovery metrics

---

## 🧮 Progression Scripting Engine

Built-in scripts:

```javascript
// Linear Progression
if (completedReps >= reps && completedSets >= sets) {
  weight = weight + 2.5;
}

// 5/3/1 Periodization
var trainingMax = percentOf1RM(0.90);
var pcts = [0.65, 0.70, 0.75, 0.60]; // 3/3/3, 3/1/3, deload
weight = roundToPlates(trainingMax * pcts[(week - 1) % 4]);

// RPE-Based Auto-Regulation
if (rpe > 9.0) { weight = weight * 0.95; }
else if (rpe < 7.0) { weight = weight * 1.05; }
```

Available variables: `weight`, `sets`, `reps`, `completedReps`,
`completedSets`, `failedSets`, `rpe`, `week`, `day`, `sessionCount`,
`lastWeight`, `pr1RM`

Helper functions: `percentOf1RM(pct)`, `roundToPlates(weight)`, `deloadWeight(pct)`

---

## 🤖 AI Coaching System

The `AiCoachingService` provides:

1. **Progression Analysis** — Detects plateaus, recommends weight increases
2. **Deload Detection** — Identifies accumulated fatigue patterns
3. **Program Generation** — Creates personalized programs based on goal + frequency
4. **Recovery Advice** — Muscle group recovery estimation

No external AI API required — all logic runs server-side with statistical analysis.

---

## 📊 Database Schema

Key tables:
- `users` — Profiles, subscription status, OAuth IDs
- `exercises` — Built-in + custom exercise library
- `workouts` — Sessions with status, date, program link
- `workout_exercises` — Exercises within each session
- `workout_sets` — Individual sets with targets + logged values
- `personal_records` — PRs with e1RM tracking
- `programs` — Training programs with scripting
- `program_days/exercises` — Program structure
- `exercise_history` — Denormalized for fast analytics queries

Materialized view: `weekly_volume_by_muscle` — refreshed nightly for O(1) analytics queries.

---

## 🧪 Testing

```bash
# Flutter
cd frontend
flutter test                        # Unit tests
flutter test integration_test/       # Integration tests

# Backend
cd backend
npm run test                        # Unit tests
npm run test:e2e                    # End-to-end tests
npm run test:cov                    # Coverage report
```

---

## 📦 Building for Production

### Android

```bash
cd frontend
flutter build apk --release         # APK
flutter build appbundle --release   # AAB (recommended for Play Store)
```

### iOS

```bash
cd frontend
flutter build ios --release
# Then archive in Xcode
```

### Backend

```bash
cd backend
npm run build
# Or use Docker:
docker build -t ironlog-api .
```

---

## 🔒 Security & GDPR

- JWT access tokens (1 hour expiry) + refresh tokens (30 days)
- Passwords hashed with bcrypt (12 rounds)
- GDPR: Account deletion anonymizes data, purged after 30 days
- Rate limiting: 10 req/s short, 200 req/min long
- SQL injection protected by TypeORM parameterized queries
- All API endpoints require authentication (except auth routes)

---

## 🗺️ Roadmap

- [ ] Apple Watch / Wear OS companion app
- [ ] Apple Health / Google Fit sync
- [ ] Barcode scanner for food logging
- [ ] Social features (follow, share routines)
- [ ] Program marketplace
- [ ] Video exercise demonstrations
- [ ] RPE coach (camera-based form check — future)
- [ ] Periodization calendar view
- [ ] Custom equipment profiles

---

## 📄 License

MIT — see [LICENSE](LICENSE)

---

## 🙏 Credits

Inspired by:
- [Liftosaur](https://liftosaur.com) — Scripting system
- [Strong](https://www.strong.app) — UX simplicity
- [Hevy](https://hevy.app) — Social features
- [JuggernautAI](https://juggernautai.app) — AI coaching

Built with: Flutter, NestJS, Drift, fl_chart, RevenueCat, Google AdMob
