# KamaiPlus Admin Console

A Flutter Web internal tool for the KamaiPlus team — merchant directory, Pro subscription
grants/revokes, discount coupons, and broadcast/config push. Connects to the same Firebase
project (`kamaiplus`) as the Android POS app; it's a separate deployable, not a mobile build
target of that app.

Live at: https://kamaiplus-admin.web.app

## Access

Sign-in is Firebase Auth (Google or email/password), but authentication alone does not grant
admin power — a Firestore document at `admins/{your-uid}` must exist. That document can only
be created via direct Firebase Console/CLI access to the `kamaiplus` project (see
`firestore.rules`'s `isAdmin()` — it's deliberately never client-writable). See the repo root's
`DEVELOPMENT_LOG.md` for how the first admin was bootstrapped.

## Data model

This console never talks to its own backend — it reads/writes the same Firestore collections
the mobile app already dual-syncs "for Web Admin Portal" (`sales`, `products`, `customers`,
`businesses`, `merchants` at the root, alongside the per-merchant subcollections the app uses
for its own local sync). `lib/services/admin_firestore_service.dart` is the single place every
screen goes through — see it for the exact collections and methods available.

## Local development

```
flutter pub get
flutter run -d chrome
```

## Deploying

```
flutter build web --release
firebase deploy --only hosting:admin --project kamaiplus
```

Firestore rules for this project live at the repo root (`../firestore.rules`), not here —
they're shared with the mobile app's data. Deploy them with:

```
firebase deploy --only firestore:rules --project kamaiplus
```
