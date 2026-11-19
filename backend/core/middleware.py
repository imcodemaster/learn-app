class SecurityHeadersMiddleware:
    """Extra response headers on top of Django's SecurityMiddleware."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        path = request.path
        if path.startswith("/api/"):
            response.setdefault("Cache-Control", "no-store")
            response.setdefault("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
        elif path.startswith("/media/"):
            # Uploaded files are only ever shown as images, never run as pages.
            response.setdefault("Content-Security-Policy", "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'")
            response.setdefault("Content-Disposition", "inline")
        response.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        return response
