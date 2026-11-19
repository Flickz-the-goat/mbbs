from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .accounts import DUMMY_HASH, issue_session, password_hash, token_hash, verify_password
from .db import make_engine
from .models import Contact, LoginSession, User
from .schemas import ContactProfile, ContactRequest, LoginRequest, Profile, Registration, SignedIn


def create_app(engine=None):
    @asynccontextmanager
    async def lifespan(app):
        app.state.engine = engine if engine is not None else make_engine()
        try:
            yield
        finally:
            if engine is None:
                app.state.engine.dispose()

    app = FastAPI(lifespan=lifespan)
    bearer = HTTPBearer(auto_error=False)

    def database(request: Request):
        with Session(request.app.state.engine) as db:
            yield db

    DB = Annotated[Session, Depends(database)]

    @app.exception_handler(RequestValidationError)
    async def validation_error(_request: Request, _error: RequestValidationError):
        return JSONResponse(status_code=422, content={"detail": "Check username, name, password, level and device ID."})

    def authenticate(db: DB, credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]):
        if credentials:
            login = db.scalar(select(LoginSession).where(
                LoginSession.token_hash == token_hash(credentials.credentials),
                LoginSession.expires_at > datetime.now(timezone.utc),
            ))
            if login:
                return login
        raise HTTPException(401, "Sign in to continue.", headers={"WWW-Authenticate": "Bearer"})

    Auth = Annotated[LoginSession, Depends(authenticate)]

    @app.post("/api/v1/register", status_code=201)
    def register(body: Registration, db: DB) -> SignedIn:
        values = body.model_dump(exclude={"password"})
        user = User(**values, password_hash=password_hash(body.password))
        db.add(user)
        try:
            db.flush()
            token = issue_session(db, user.username)
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, "Username or device ID is already registered.")
        return SignedIn(user=Profile.model_validate(user), token=token)

    @app.post("/api/v1/login")
    def login(body: LoginRequest, db: DB) -> SignedIn:
        user = db.get(User, body.username)
        if not verify_password(body.password, user.password_hash if user else DUMMY_HASH) or user is None:
            raise HTTPException(401, "Username or password is incorrect.")
        if user.device_id != body.device_id:
            raise HTTPException(409, "This account is linked to a different Hollow device ID.")
        token = issue_session(db, user.username)
        db.commit()
        return SignedIn(user=Profile.model_validate(user), token=token)

    @app.post("/api/v1/logout", status_code=204)
    def logout(db: DB, login: Auth) -> Response:
        db.delete(login)
        db.commit()
        return Response(status_code=204)

    @app.get("/api/v1/contacts")
    def contacts(db: DB, login: Auth) -> list[ContactProfile]:
        return db.scalars(select(User).join(Contact, Contact.contact == User.username)
                          .where(Contact.owner == login.username).order_by(User.username)).all()

    @app.post("/api/v1/contacts")
    def add_contact(body: ContactRequest, db: DB, login: Auth) -> ContactProfile:
        owner = login.username
        if body.username == owner:
            raise HTTPException(422, "Enter another user's username.")
        user = db.get(User, body.username)
        if user is None:
            raise HTTPException(404, "No user has that username.")
        if db.get(Contact, (owner, user.username)) is None:
            db.add(Contact(owner=owner, contact=user.username))
            try:
                db.commit()
            except IntegrityError:
                db.rollback()
                if db.get(Contact, (owner, user.username)) is None:
                    raise
        return ContactProfile.model_validate(user)

    return app


app = create_app()
