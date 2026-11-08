"""Request and response shapes for users, auth and profiles."""
import re
from datetime import date
from typing import Literal

from pydantic import BaseModel, EmailStr, Field, field_validator

BloodGroup = Literal["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-", "Unknown"]


class RegisterRequest(BaseModel):
    full_name: str = Field(min_length=2, max_length=80)
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    accepted_terms: bool

    @field_validator("password")
    @classmethod
    def strong_password(cls, value: str) -> str:
        if not re.search(r"[A-Za-z]", value) or not re.search(r"\d", value):
            raise ValueError("Password must contain at least one letter and one number")
        return value

    @field_validator("accepted_terms")
    @classmethod
    def must_accept(cls, value: bool) -> bool:
        if not value:
            raise ValueError("You must accept the terms and privacy policy")
        return value

    @field_validator("full_name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        return value.strip()


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: str
    email: EmailStr
    full_name: str
    roles: list[str]
    email_verified: bool


class EmergencyContact(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    phone: str = Field(min_length=5, max_length=20)
    relation: str = Field(default="", max_length=40)


class NotificationPrefs(BaseModel):
    medicine_reminders: bool = True
    appointments: bool = True
    health_tips: bool = False


class ProfileUpdate(BaseModel):
    """All fields are optional so the app can update one field at a time."""
    full_name: str | None = Field(default=None, min_length=2, max_length=80)
    date_of_birth: date | None = None
    gender: Literal["male", "female", "other", "prefer_not_to_say"] | None = None
    phone: str | None = Field(default=None, max_length=20)
    blood_group: BloodGroup | None = None
    allergies: list[str] | None = Field(default=None, max_length=50)
    conditions: list[str] | None = Field(default=None, max_length=50)
    emergency_contacts: list[EmergencyContact] | None = Field(default=None, max_length=5)
    language: Literal["en", "ur", "roman_ur"] | None = None
    city: str | None = Field(default=None, max_length=60)
    notification_prefs: NotificationPrefs | None = None


class ProfileOut(BaseModel):
    user_id: str
    full_name: str
    email: EmailStr
    date_of_birth: date | None = None
    gender: str | None = None
    phone: str | None = None
    blood_group: str = "Unknown"
    allergies: list[str] = []
    conditions: list[str] = []
    emergency_contacts: list[EmergencyContact] = []
    language: str = "en"
    city: str | None = None
    notification_prefs: NotificationPrefs = NotificationPrefs()
