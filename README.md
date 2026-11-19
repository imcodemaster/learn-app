# LearnInCreation — Android app + Django backend

A Udemy-style learning app for **LearnInCreation** (learnincreation.com). Lessons are text, not video, and you publish them from the admin panel.

| Part | Technology | Folder |
| --- | --- | --- |
| Mobile app (Android now, iOS later) | Flutter 3 / Dart | `app/` |
| Backend API + admin panel | Python 3.12, Django 5.2, Django REST Framework | `backend/` |
| Database | PostgreSQL (recommended), MySQL or SQLite | — |
| Payments | Razorpay | — |

## What it does

**Students (app)**
- Sign in with **email + password**, **mobile number + SMS code (OTP)**, or **Google**. They can sign out, sign out of all devices, reset a forgotten password by email code, and delete their account (Google Play requires this).
- Browse and search the catalogue, with filters for category, free or paid, and sort order.
- Open a course to see what they'll learn, the curriculum, requirements and instructor. Free-preview lessons open without enrolling.
- **Enroll** in free courses, or **buy** paid ones with **Razorpay** (UPI, cards, net banking, wallets).
- **Bookmark** courses to save them. Read lessons (Markdown with code, tables and images), mark them complete and track progress in My learning.
- **Study center seat booking**, two kinds:
  - **Course batches**: classroom batches with a time slot and seat map. A student picks a seat and pays the fee, or an advance, or nothing for "pay at the center".
  - **Library desks**: monthly self-study desks by shift (e.g. Morning, Evening, Full day). Shifts whose hours overlap can't double-book the same desk.
  - A seat is held for 10 minutes while the student pays, then released automatically. Booking codes, My bookings, payment history.
- About, Contact (call or email), FAQ, privacy policy and terms. All of these are editable from the admin panel.

**You (admin panel at `/admin/`)**
- Courses and categories: price, original price, image, publish/unpublish, featured, lesson list.
- **Lesson editor**: Markdown with a formatting toolbar and **live preview**. Upload images and paste the generated code into the lesson.
- Study center: batches with a **live seat map showing who sits where**, library shifts with today's desk map, and bookings. You can confirm a booking paid at the center, or cancel it and free the seat, or cancel it and mark it for refund.
- Students: search, block (signs them out everywhere), and give course access manually through Enrollments (e.g. after a cash payment).
- Payments: every Razorpay order, with refund status.
- Site settings (contact details, about text, links, library desk count) and FAQ.

The sample data comes from learnincreation.com: 20 courses, 12 study-center batches with the fees from the site, 3 library shifts and FAQs. Online-course prices and library fees are **samples** — change them in the admin panel.

## Project layout

```
backend/                 Django project
  config/                settings, URLs
  accounts/              users, sign-in (email, OTP, Google), sessions
  courses/               categories, courses, lessons, enrollments, bookmarks, progress
  payments/              Razorpay orders, signature checks, webhook
  studycenter/           batches, library shifts, seat bookings
  core/                  site settings, FAQ, API helpers, sample data, tests
  deploy/                Nginx, systemd and Docker files
app/                     Flutter app
  lib/screens/           all screens
  lib/services/          API calls, Razorpay checkout, Google sign-in
  android/               Android project
.github/workflows/       automatic APK build + backend tests
scripts/windows/         one-click setup and build for Windows
```

---

## Quick start on Windows (one click)

Needs Git for Windows, Python 3.10+ and the Android SDK (installed with Android Studio). If no Java JDK 17+ is found (Android Studio includes one), the script downloads JDK 21 into `%USERPROFILE%\jdk-21`.

1. Double-click **`SETUP-AND-BUILD-ON-WINDOWS.cmd`**. It installs Flutter (into `%USERPROFILE%\flutter`) and the backend packages, creates the database with the sample content and an admin login (`backend\ADMIN-LOGIN.txt`), runs the backend and app tests, builds **`LearnInCreation-WiFi-test.apk`** and starts the backend. Progress is saved in `setup-log.txt`.
2. Install the APK on a phone that is on the **same Wi-Fi** as the PC. If Windows asks whether Python may use the network, allow it on private networks.
3. Later, start the backend again with **`START-BACKEND.cmd`**.
4. To upload the project to GitHub, create an **empty** repository on github.com (no README, .gitignore or license) and double-click **`PUSH-TO-GITHUB.cmd`**. It asks for the repository address the first time, keeps private files (`.env`, the database, `ADMIN-LOGIN.txt`, the APK) out of Git, and opens a GitHub sign-in window on the first upload. Run it again to upload later changes; details are saved in `push-log.txt`.

The Wi-Fi test APK uses this PC's network address over plain http, so it only works at home and must be rebuilt (run the setup again) if the PC's address changes. For the real app, deploy the backend (section 3) and build with your https address: `powershell -ExecutionPolicy Bypass -File scripts\windows\setup_and_build.ps1 -ServerUrl https://api.yourdomain.com`.

