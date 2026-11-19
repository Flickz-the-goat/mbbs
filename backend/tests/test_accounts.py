from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.main import create_app
from app.models import User


@pytest.fixture
def api(tmp_path, monkeypatch):
    uri = f"sqlite:///{tmp_path / 'accounts.db'}"
    monkeypatch.setenv("DATABASE_URL", uri)
    command.upgrade(Config("backend/alembic.ini"), "head")
    engine = create_engine(uri)
    with TestClient(create_app(engine)) as client:
        yield client, engine
    engine.dispose()


def resident(username="lou"):
    return {
        "username": username, "password": "test-passphrase", "name": "Lou",
        "level": 3, "device_id": str(uuid4()),
    }


def test_registration_login_and_logout(api):
    client, engine = api
    body = resident("Lou")
    response = client.post("/api/v1/register", json=body)
    assert response.status_code == 201, response.text
    assert response.json()["user"] == {
        "username": "lou", "name": "Lou", "level": 3, "device_id": body["device_id"],
    }
    with Session(engine) as database:
        stored = database.get(User, "lou")
        assert stored.password_hash != body["password"]
    assert client.post("/api/v1/register", json=body).status_code == 409
    assert client.post("/api/v1/register", json=body | {"username": "another"}).status_code == 409
    assert client.post("/api/v1/login", json=body | {"password": "wrong-pass"}).status_code == 401
    assert client.post("/api/v1/login", json=body | {"device_id": str(uuid4())}).status_code == 409
    login = client.post("/api/v1/login", json=body)
    assert login.status_code == 200
    headers = {"Authorization": f"Bearer {login.json()['token']}"}
    assert client.post("/api/v1/logout", headers=headers).status_code == 204
    assert client.get("/api/v1/contacts", headers=headers).status_code == 401


def test_contact_permissions_and_retries(api):
    client, _ = api
    response = client.post("/api/v1/register", json=resident())
    other = resident("mika")
    other_response = client.post("/api/v1/register", json=other)
    headers = {"Authorization": f"Bearer {response.json()['token']}"}
    other_headers = {"Authorization": f"Bearer {other_response.json()['token']}"}
    assert client.get("/api/v1/contacts").status_code == 401
    assert client.post("/api/v1/contacts", json={"username": "mika"}).status_code == 401
    assert client.post("/api/v1/contacts", headers=headers, json={"username": "lou"}).status_code == 422
    assert client.post("/api/v1/contacts", headers=headers, json={"username": "missing"}).status_code == 404
    for _ in range(2):
        contact = client.post("/api/v1/contacts", headers=headers, json={"username": "MIKA"})
        assert contact.status_code == 200
        assert contact.json() == {"username": "mika", "name": other["name"], "device_id": other["device_id"]}
    assert client.get("/api/v1/contacts", headers=headers).json() == [contact.json()]
    assert client.get("/api/v1/contacts", headers=other_headers).json() == []


def test_invalid_registration_does_not_echo_credentials(api):
    client, _ = api
    response = client.post("/api/v1/register", json=resident() | {"level": 99, "password": "secret"})
    assert response.status_code == 422
    assert "secret" not in response.text
