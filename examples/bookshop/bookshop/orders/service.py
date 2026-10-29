from dataclasses import dataclass
from decimal import Decimal

from sqlalchemy.orm import Session

from bookshop import jobs
from bookshop.catalog import repository as catalog
from bookshop.orders.models import Order, OrderItem
from bookshop.payments.stripe_client import charge


class BookNotFound(Exception):
    pass


@dataclass
class RequestedItem:
    book_id: int
    quantity: int


def place_order(
    session: Session,
    customer_email: str,
    items: list[RequestedItem],
    payment_method_id: str,
) -> Order:
    order = Order(customer_email=customer_email, total=Decimal("0"), status="pending")
    for requested in items:
        book = catalog.get_book(session, requested.book_id)
        if book is None:
            raise BookNotFound(requested.book_id)
        catalog.reserve_stock(session, book, requested.quantity)
        order.items.append(
            OrderItem(book_id=book.id, quantity=requested.quantity, unit_price=book.price)
        )
        order.total += book.price * requested.quantity

    order.payment_intent_id = charge(
        amount_cents=int(order.total * 100),
        payment_method_id=payment_method_id,
        description=f"Bookshop order for {customer_email}",
    )
    order.status = "paid"
    session.add(order)
    session.commit()

    jobs.enqueue("order_confirmation", {"order_id": order.id, "email": customer_email})
    return order


def get_order(session: Session, order_id: int) -> Order | None:
    return session.get(Order, order_id)
