"""Sends emails through the SMTP account in backend/.env (e.g. a Gmail address with an App Password)."""
import asyncio
import smtplib
import ssl
from email.message import EmailMessage

from app.core.config import Settings


class MailNotConfigured(Exception):
    pass


def _send(settings: Settings, to: str, subject: str, body: str, reply_to: str | None) -> None:
    msg = EmailMessage()
    msg["From"] = settings.smtp_from or settings.smtp_user
    msg["To"] = to
    msg["Subject"] = subject
    if reply_to:
        msg["Reply-To"] = reply_to
    msg.set_content(body)
    context = ssl.create_default_context()
    if settings.smtp_port == 465:
        with smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, context=context, timeout=20) as s:
            s.login(settings.smtp_user, settings.smtp_password)
            s.send_message(msg)
    else:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=20) as s:
            s.starttls(context=context)
            s.login(settings.smtp_user, settings.smtp_password)
            s.send_message(msg)


async def send_mail(settings: Settings, to: str, subject: str, body: str, reply_to: str | None = None) -> None:
    if not (settings.smtp_host and settings.smtp_user and settings.smtp_password):
        raise MailNotConfigured()
    await asyncio.to_thread(_send, settings, to, subject, body, reply_to)
