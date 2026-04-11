#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "httpx>=0.28.1",
# ]
# ///

import argparse
import os
import platform
import shutil
import stat
import sys
import tempfile
from pathlib import Path

import httpx


REPO = "existedinnettw/code_work_spawner"
BINARY_NAME = "code_work_spawner"


def github_headers() -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "code_work_spawner-install-script",
    }
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Install code_work_spawner from GitHub Releases."
    )
    parser.add_argument(
        "--version",
        default="latest",
        help="Release tag to install (default: latest).",
    )
    parser.add_argument(
        "--bin-dir",
        default=str(default_bin_dir()),
        help="Directory to install the binary into.",
    )
    parser.add_argument(
        "--repo",
        default=REPO,
        help="GitHub repository in owner/name format.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the selected asset and destination without downloading.",
    )
    return parser.parse_args()


def default_bin_dir() -> Path:
    if os.name == "nt":
        local_app_data = os.environ.get("LOCALAPPDATA")
        if local_app_data:
            return Path(local_app_data) / "Programs" / "code_work_spawner" / "bin"
        return (
            Path.home() / "AppData" / "Local" / "Programs" / "code_work_spawner" / "bin"
        )
    return Path.home() / ".local" / "bin"


def detect_target() -> tuple[str, str, str]:
    system = platform.system().lower()
    machine = platform.machine().lower()

    if system.startswith("linux"):
        target_os = "linux"
        extension = ""
    elif system.startswith("darwin"):
        target_os = "macos"
        extension = ""
    elif system.startswith("windows"):
        target_os = "windows"
        extension = ".exe"
    else:
        raise RuntimeError(f"Unsupported operating system: {platform.system()}")

    if machine in {"x86_64", "amd64"}:
        arch = "x64"
    elif machine in {"aarch64", "arm64"}:
        arch = "arm64"
    else:
        raise RuntimeError(f"Unsupported architecture: {platform.machine()}")

    if target_os == "windows" and arch != "x64":
        raise RuntimeError(
            "No published Windows release asset for this architecture. Expected x64."
        )

    return target_os, arch, extension


def release_api_url(repo: str, version: str) -> str:
    if version == "latest":
        return f"https://api.github.com/repos/{repo}/releases/latest"
    from urllib.parse import quote

    encoded_tag = quote(version, safe="")
    return f"https://api.github.com/repos/{repo}/releases/tags/{encoded_tag}"


def download_release_metadata(repo: str, version: str) -> dict:
    url = release_api_url(repo, version)
    try:
        response = httpx.get(
            url,
            headers=github_headers(),
            timeout=30.0,
            follow_redirects=True,
        )
        response.raise_for_status()
        return response.json()
    except httpx.HTTPStatusError as exc:
        hint = ""
        if exc.response.status_code == 404:
            hint = " If this release exists, set GH_TOKEN (or GITHUB_TOKEN) and retry."
        raise RuntimeError(
            "Failed to fetch release metadata "
            f"({exc.response.status_code}): {exc.response.text}{hint}"
        ) from exc
    except httpx.HTTPError as exc:
        raise RuntimeError(f"Failed to fetch release metadata: {exc}") from exc


def expected_asset_name(tag: str, target_os: str, arch: str, extension: str) -> str:
    return f"{BINARY_NAME}-{tag}-{target_os}-{arch}{extension}"


def select_asset(metadata: dict, asset_name: str) -> dict:
    for asset in metadata.get("assets", []):
        if asset.get("name") == asset_name:
            return asset
    available = ", ".join(
        asset.get("name", "<unknown>") for asset in metadata.get("assets", [])
    )
    raise RuntimeError(
        f"Could not find release asset {asset_name!r}. Available assets: {available}"
    )


def download_asset(asset: dict, destination: Path) -> None:
    download_url = asset.get("browser_download_url")
    if not download_url:
        raise RuntimeError("Release asset is missing browser_download_url.")

    try:
        with httpx.stream(
            "GET",
            download_url,
            headers=github_headers(),
            timeout=60.0,
            follow_redirects=True,
        ) as response:
            response.raise_for_status()
            with destination.open("wb") as output:
                for chunk in response.iter_bytes(chunk_size=1024 * 64):
                    output.write(chunk)
    except httpx.HTTPStatusError as exc:
        raise RuntimeError(
            f"Failed to download asset ({exc.response.status_code}): {exc.response.text}"
        ) from exc
    except httpx.HTTPError as exc:
        raise RuntimeError(f"Failed to download asset: {exc}") from exc


def install_binary(download_path: Path, destination_path: Path) -> None:
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(download_path), str(destination_path))
    if os.name != "nt":
        mode = destination_path.stat().st_mode
        destination_path.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def warn_if_not_on_path(bin_dir: Path) -> None:
    path_env = os.environ.get("PATH", "")
    path_entries = [
        Path(entry).resolve() for entry in path_env.split(os.pathsep) if entry
    ]
    if bin_dir.resolve() not in path_entries:
        print(
            f"Warning: {bin_dir} is not in PATH. Add it to run {BINARY_NAME} directly.",
            file=sys.stderr,
        )


def main() -> int:
    args = parse_args()
    target_os, arch, extension = detect_target()
    metadata = download_release_metadata(args.repo, args.version)
    tag = metadata.get("tag_name")
    if not tag:
        raise RuntimeError("Release metadata is missing tag_name.")

    asset_name = expected_asset_name(tag, target_os, arch, extension)
    asset = select_asset(metadata, asset_name)

    bin_dir = Path(args.bin_dir).expanduser()
    binary_filename = BINARY_NAME + extension
    destination_path = bin_dir / binary_filename

    if args.dry_run:
        print(f"repo: {args.repo}")
        print(f"tag: {tag}")
        print(f"asset: {asset_name}")
        print(f"install_to: {destination_path}")
        return 0

    with tempfile.TemporaryDirectory(prefix="code_work_spawner-install-") as temp_dir:
        temp_path = Path(temp_dir) / binary_filename
        download_asset(asset, temp_path)
        install_binary(temp_path, destination_path)

    print(f"Installed {BINARY_NAME} {tag} to {destination_path}")
    warn_if_not_on_path(bin_dir)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)
