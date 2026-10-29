from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from bookshop.catalog import repository
from bookshop.db import get_session

router = APIRouter(prefix="/books", tags=["catalog"])


class BookOut(BaseModel):
    id: int
    title: str
    author: str
    price: Decimal
    stock: int

    model_config = {"from_attributes": True}


@router.get("", response_model=list[BookOut])
def list_books(q: str | None = None, session: Session = Depends(get_session)):
    return repository.list_books(session, q)


@router.get("/{book_id}", response_model=BookOut)
def get_book(book_id: int, session: Session = Depends(get_session)):
    book = repository.get_book(session, book_id)
    if book is None:
        raise HTTPException(status_code=404, detail="Book not found")
    return book
