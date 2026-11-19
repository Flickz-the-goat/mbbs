from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, StringConstraints

Username = Annotated[str, StringConstraints(strip_whitespace=True, to_lower=True, pattern=r"^[a-zA-Z0-9_]{3,32}$")]
Password = Annotated[str, StringConstraints(min_length=8, max_length=128)]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=80)]


class ContactRequest(BaseModel):
    username: Username


class LoginRequest(ContactRequest):
    password: Password
    device_id: UUID


class Registration(LoginRequest):
    name: Name
    level: Literal[2, 3, 4]


class ContactProfile(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    username: str
    name: str
    device_id: UUID


class Profile(ContactProfile):
    level: int


class SignedIn(BaseModel):
    user: Profile
    token: str
