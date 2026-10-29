from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail

from bookshop.config import EMAIL_FROM, SENDGRID_API_KEY

_client = SendGridAPIClient(SENDGRID_API_KEY)


def send_order_confirmation(email: str, order_id: int) -> None:
    message = Mail(
        from_email=EMAIL_FROM,
        to_emails=email,
        subject=f"Your Bookshop order #{order_id}",
        plain_text_content=f"Thank you! Your order #{order_id} has been paid.",
    )
    _client.send(message)
