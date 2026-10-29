# Bookshop

Online bookstore: browse the catalog, order books, pay by card, get an e-mail confirmation.

## Run locally

```bash
cp .env.example .env   # fill in the API keys
docker compose up --build
docker compose run --rm api python scripts/seed_db.py
```

The API is available at http://localhost:8000 (OpenAPI docs at `/docs`).
