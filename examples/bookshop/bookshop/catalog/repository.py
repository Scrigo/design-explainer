from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from bookshop.catalog.models import Book


class OutOfStock(Exception):
    pass


def list_books(session: Session, query: str | None = None) -> list[Book]:
    stmt = select(Book).order_by(Book.title)
    if query:
        pattern = f"%{query}%"
        stmt = stmt.where(or_(Book.title.ilike(pattern), Book.author.ilike(pattern)))
    return list(session.scalars(stmt))


def get_book(session: Session, book_id: int) -> Book | None:
    return session.get(Book, book_id)


def reserve_stock(session: Session, book: Book, quantity: int) -> None:
    if book.stock < quantity:
        raise OutOfStock(f"Not enough copies of '{book.title}'")
    book.stock -= quantity
