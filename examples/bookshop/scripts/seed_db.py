"""Creates the tables and inserts a few sample books."""
from decimal import Decimal

from bookshop.catalog.models import Book
from bookshop.db import Base, SessionLocal, engine
from bookshop.orders import models as _order_models  # noqa: F401  (register tables)

BOOKS = [
    ("Domain-Driven Design", "Eric Evans", Decimal("54.90"), 10),
    ("Designing Data-Intensive Applications", "Martin Kleppmann", Decimal("49.90"), 7),
    ("The Pragmatic Programmer", "David Thomas, Andrew Hunt", Decimal("39.90"), 12),
]


def main() -> None:
    Base.metadata.create_all(engine)
    with SessionLocal() as session:
        for title, author, price, stock in BOOKS:
            session.add(Book(title=title, author=author, price=price, stock=stock))
        session.commit()


if __name__ == "__main__":
    main()
