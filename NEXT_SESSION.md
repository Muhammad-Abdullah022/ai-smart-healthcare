# Next Session — start here

1. **You (once):** double-click `E:\FYP SESMTER\app\scripts\flutter_checks.bat`.
   It creates the `android/` folder (first run only), runs `pub get`, `analyze`, `test`
   and writes `scripts\flutter_checks.log`. Wait until the window closes.
2. Say **"Continue the project"**. Claude will:
   * read the tracker + these files,
   * read `scripts/flutter_checks.log`, fix every analyze error / failing test,
   * move Phase B tasks from *Testing* to *Done* only if checks pass.
3. **Next task IDs after that:** C-03 (needs your Atlas URI in `backend/.env`), then C-09 (email), C-12 (file storage), B-21, then Phase D.

Current task: **A-03 / Phase B (Testing)**. Next task: **A-03 verification → C-03**.

## Update 2026-11-01 (afternoon)
Symptom checker built. Next: user runs app + backend and does one symptom check (verifies Gemini/Groq keys).
Then: E-12 SOS, E-16/E-25 mental health screening + crisis support, C-11 roles, C-12 file storage.

## Update 2026-11-01 (evening) - UI phase
Done: gentle redesign, all 50 features have screens saving to MongoDB (/entries), readings chart (41), emergency QR card (44, qr_flutter), profile header, grouped settings, RUN/START_BACKEND.bat + RUN/START_FRONTEND.bat.
Pending tracker updates: ~/t1.json, ~/t2.json (Excel was open - re-apply when closed).
Next UI items: file/photo upload (8, 26, 38), PDF summary (50), local notifications (33), maps (6, 28), voice (13), camera (20, 21), Urdu.
Then: run `flutter analyze` + `flutter test` on the PC and fix findings; logic per feature.

## Decision 2026-11-01: DESIGN FIRST (no logic for now)
User wants to focus only on design and improve it day by day. Logic waits.
Daily design plan (one area per day, user reviews with screenshots):
 Day 1: Home + bottom navigation (spacing, icons, header details)
 Day 2: Symptom checker form + result page
 Day 3: Medicines (Today / Add) + reminders look
 Day 4: Mental health screens (mood, breathing, checks, crisis)
 Day 5: Records tab + feature forms + saved lists
 Day 6: Profile, Edit profile, Settings, Consent
 Day 7: Onboarding, Login, Sign up, Splash + empty/error/loading states
 Then: micro-details (animations on actions, icons, Urdu-ready text sizes), dark mode (optional)
Ask the user for a screenshot of each screen at the start of each day.

## 2026-11-08
- Done: AI Health Assistant chat (language, voice, read aloud, history, report upload, comparison). Committed.
- To check on PC: run START_BACKEND.bat (installs python-multipart), START_FRONTEND.bat (gets new Flutter packages), then `flutter analyze` and `flutter test`.
- Next ideas from user: wait for the user's next list ("baki bad ma bataa hu").
