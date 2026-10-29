import os

DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql+psycopg://bookshop:bookshop@localhost:5432/bookshop"
)
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
STRIPE_API_KEY = os.environ.get("STRIPE_API_KEY", "")
SENDGRID_API_KEY = os.environ.get("SENDGRID_API_KEY", "")
EMAIL_FROM = os.environ.get("EMAIL_FROM", "orders@bookshop.example")
