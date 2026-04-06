import os
from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail
from twilio.rest import Client

# ── Config ─────────────────────────────────────────────────────────────────────
NOTIFICATION_MODE    = os.getenv("NOTIFICATION_MODE", "log")
SENDGRID_API_KEY     = os.getenv("SENDGRID_API_KEY", "")
TWILIO_ACCOUNT_SID   = os.getenv("TWILIO_ACCOUNT_SID", "")
TWILIO_AUTH_TOKEN    = os.getenv("TWILIO_AUTH_TOKEN", "")
TWILIO_PHONE_NUMBER  = os.getenv("TWILIO_PHONE_NUMBER", "")
FROM_EMAIL           = os.getenv("FROM_EMAIL", "noreply@boxco.com")


# ── Email ──────────────────────────────────────────────────────────────────────

def send_order_confirmation_email(to_email: str, customer_name: str, order_number: str, items: list):
    """
    Sends an order confirmation email via SendGrid.

    In NOTIFICATION_MODE=log (local dev), prints to console instead
    of actually sending — no SendGrid account needed locally.

    In NOTIFICATION_MODE=send (production), sends a real email.
    Requires SENDGRID_API_KEY and FROM_EMAIL to be set.
    """
    items_text = "\n".join(
        f"  - {item.get('productName', item.get('product_name', 'Unknown'))}: "
        f"{item.get('quantity')} unit(s)"
        for item in items
    )

    subject = f"Order Confirmed — {order_number}"
    body    = (
        f"Hi {customer_name},\n\n"
        f"Your order has been successfully placed.\n\n"
        f"Order number: {order_number}\n\n"
        f"Items ordered:\n{items_text}\n\n"
        f"We will notify you once your order has shipped.\n\n"
        f"Thank you for your order!\n"
        f"BoxCo Team"
    )

    if NOTIFICATION_MODE == "log":
        print(f"[Notification — EMAIL LOG]")
        print(f"  To:      {to_email}")
        print(f"  Subject: {subject}")
        print(f"  Body:\n{body}")
        return

    try:
        message = Mail(
            from_email    = FROM_EMAIL,
            to_emails     = to_email,
            subject       = subject,
            plain_text_content = body,
        )
        sg       = SendGridAPIClient(SENDGRID_API_KEY)
        response = sg.send(message)
        print(f"[Notification] Order confirmation email sent to {to_email} "
              f"— status {response.status_code}")
    except Exception as e:
        print(f"[Notification] Failed to send order confirmation email to {to_email}: {e}")


def send_shipment_notification_email(to_email: str, customer_name: str, order_number: str,
                                     carrier: str, tracking_number: str, shipped_at: str):
    """
    Sends a shipment notification email with tracking info via SendGrid.
    """
    subject = f"Your Order Has Shipped — {order_number}"
    body    = (
        f"Hi {customer_name},\n\n"
        f"Great news — your order has shipped!\n\n"
        f"Order number:    {order_number}\n"
        f"Carrier:         {carrier}\n"
        f"Tracking number: {tracking_number}\n"
        f"Shipped at:      {shipped_at}\n\n"
        f"You can track your shipment using the tracking number above "
        f"on the {carrier} website.\n\n"
        f"Thank you for your order!\n"
        f"BoxCo Team"
    )

    if NOTIFICATION_MODE == "log":
        print(f"[Notification — EMAIL LOG]")
        print(f"  To:      {to_email}")
        print(f"  Subject: {subject}")
        print(f"  Body:\n{body}")
        return

    try:
        message = Mail(
            from_email         = FROM_EMAIL,
            to_emails          = to_email,
            subject            = subject,
            plain_text_content = body,
        )
        sg       = SendGridAPIClient(SENDGRID_API_KEY)
        response = sg.send(message)
        print(f"[Notification] Shipment email sent to {to_email} "
              f"— status {response.status_code}")
    except Exception as e:
        print(f"[Notification] Failed to send shipment email to {to_email}: {e}")


# ── SMS ────────────────────────────────────────────────────────────────────────

def send_order_confirmation_sms(to_phone: str, customer_name: str, order_number: str):
    """
    Sends an order confirmation SMS via Twilio.

    SMS messages are kept short — just the essentials.
    Full details go in the email.
    """
    body = (
        f"Hi {customer_name}, your BoxCo order {order_number} "
        f"has been confirmed. You will receive another message when it ships."
    )

    if NOTIFICATION_MODE == "log":
        print(f"[Notification — SMS LOG]")
        print(f"  To:   {to_phone}")
        print(f"  Body: {body}")
        return

    try:
        client  = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        message = client.messages.create(
            body = body,
            from_= TWILIO_PHONE_NUMBER,
            to   = to_phone,
        )
        print(f"[Notification] Order confirmation SMS sent to {to_phone} "
              f"— SID {message.sid}")
    except Exception as e:
        print(f"[Notification] Failed to send order confirmation SMS to {to_phone}: {e}")


def send_shipment_notification_sms(to_phone: str, customer_name: str,
                                   order_number: str, carrier: str, tracking_number: str):
    """
    Sends a shipment notification SMS with tracking info via Twilio.
    """
    body = (
        f"Hi {customer_name}, your BoxCo order {order_number} has shipped! "
        f"Carrier: {carrier}. Tracking: {tracking_number}."
    )

    if NOTIFICATION_MODE == "log":
        print(f"[Notification — SMS LOG]")
        print(f"  To:   {to_phone}")
        print(f"  Body: {body}")
        return

    try:
        client  = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        message = client.messages.create(
            body = body,
            from_= TWILIO_PHONE_NUMBER,
            to   = to_phone,
        )
        print(f"[Notification] Shipment SMS sent to {to_phone} "
              f"— SID {message.sid}")
    except Exception as e:
        print(f"[Notification] Failed to send shipment SMS to {to_phone}: {e}")
