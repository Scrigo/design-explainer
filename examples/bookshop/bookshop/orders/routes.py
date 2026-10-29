from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session

from bookshop.catalog.repository import OutOfStock
from bookshop.db import get_session
from bookshop.orders import service

router = APIRouter(prefix="/orders", tags=["orders"])


class OrderItemIn(BaseModel):
    book_id: int
    quantity: int


class OrderIn(BaseModel):
    customer_email: EmailStr
    items: list[OrderItemIn]
    payment_method_id: str


class OrderOut(BaseModel):
    id: int
    status: str
    total: Decimal

    model_config = {"from_attributes": True}


@router.post("", response_model=OrderOut, status_code=201)
def place_order(body: OrderIn, session: Session = Depends(get_session)):
    try:
        return service.place_order(
            session,
            body.customer_email,
            [service.RequestedItem(i.book_id, i.quantity) for i in body.items],
            body.payment_method_id,
        )
    except service.BookNotFound:
        raise HTTPException(status_code=404, detail="Book not found")
    except OutOfStock as exc:
        raise HTTPException(status_code=409, detail=str(exc))


@router.get("/{order_id}", response_model=OrderOut)
def get_order(order_id: int, session: Session = Depends(get_session)):
    order = service.get_order(session, order_id)
    if order is None:
        raise HTTPException(status_code=404, detail="Order not found")
    return order
