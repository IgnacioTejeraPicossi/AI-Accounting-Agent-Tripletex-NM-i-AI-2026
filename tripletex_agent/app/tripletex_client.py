"""Simplified Tripletex API client.

Matches the official example pattern exactly:
  requests.get(f"{base_url}/employee", auth=("0", session_token), params=...)

No Session object, no extra headers, just simple requests calls.
"""
import json
import sys

import requests


def log_json(event, **kwargs):
    try:
        msg = json.dumps({"event": event, **kwargs}, default=str, ensure_ascii=False)
        print(msg, file=sys.stdout, flush=True)
    except Exception:
        pass


class TripletexApiError(Exception):
    pass


class TripletexClient:
    def __init__(self, base_url: str, session_token: str):
        self.base_url = base_url.rstrip("/")
        self.token = session_token
        self.auth = ("0", session_token)

    def _url(self, path: str) -> str:
        if not path.startswith("/"):
            path = "/" + path
        return f"{self.base_url}{path}"

    def get(self, path, params=None):
        url = self._url(path)
        resp = requests.get(url, auth=self.auth, params=params, timeout=30)
        log_json("api", method="GET", url=url, status=resp.status_code)
        if resp.status_code >= 400:
            log_json("api_error", method="GET", url=url,
                     status=resp.status_code, body=resp.text[:500])
            raise TripletexApiError(
                f"GET {path} -> {resp.status_code}: {resp.text[:300]}")
        return self._parse(resp)

    def post(self, path, payload=None):
        url = self._url(path)
        resp = requests.post(url, auth=self.auth, json=payload, timeout=30)
        log_json("api", method="POST", url=url, status=resp.status_code)
        if resp.status_code >= 400:
            log_json("api_error", method="POST", url=url,
                     status=resp.status_code, body=resp.text[:500],
                     sent_payload=payload)
            raise TripletexApiError(
                f"POST {path} -> {resp.status_code}: {resp.text[:300]}")
        return self._parse(resp)

    def put(self, path, payload=None):
        url = self._url(path)
        resp = requests.put(url, auth=self.auth, json=payload, timeout=30)
        log_json("api", method="PUT", url=url, status=resp.status_code)
        if resp.status_code >= 400:
            raise TripletexApiError(
                f"PUT {path} -> {resp.status_code}: {resp.text[:300]}")
        return self._parse(resp)

    def delete(self, path):
        url = self._url(path)
        resp = requests.delete(url, auth=self.auth, timeout=30)
        log_json("api", method="DELETE", url=url, status=resp.status_code)
        if resp.status_code >= 400:
            raise TripletexApiError(
                f"DELETE {path} -> {resp.status_code}: {resp.text[:300]}")
        return None

    def _parse(self, resp):
        if not resp.content:
            return None
        try:
            data = resp.json()
        except ValueError:
            return None
        if isinstance(data, dict) and "value" in data:
            return data["value"]
        return data
