from django.core.management.base import BaseCommand

from studycenter.services import expire_stale_holds


class Command(BaseCommand):
    help = "Releases study-center seats whose payment hold has expired (optional cron job; also happens automatically)."

    def handle(self, *args, **options):
        released = expire_stale_holds()
        self.stdout.write(f"Released {released} expired seat hold(s).")
