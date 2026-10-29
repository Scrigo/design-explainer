from fastapi import FastAPI

from bookshop.catalog.routes import router as catalog_router
from bookshop.orders.routes import router as orders_router

app = FastAPI(title="Bookshop API")
app.include_router(catalog_router)
app.include_router(orders_router)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}
