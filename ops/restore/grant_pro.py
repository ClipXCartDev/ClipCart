"""Give an account a Professional subscription - for QA logins after a restore.

Any currently active subscription is expired first, so the account ends up with
exactly one active row rather than two that disagree.

  python grant_pro.py tester@clipcart.app          # 30 days
  python grant_pro.py tester@clipcart.app 365
"""
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, "/app")
import app.models  # noqa: F401  (register mappers)
from app.db.session import SessionLocal
from app.models import User
from app.models.billing import Plan, SubStatus, Subscription

email = sys.argv[1] if len(sys.argv) > 1 else sys.exit("usage: grant_pro.py <email> [days]")
days = int(sys.argv[2]) if len(sys.argv) > 2 else 30

db = SessionLocal()
user = db.query(User).filter_by(email=email).first()
if not user:
    sys.exit(f"no such user: {email}")

plan = (db.query(Plan).filter(Plan.slug == "professional").first()
        or db.query(Plan).filter(Plan.name.ilike("%professional%")).first())
if not plan:
    sys.exit("no Professional plan - run the seed first")

live = db.query(Subscription).filter_by(user_id=user.id, status=SubStatus.active).all()
for s in live:
    s.status = SubStatus.expired
    s.expires_at = datetime.now(timezone.utc)
print(f"expired {len(live)} existing active subscription(s)")

now = datetime.now(timezone.utc)
db.add(Subscription(user_id=user.id, plan_id=plan.id, status=SubStatus.active,
                    started_at=now, expires_at=now + timedelta(days=days)))
db.commit()
print(f"{email} -> {plan.name}, active until {(now + timedelta(days=days)).date()}")
