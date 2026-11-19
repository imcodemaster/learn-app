import os

from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.core.management.base import BaseCommand, CommandError


class Command(BaseCommand):
    help = (
        "Creates the first admin-panel user from the ADMIN_EMAIL and ADMIN_PASSWORD environment variables "
        "(ADMIN_NAME is optional). Does nothing when they are not set or the user already exists, so it is "
        "safe to run on every start; change the password later in the admin panel."
    )

    def handle(self, *args, **options):
        email = os.environ.get("ADMIN_EMAIL", "").strip().lower()
        password = os.environ.get("ADMIN_PASSWORD", "")
        name = os.environ.get("ADMIN_NAME", "").strip() or "Admin"
        if not email or not password:
            self.stdout.write("ADMIN_EMAIL / ADMIN_PASSWORD not set: no admin user created.")
            return
        User = get_user_model()
        if User.objects.filter(email=email).exists():
            self.stdout.write(f"Admin user {email} already exists.")
            return
        candidate = User(email=email, name=name)
        try:
            validate_password(password, user=candidate)
        except ValidationError as exc:
            raise CommandError("ADMIN_PASSWORD is too weak: " + " ".join(exc.messages)) from exc
        User.objects.create_superuser(email=email, password=password, name=name)
        self.stdout.write(self.style.SUCCESS(f"Created admin user {email}."))
