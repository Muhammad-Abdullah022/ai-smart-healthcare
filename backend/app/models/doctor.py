"""Doctor profile fields (used by doctor sign-up, the doctor panel and the admin panel)."""
from typing import Literal

from pydantic import BaseModel, Field


class DoctorJoin(BaseModel):
    name: str = Field(min_length=3, max_length=80)
    pmdc_number: str = Field(min_length=3, max_length=20)
    specialty: str = Field(min_length=3, max_length=60)
    qualification: str = Field(default="MBBS", max_length=120)
    city: str = Field(min_length=2, max_length=40)
    clinic: str = Field(default="", max_length=120)
    address: str = Field(default="", max_length=200)
    phone: str = Field(default="", max_length=20)
    timings: str = Field(default="", max_length=80)
    fee_pkr: int = Field(ge=0, le=50000)
    payment_method: Literal["JazzCash", "Easypaisa", "Bank transfer"] = "JazzCash"
    payment_title: str = Field(min_length=2, max_length=80, description="Account holder name")
    payment_account: str = Field(min_length=5, max_length=34, description="Mobile wallet number or IBAN")
    experience_years: int | None = Field(default=None, ge=0, le=60)
    gender: Literal["male", "female", ""] = ""
    about: str = Field(default="", max_length=400)
    available: bool = True
