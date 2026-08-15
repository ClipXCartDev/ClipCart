"""Seed demo data so you can log in and test immediately.

Run from the backend folder:
    .venv\\Scripts\\python scripts\\seed.py       (Windows)
    .venv/bin/python scripts/seed.py             (macOS/Linux)

Creates admin / editor / customer accounts (password: password123), two plans,
one category, and clips (1 approved + 2 pending so Admin has something to review).
"""
import os
import sys
from datetime import datetime, timezone

# make `app` importable when run as `python scripts/seed.py`
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import app.models  # noqa: F401  (register models)
from app.core.security import hash_password
from app.db.base import Base
from app.db.session import SessionLocal, engine
from app.models import Access, Category, Clip, ClipStatus, Plan, Role, User
from app.services.catalog import slugify

Base.metadata.create_all(bind=engine)
db = SessionLocal()

PWD = "password123"


def user(email, name, role):
    u = db.query(User).filter_by(email=email).first()
    if not u:
        u = User(name=name, email=email, role=role, password_hash=hash_password(PWD))
        db.add(u)
    else:
        u.role = role
    db.commit()
    return db.query(User).filter_by(email=email).first()


admin = user("admin@clipcart.app", "Admin", Role.admin)
editor = user("editor@clipcart.app", "Maria K", Role.editor)
customer = user("customer@clipcart.app", "Aditya", Role.customer)

# plans
if not db.query(Plan).filter_by(slug="professional").first():
    db.add(Plan(name="Basic", slug="basic", price_usd=4, export_limit=30, quality="1080p", max_devices=1, features=["Free clips library", "No watermark"]))
    db.add(Plan(name="Professional", slug="professional", price_usd=9, export_limit=None, quality="1080p", max_devices=2, features=["All Pro clips", "Priority new drops", "No watermark"], sort_order=1))
    db.commit()

# category
cat = db.query(Category).filter_by(slug="comedy").first()
if not cat:
    cat = Category(name="Comedy", slug="comedy")
    db.add(cat)
    db.commit()

# clips
seed_clips = [
    ("Monday Mood", "pro", "approved"),
    ("Boss Reaction", "free", "pending"),
    ("Exam Fear", "free", "pending"),
]
for title, access, st in seed_clips:
    if db.query(Clip).filter_by(title=title).first():
        continue
    c = Clip(
        title=title, slug=slugify(title), editor_id=editor.id, category_id=cat.id,
        movie_name="3 Idiots", genre="Comedy", language="English",
        access=Access(access), layers=["subtitle", "logo", "username"], duration_sec=12,
        status=ClipStatus(st),
    )
    if st == "approved":
        c.published_at = datetime.now(timezone.utc)
    db.add(c)
db.commit()

print("\n=== Seed complete — password for all: password123 ===")
print("  ADMIN     admin@clipcart.app")
print("  EDITOR    editor@clipcart.app")
print("  CUSTOMER  customer@clipcart.app")
print("Clips: 1 approved (browse), 2 pending (admin approvals).\n")
