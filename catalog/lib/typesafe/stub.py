#!/usr/bin/env python3
"""A stand-in for api.typesafe.ai, for the package's offline check.

Serves the two endpoints `openapi.yaml` describes on a port of its own, written to the file
named on the command line once it is bound, and answers as the API's schemas say: every
question gets an answer of its type, a request without state or questions a 422 with the
validation detail, and a request without the bearer token `test` a 401.
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

MODELS = {
    "models": [
        {
            "name": "jev-latest",
            "description": "General-purpose system one model.",
            "release_date": "2026-09-15",
        }
    ]
}


def answer(question):
    kind = question.get("type")
    if kind == "noul":
        return {"type": "noul", "noul": 0.98}
    if kind == "choice":
        names = list(question.get("criteria", {}))
        share = 1 / len(names) if names else 0
        return {
            "type": "choice",
            "choice": names[0] if names else "",
            "confidence": 0.9,
            "probabilities": {name: share for name in names},
        }
    if kind == "score":
        levels = question.get("criteria", [])
        return {
            "type": "score",
            "score": float(len(levels) - 1),
            "confidence": 0.9,
            "legend": {str(i): level for i, level in enumerate(levels)},
            "probabilities": {str(i): (1.0 if i == len(levels) - 1 else 0.0) for i in range(len(levels))},
        }
    if kind == "box":
        return {
            "type": "box",
            "box": {"top": 0.2, "bottom": 0.66, "left": 0.19, "right": 0.68},
            "confidence": None,
        }
    return None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("x-typesafe-request-id", "stub")
        self.end_headers()
        self.wfile.write(data)

    def authorized(self):
        if self.headers.get("Authorization") == "Bearer test":
            return True
        self.send(401, {"error": "Invalid API key."})
        return False

    def do_GET(self):
        if not self.authorized():
            return
        if self.path == "/v1/models":
            self.send(200, MODELS)
        else:
            self.send(404, {"error": "Not found."})

    def do_POST(self):
        if not self.authorized():
            return
        if self.path != "/v1/systemone":
            self.send(404, {"error": "Not found."})
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            request = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            self.send(400, {"error": "The body is not JSON."})
            return
        missing = [name for name in ("state", "questions") if name not in request]
        if missing or not request.get("questions"):
            self.send(
                422,
                {
                    "detail": [
                        {"loc": ["body", name], "msg": "Field required", "type": "missing"}
                        for name in (missing or ["questions"])
                    ]
                },
            )
            return
        answers = {}
        for name, question in request["questions"].items():
            answered = answer(question)
            if answered is None:
                self.send(422, {"detail": [{"loc": ["body", "questions", name, "type"], "msg": "Unknown question type", "type": "literal_error"}]})
                return
            answers[name] = answered
        self.send(
            200,
            {
                "model": request.get("model", "jev-latest"),
                "answers": answers,
                "usage": {"input_tokens": len(json.dumps(request["state"])), "output_tokens": len(answers)},
            },
        )


def main():
    port_file = sys.argv[1]
    server = HTTPServer(("127.0.0.1", 0), Handler)
    with open(port_file, "w") as out:
        out.write(str(server.server_address[1]))
    server.serve_forever()


if __name__ == "__main__":
    main()
