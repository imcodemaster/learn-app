import logging

import requests
from django.conf import settings

from .sms_providers import SmsError, otp_message, send_fast2sms, send_msg91, send_twilio

logger = logging.getLogger("learnincreation")

__all__ = ["SmsError", "send_otp_sms", "sms_available"]


def sms_available() -> bool:
    """Whether codes can reach phones: production needs a real SMS provider."""
    return not (settings.SMS_BACKEND == "console" and settings.APP_ENV == "production")


def send_otp_sms(phone_e164: str, code: str) -> None:
    backend = settings.SMS_BACKEND
    minutes = max(1, settings.OTP_TTL_SECONDS // 60)
    if backend == "msg91":
        send_msg91(requests, settings.MSG91_AUTH_KEY, settings.MSG91_TEMPLATE_ID, phone_e164, code)
    elif backend == "fast2sms":
        send_fast2sms(requests, settings.FAST2SMS_API_KEY, phone_e164, code)
    elif backend == "twilio":
        send_twilio(requests, settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN, settings.TWILIO_FROM,
                    phone_e164, otp_message(code, minutes))
    elif backend == "console":
        if settings.APP_ENV == "production":
            raise SmsError("SMS_BACKEND=console cannot be used in production. Configure an SMS provider.")
        logger.warning("SMS not sent (console backend). To %s: %s", phone_e164, otp_message(code, minutes))
    else:
        raise SmsError(f"Unknown SMS_BACKEND '{backend}'.")
