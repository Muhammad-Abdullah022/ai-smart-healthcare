"""MongoDB connection and index setup."""
import json
import socket
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from pymongo import ASCENDING, DESCENDING
from pymongo.errors import ConfigurationError

DOH_URL = "https://dns.google/resolve?name={name}&type={type}"
LOG = Path(__file__).resolve().parents[2] / "logs" / "startup.log"


def _log(msg: str) -> None:
    print(f"[mongo] {msg}")
    try:
        LOG.parent.mkdir(exist_ok=True)
        with LOG.open("a", encoding="utf-8") as f:
            f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} {msg}\n")
    except OSError:
        pass


def _doh(name: str, rtype: str) -> list[str]:
    """DNS lookup over HTTPS (Google), for networks whose DNS cannot answer SRV/TXT lookups."""
    with urllib.request.urlopen(DOH_URL.format(name=name, type=rtype), timeout=8) as r:
        data = json.loads(r.read())
    code = {"SRV": 33, "TXT": 16}[rtype]
    return [a["data"].strip('"') for a in data.get("Answer", []) if a.get("type") == code]


def srv_to_standard(uri: str) -> str:
    """mongodb+srv://user:pw@cluster/db?x  ->  mongodb://user:pw@host1:27017,host2:27017/db?x&replicaSet=..&tls=true"""
    parts = urllib.parse.urlsplit(uri)
    userinfo, _, host = parts.netloc.rpartition("@")
    hosts = []
    for rec in _doh(f"_mongodb._tcp.{host}", "SRV"):
        _prio, _weight, port, target = rec.split()
        hosts.append(f"{target.rstrip('.')}:{port}")
    if not hosts:
        raise ConfigurationError(f"Could not find the database servers for {host}")
    opts = dict(urllib.parse.parse_qsl(parts.query))
    for txt in _doh(host, "TXT"):
        for k, v in urllib.parse.parse_qsl(txt):
            opts.setdefault(k, v)
    opts.setdefault("tls", "true")
    return f"mongodb://{userinfo + '@' if userinfo else ''}{','.join(hosts)}{parts.path or '/'}?{urllib.parse.urlencode(opts)}"


def create_client(uri: str) -> AsyncIOMotorClient:
    # tz_aware=True keeps all dates in UTC with timezone info.
    try:
        return AsyncIOMotorClient(uri, tz_aware=True, serverSelectionTimeoutMS=10000)
    except ConfigurationError as exc:
        # Some home/ISP DNS servers cannot answer the special (SRV) lookup that "mongodb+srv://"
        # addresses need ("The DNS query name does not exist"). Look it up over HTTPS instead and
        # connect with the normal address format.
        if not uri.startswith("mongodb+srv://"):
            raise
        _log(f"Local DNS failed for the Atlas address ({exc}); looking it up over HTTPS instead.")
        standard = srv_to_standard(uri)
        first = standard.split("@")[-1].split(",")[0].split(":")[0]
        try:
            socket.getaddrinfo(first, 27017)
            _log(f"Server {first} resolves on this network; connecting.")
        except OSError as e:
            _log(f"Warning: this network also cannot resolve {first}: {e}")
        return AsyncIOMotorClient(standard, tz_aware=True, serverSelectionTimeoutMS=10000)


async def ensure_indexes(db: AsyncIOMotorDatabase) -> None:
    """Create indexes. Safe to run every time the server starts."""
    await db.users.create_index([("email", ASCENDING)], unique=True)
    await db.profiles.create_index([("user_id", ASCENDING)], unique=True)
    await db.refresh_tokens.create_index([("token_hash", ASCENDING)], unique=True)
    await db.refresh_tokens.create_index([("user_id", ASCENDING)])
    # MongoDB deletes expired refresh tokens automatically (TTL index).
    await db.refresh_tokens.create_index([("expires_at", ASCENDING)], expireAfterSeconds=0)
    await db.symptom_assessments.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.consents.create_index([("user_id", ASCENDING), ("category", ASCENDING), ("created_at", DESCENDING)])
    await db.notifications.create_index([("user_id", ASCENDING), ("read", ASCENDING), ("created_at", DESCENDING)])
    await db.mental_assessments.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.mood_entries.create_index([("user_id", ASCENDING), ("day", ASCENDING)], unique=True)
    await db.breathing_sessions.create_index([("user_id", ASCENDING)])
    await db.medicine_records.create_index([("user_id", ASCENDING), ("active", ASCENDING)])
    await db.medication_intake.create_index(
        [("user_id", ASCENDING), ("medicine_id", ASCENDING), ("day", ASCENDING), ("time", ASCENDING)], unique=True)
    await db.sos_events.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.feature_entries.create_index([("user_id", ASCENDING), ("feature", ASCENDING), ("created_at", DESCENDING)])
    await db.medical_reports.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.report_files.create_index([("user_id", ASCENDING)])
    await db.medicine_brands.create_index([("brand_key", ASCENDING)])
    await db.medicine_brands.create_index([("generic_key", ASCENDING)])
    await db.vitals.create_index([("user_id", ASCENDING), ("kind", ASCENDING), ("at", DESCENDING)])
    await db.record_shares.create_index([("token_hash", ASCENDING)])
    await db.record_shares.create_index("expires_at", expireAfterSeconds=0)
    await db.pharmacies.create_index([("city_key", ASCENDING)])
    await db.prescriptions.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.prescription_files.create_index([("user_id", ASCENDING)])
    await db.assistant_chats.create_index([("user_id", ASCENDING), ("updated_at", DESCENDING)])
    await db.labs.create_index([("city_key", ASCENDING)])
    await db.lab_prices.create_index([("city_key", ASCENDING), ("family", ASCENDING)])
    await db.lab_locations.create_index([("city_key", ASCENDING)])
    await db.lab_demo_prices.create_index([("city_key", ASCENDING), ("family", ASCENDING)])
    await db.companion_chats.create_index([("user_id", ASCENDING), ("updated_at", DESCENDING)])
    await db.companion_turns.create_index([("user_id", ASCENDING), ("at", DESCENDING)])
    await db.companion_turns.create_index([("chat_id", ASCENDING), ("at", ASCENDING)])
    await db.companion_memory.create_index([("user_id", ASCENDING)], unique=True)
    await db.doctors.create_index([("city_key", ASCENDING), ("specialty", ASCENDING)])
    await db.appointments.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
    await db.doctors.create_index("user_id", sparse=True)
    await db.issues.create_index([("user_id", ASCENDING), ("updated_at", DESCENDING)])
    await db.consultations.create_index([("user_id", ASCENDING), ("updated_at", DESCENDING)])
    await db.consultations.create_index([("doctor_id", ASCENDING), ("updated_at", DESCENDING)])
    await db.consult_messages.create_index([("consultation_id", ASCENDING), ("created_at", ASCENDING)])
    await db.audit_events.create_index([("user_id", ASCENDING), ("created_at", DESCENDING)])