---

## 1. Run the backend on your computer

You need **Python 3.12** (python.org; on Windows tick "Add Python to PATH").

**Windows:** open the `backend` folder and double-click `setup_dev.bat`.
**macOS / Linux:** `cd backend && ./setup_dev.sh`

The script installs everything, creates the database, loads the sample content and asks you for an admin email and password. Then start the server:

```bash
cd backend
# Windows: .venv\Scripts\activate      macOS/Linux: . .venv/bin/activate
python manage.py runserver 0.0.0.0:8000
```

- Admin panel: <http://127.0.0.1:8000/admin/>
- API check: <http://127.0.0.1:8000/api/health>

In this local test mode (`.env` → `APP_ENV=local`, `PAYMENTS_MODE=mock`, `SMS_BACKEND=console`):
- **Payments are simulated.** The app shows a "Test payment" dialog and no money moves.
- **OTP codes are shown in the app** and printed in the server window, so no SMS provider is needed.
- Password-reset emails are printed in the server window.

The first setup creates database migration files (`*/migrations/0001_initial.py`). **Keep them** with your project. Future changes to the models then become new migrations instead of clashing with old ones.

Run the backend tests: `python manage.py test`

## 2. Run and build the Android app

1. Install **Flutter** (latest stable; flutter.dev → Get started) and **Android Studio**. Run `flutter doctor` and fix anything it lists.
2. Start the backend (step 1), then:

```bash
cd app
flutter pub get
flutter run                      # Android emulator: talks to http://10.0.2.2:8000
```

On a **real phone** on the same Wi-Fi, find your computer's IP address (e.g. 192.168.1.10). Add it to `DJANGO_ALLOWED_HOSTS` in `backend/.env`, then run:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

(Debug builds allow plain `http://`. Release builds only allow `https://`, which is the safe setting.)

### Build the APK

```bash
cd app
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.learnincreation.com \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

The APK is written to `app/build/app/outputs/flutter-apk/app-release.apk`.

### …or let GitHub build it (no Flutter install needed)

1. Put this whole folder in a GitHub repository (private is fine).
2. Repository → **Settings → Secrets and variables → Actions → Variables**: add `API_BASE_URL`, and optionally `GOOGLE_SERVER_CLIENT_ID`.
3. Push. The **Build Android APK** workflow runs. Open the run and download **learnincreation-apk** under *Artifacts*.

### Signing (do this before sharing the app widely)

Without your own key, release APKs are signed with a temporary debug key. That's fine for testing, but updates won't install over each other and Google sign-in breaks between builds. Create your key once and **keep it safe forever**; the Play Store needs the same key for every update:

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias learnincreation
```

