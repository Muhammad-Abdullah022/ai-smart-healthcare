# Backend (FastAPI)

## Endpoints so far
| Method | Path | What it does |
|---|---|---|
| GET | `/health` | Server is running |
| POST | `/auth/register` | Create account → returns tokens |
| POST | `/auth/login` | Log in → returns tokens |
| POST | `/auth/refresh` | Swap a refresh token for new tokens (old one stops working) |
| POST | `/auth/logout` | Revoke the refresh token |
| GET | `/auth/me` | Current user |
| GET / PATCH | `/profile` | Read / update **your own** profile |

## How login security works (simple version)
* Passwords are hashed with **bcrypt**; the real password is never stored.
* After login the app gets two tokens:
  * **access token** – short-lived (15 min), sent with every request.
  * **refresh token** – longer (7 days), used once to get new tokens. Stored hashed in MongoDB so it can be revoked on logout.
* Wrong email and wrong password give the **same** error, so nobody can test which emails have accounts.
* Sensitive actions (register, login, failed login, profile update) are written to `audit_events`.

## MongoDB Atlas setup (beginner steps)
1. Go to https://www.mongodb.com/cloud/atlas and create a free account.
2. Create a **free (M0) cluster**. Pick a region close to Pakistan (e.g. Mumbai or Bahrain if offered).
3. **Database Access** → *Add New Database User* → username + strong password → role **Read and write to any database** (later you can restrict it to just `ai_smart_healthcare`).
4. **Network Access** → *Add IP Address* → *Add current IP address*. (Avoid `0.0.0.0/0` except for short testing.)
5. **Database** → *Connect* → *Drivers* → copy the `mongodb+srv://...` string.
6. Put it in `backend/.env` as `MONGODB_URI`, replacing `<db_password>` with your real password.
7. Generate a JWT secret:
   `python -c "import secrets; print(secrets.token_urlsafe(48))"` → paste into `JWT_SECRET`.
8. Start the server. Indexes are created automatically on start-up.

## Tests
`python -m pytest` — runs against an in-memory fake MongoDB, so it never touches your Atlas data.
