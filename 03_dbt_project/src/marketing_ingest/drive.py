"""Google Drive access.

The folders are shared "Anyone with the link", so an API key (restricted to the Drive API) is
enough and is what `auth_mode: api_key` uses. `auth_mode: service_account` is supported for private
folders. Either way the Drive API gives each file's server-side MD5 (`md5Checksum`) *without*
downloading it, which is what lets the loader skip unchanged files.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload

_SCOPE = "https://www.googleapis.com/auth/drive.readonly"
_FOLDER_MIME = "application/vnd.google-apps.folder"


@dataclass(frozen=True)
class DriveFile:
    id: str
    name: str
    md5: str | None
    size: int | None
    mime: str


class DriveClient:
    def __init__(self, service):
        self._svc = service

    @classmethod
    def from_config(cls, auth_mode: str, secret_scope: str, secret_getter: Callable[[str, str], str]) -> "DriveClient":
        """Build a read-only Drive client. `secret_getter(scope, key)` reads a Databricks secret."""
        if auth_mode == "service_account":
            import json

            from google.oauth2 import service_account

            info = json.loads(secret_getter(secret_scope, "service_account_json"))
            creds = service_account.Credentials.from_service_account_info(info, scopes=[_SCOPE])
            svc = build("drive", "v3", credentials=creds, cache_discovery=False)
        elif auth_mode == "api_key":
            svc = build("drive", "v3", developerKey=secret_getter(secret_scope, "api_key"), cache_discovery=False)
        else:
            raise ValueError(f"unknown auth_mode {auth_mode!r} (expected api_key or service_account)")
        return cls(svc)

    def list_folder(self, folder_id: str) -> list[DriveFile]:
        """Every non-trashed file directly in a folder, with its server-side MD5 (paginated)."""
        out, token = [], None
        while True:
            resp = self._svc.files().list(
                q=f"'{folder_id}' in parents and trashed = false",
                fields="nextPageToken, files(id, name, mimeType, size, md5Checksum)",
                pageSize=1000,
                pageToken=token,
                supportsAllDrives=True,
                includeItemsFromAllDrives=True,
            ).execute()
            for f in resp.get("files", []):
                if f["mimeType"] == _FOLDER_MIME:
                    continue
                out.append(DriveFile(
                    id=f["id"], name=f["name"], md5=f.get("md5Checksum"),
                    size=int(f["size"]) if f.get("size") else None, mime=f["mimeType"],
                ))
            token = resp.get("nextPageToken")
            if not token:
                return out

    def download(self, file: DriveFile, dest_path: str) -> None:
        request = self._svc.files().get_media(fileId=file.id, supportsAllDrives=True)
        with open(dest_path, "wb") as fh:
            downloader = MediaIoBaseDownload(fh, request, chunksize=16 * 1024 * 1024)
            done = False
            while not done:
                _, done = downloader.next_chunk()
