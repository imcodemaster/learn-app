"""
SMS gateways for OTP codes. Pure functions (no Django) so they can be tested
with a fake HTTP session. `session` is the `requests` module or a Session.
"""

from __future__ import annotations


class SmsError(Exception):
    pass


def otp_message(code: str, minutes: int) -> str:
    return (
        f"{code} is your LearnInCreation verification code. "
        f"It expires in {minutes} minutes. Do not share it with anyone."
    )


def _json(response) -> dict:
    try:
        data = response.json()
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}


def send_msg91(session, auth_key: str, template_id: str, phone_e164: str, code: str, timeout: int = 10) -> None:
    """MSG91 OTP API. The DLT-approved template must contain the ##OTP## variable."""
    if not auth_key or not template_id:
        raise SmsError("MSG91 is not configured (MSG91_AUTH_KEY / MSG91_TEMPLATE_ID).")
    response = session.post(
        "https://control.msg91.com/api/v5/otp",
        params={"template_id": template_id, "mobile": phone_e164.lstrip("+"), "otp": code},
        headers={"authkey": auth_key, "accept": "application/json", "content-type": "application/json"},
        json={},
        timeout=timeout,
    )
    data = _json(response)
    if response.status_code >= 300 or data.get("type") == "error":
        raise SmsError(f"MSG91 error {response.status_code}: {data.get('message', '')}")


def send_fast2sms(session, api_key: str, phone_e164: str, code: str, timeout: int = 10) -> None:
    """Fast2SMS OTP route (Indian numbers, 10 digits without +91)."""
    if not api_key:
        raise SmsError("Fast2SMS is not configured (FAST2SMS_API_KEY).")
    response = session.post(
        "https://www.fast2sms.com/dev/bulkV2",
        headers={"authorization": api_key, "accept": "application/json"},
        json={"route": "otp", "variables_values": code, "numbers": phone_e164[-10:]},
        timeout=timeout,
    )
    data = _json(response)
    if response.status_code >= 300 or data.get("return") is not True:
        raise SmsError(f"Fast2SMS error {response.status_code}: {data.get('message', '')}")


def send_twilio(session, account_sid: str, auth_token: str, sender: str, phone_e164: str,
                message: str, timeout: int = 10) -> None:
    """Twilio Programmable SMS. `sender` is a phone number or a Messaging Service SID (MG...)."""
    if not (account_sid and auth_token and sender):
        raise SmsError("Twilio is not configured (TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_FROM).")
    payload = {"To": phone_e164, "Body": message}
    if sender.startswith("MG"):
        payload["MessagingServiceSid"] = sender
    else:
        payload["From"] = sender
    response = session.post(
        f"https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Messages.json",
        auth=(account_sid, auth_token),
        data=payload,
        timeout=timeout,
    )
    if response.status_code not in (200, 201):
        raise SmsError(f"Twilio error {response.status_code}: {_json(response).get('message', '')}")
