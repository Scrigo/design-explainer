import stripe

from bookshop.config import STRIPE_API_KEY

stripe.api_key = STRIPE_API_KEY


def charge(amount_cents: int, payment_method_id: str, description: str) -> str:
    intent = stripe.PaymentIntent.create(
        amount=amount_cents,
        currency="eur",
        payment_method=payment_method_id,
        confirm=True,
        automatic_payment_methods={"enabled": True, "allow_redirects": "never"},
        description=description,
    )
    return intent.id
