"""Test fixtures: isolated sqlite DB + TestClient + direct session for role setup."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.db.base import Base
from app.db.session import get_db
from app.main import app


@pytest.fixture()
def _engine(tmp_path):
    engine = create_engine(
        f"sqlite:///{tmp_path / 'test.db'}", connect_args={"check_same_thread": False}
    )
    Base.metadata.create_all(bind=engine)
    yield engine
    engine.dispose()


@pytest.fixture()
def session_factory(_engine):
    return sessionmaker(bind=_engine, autoflush=False, autocommit=False)


@pytest.fixture()
def db(session_factory):
    s = session_factory()
    try:
        yield s
    finally:
        s.close()


@pytest.fixture()
def client(session_factory):
    def override_get_db():
        s = session_factory()
        try:
            yield s
        finally:
            s.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
