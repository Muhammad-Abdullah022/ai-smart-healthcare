"""The logged-in user's own profile. A user can only ever read or edit their own."""
from fastapi import APIRouter, Depends

from app.deps import get_current_user, get_repo
from app.models.user import ProfileOut, ProfileUpdate
from app.repositories.user_repository import UserRepository

router = APIRouter(prefix="/profile", tags=["profile"])


def _profile_out(user: dict, profile: dict | None) -> ProfileOut:
    profile = profile or {}
    return ProfileOut(
        user_id=str(user["_id"]),
        full_name=user["full_name"],
        email=user["email"],
        date_of_birth=profile.get("date_of_birth"),
        gender=profile.get("gender"),
        phone=profile.get("phone"),
        blood_group=profile.get("blood_group", "Unknown"),
        allergies=profile.get("allergies", []),
        conditions=profile.get("conditions", []),
        emergency_contacts=profile.get("emergency_contacts", []),
        language=profile.get("language", "en"),
        notification_prefs=profile.get("notification_prefs") or {},
    )


@router.get("", response_model=ProfileOut)
async def get_profile(user: dict = Depends(get_current_user), repo: UserRepository = Depends(get_repo)):
    return _profile_out(user, await repo.get_profile(user["_id"]))


@router.patch("", response_model=ProfileOut)
async def update_profile(
    body: ProfileUpdate,
    user: dict = Depends(get_current_user),
    repo: UserRepository = Depends(get_repo),
):
    changes = body.model_dump(exclude_unset=True, mode="json")  # dates become "YYYY-MM-DD"
    full_name = changes.pop("full_name", None)
    if full_name:
        await repo.update_name(user["_id"], full_name.strip())
        user["full_name"] = full_name.strip()
    if changes:
        await repo.update_profile(user["_id"], changes)
    await repo.audit(user["_id"], "profile.update", {"fields": sorted(body.model_fields_set)})
    return _profile_out(user, await repo.get_profile(user["_id"]))


@router.get("/activity")
async def my_activity(user: dict = Depends(get_current_user), repo: UserRepository = Depends(get_repo)):
    """Feature 49: the user's own audit trail (what happened in their account, and when)."""
    cursor = repo.db.audit_events.find({"user_id": user["_id"]}).sort("created_at", -1).limit(100)
    return [{"action": d["action"], "details": d.get("details", {}), "created_at": d["created_at"]}
            async for d in cursor]