- **Local builds:** copy `release.jks` to `app/android/app/`. Then create `app/android/key.properties` containing `storeFile=release.jks`, `storePassword=…`, `keyAlias=learnincreation` and `keyPassword=…`.
- **GitHub builds:** add the secrets `ANDROID_KEYSTORE_BASE64` (the file as base64: `base64 -w0 release.jks`, or on Windows PowerShell `[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.jks"))`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`.

Never commit `release.jks` or `key.properties`; they're already in `.gitignore`.

---

## 3. Go live

Django needs **Python hosting**. Ordinary PHP shared hosting won't run it. Good options:

- **A small VPS** (Hostinger VPS, DigitalOcean, AWS Lightsail, about ₹400–800/month) running Docker. This is the easiest complete setup:
  ```bash
  cd backend
  cp .env.production.example .env        # edit every value
  docker compose up -d --build
  docker compose exec web python manage.py seed_demo          # optional sample content
  docker compose exec web python manage.py createsuperuser
  ```
  Put HTTPS in front with Nginx + a free Let's Encrypt certificate (`deploy/nginx.conf`, then `sudo certbot --nginx -d api.learnincreation.com`). Point a subdomain such as `api.learnincreation.com` at the server.
- **Without Docker on a VPS:** `deploy/learnincreation.service` (Gunicorn under systemd) together with `deploy/nginx.conf`.
- **Render / Railway / PythonAnywhere:** start command `gunicorn config.wsgi:application`, and set the variables from `.env.production.example`. Use a persistent disk or cloud storage for `MEDIA_ROOT`, otherwise uploaded images vanish on each deploy.

Before launch, in the live `.env`:
- `DJANGO_DEBUG=0` and `APP_ENV=production`.
- A new random `DJANGO_SECRET_KEY` of 50+ characters.
- `ADMIN_URL` changed from `admin/` to something hard to guess.
- `PAYMENTS_MODE=razorpay` (test mode is automatically refused in production) and a real `SMS_BACKEND`.

Then run `python manage.py check --deploy`.

## 4. Connect Razorpay, Google, SMS and email

**Razorpay**
1. Dashboard → Account & Settings → **API Keys**. Put the key ID and secret in `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET`. Use `rzp_test_…` keys first, then switch to live keys after KYC.
2. Dashboard → **Webhooks** → add `https://api.learnincreation.com/api/payments/webhook`, with events `payment.captured`, `order.paid` and `payment.failed`. Put the webhook secret in `RAZORPAY_WEBHOOK_SECRET`. The webhook records payments even if a student closes the app right after paying.
3. Refunds are made in the Razorpay dashboard. Then mark the payment "Refunded" in the admin panel.

**Google sign-in** (Google Cloud Console → APIs & Services → Credentials)
1. Set up the OAuth consent screen.
2. Create an OAuth client of type **Web application**. Its client ID goes in the backend `GOOGLE_CLIENT_IDS` and in the app's `GOOGLE_SERVER_CLIENT_ID`.
3. Create an OAuth client of type **Android** with package `com.learnincreation.app` and the **SHA-1** of each key you sign with:
   - Release key: `keytool -list -v -keystore release.jks -alias learnincreation`
   - Debug key: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`
   - If you publish on Google Play, also add Play's app-signing SHA-1.

**SMS for mobile OTP:** set `SMS_BACKEND` to `msg91`, `fast2sms` or `twilio` and fill in that provider's keys. In India, OTP SMS must use a DLT-registered sender and template; your provider guides you through it. For MSG91, the template must contain the OTP variable.

**Email for password reset:** set `EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend` plus the SMTP host, user and password. For Gmail, use an *app password*; your domain's mailbox also works.

## 5. Security — what is built in

- **SQL injection:** every database query goes through Django's ORM, which always sends values as bound parameters. Search, filter and ID inputs are validated, and the tests feed classic injection strings to the API.
- **Passwords:** hashed with Django's PBKDF2. Rules: minimum length, letters and numbers, and a common-password check.
- **App sessions:** random 256-bit tokens. Only a SHA-256 hash is stored, so a database leak can't be used to sign in. Sign-out deletes the session, and blocking a user ends all their sessions. Tokens live in Android's encrypted Keystore storage.
- **OTP codes:** stored as HMAC hashes. Each code expires after 5 minutes, works once, allows 5 wrong tries, and can't be resent within 60 seconds. There are limits per phone and per IP.
- **Brute force:** rate limits on sign-in, OTP, password reset, Google sign-in, payments, bookings and the admin login.
- **Google sign-in:** the backend checks the token signature against Google's keys, plus the issuer, audience and expiry. Linking Google to an existing account whose email was never verified removes that unproven password, which blocks account pre-hijacking.
- **Payments:** amounts always come from the database, never from the app. A payment counts only after Razorpay's HMAC signature is checked with the server-side secret, or a signed webhook arrives. Fulfilment is idempotent. The Razorpay secret never reaches the app.
- **Bookings:** every booking runs in a transaction that row-locks the batch or the overlapping shifts. Database unique constraints are a second guard, so two students can't get the same seat. Students only ever see their own bookings and orders; the tests cover this.
- **Uploads:** admin images are decoded and re-encoded, which strips EXIF data and hidden payloads, and get random file names. Media is served with `nosniff` and a restrictive content policy.
- **Admin panel:** Django's CSRF protection, a throttled login, an optional secret URL, and HTTPS-only secure cookies in production.
- **Transport and headers:** HSTS and HTTPS redirect in production. Release builds block plain-HTTP traffic. API responses carry no-store, a content policy and anti-framing headers.

What remains your job: keep `.env` and `release.jks` private, serve the site over HTTPS, keep the server updated, back up the database, and use strong admin passwords.

## 6. iOS later

The Dart code is cross-platform. On a Mac with Xcode, run `flutter create --platforms=ios .` inside `app/`. Then, in `ios/Runner/Info.plist`, add your iOS Google client ID and its reversed-client-ID URL scheme (see the `google_sign_in_ios` instructions), and build with `flutter build ipa`. Razorpay needs no extra iOS setup.

## 7. Notes

- Backend logic that doesn't need Django (signatures, Google tokens, seat labels, dates, image cleaning) is unit-tested in `core/tests/test_pure.py`. The full Django suite covers sign-in, catalogue, payments, bookings, security and admin pages. The **Backend tests** GitHub workflow runs it on PostgreSQL, MySQL and SQLite.
- Change the sample prices, fees and library shifts in the admin panel before launch.
- Android build versions (checked with Flutter 3.50): Gradle 9.3.1, Android Gradle Plugin 9.1.1 and Kotlin 2.4, with `android.builtInKotlin=false` and `android.newDsl=false` in `app/android/gradle.properties` (Flutter's setting for apps that still use the Kotlin Gradle plugin). Flutter 3.50 already recommends Gradle 9.5.0, Android Gradle Plugin 9.3.1 and Kotlin 2.4.20; move to those before a newer Flutter makes them required.
