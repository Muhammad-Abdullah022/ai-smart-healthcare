"""Admin-only endpoints (task C-11). Admins see counts, never other users' health data."""
from fastapi import APIRouter, Depends

from app.deps import get_db, require_roles

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/stats")
async def stats(_: dict = Depends(require_roles("admin")), db=Depends(get_db)):
    return {
        "users": await db.users.count_documents({}),
        "symptom_assessments": await db.symptom_assessments.count_documents({}),
        "emergency_assessments": await db.symptom_assessments.count_documents({"emergency": True}),
    }
