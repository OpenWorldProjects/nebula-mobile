#!/usr/bin/env python3
import http.server
import socketserver
import urllib.request
import urllib.parse
import os

PORT = 8085
PROJECT_DIR = os.path.dirname(os.path.abspath(__file__))

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PROJECT_DIR, **kwargs)

    def do_GET(self):
        # Proxy GOG catalog API to bypass browser CORS when previewing on web
        if self.path.startswith('/api/catalog'):
            parsed = urllib.parse.urlparse(self.path)
            query_string = parsed.query
            target_url = f"https://catalog.gog.com/v1/catalog?{query_string}"
            try:
                req = urllib.request.Request(
                    target_url,
                    headers={'User-Agent': 'GOGGalaxyMobile/1.0', 'Accept': 'application/json'}
                )
                with urllib.request.urlopen(req, timeout=15) as response:
                    content = response.read()
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.end_headers()
                    self.wfile.write(content)
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(f'{{"error": "{str(e)}"}}'.encode('utf-8'))
            return

        super().do_GET()

if __name__ == '__main__':
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"GOG Galaxy Mobile Server listening on http://localhost:{PORT}")
        httpd.serve_forever()
