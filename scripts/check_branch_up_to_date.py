#!/usr/bin/env python3

import argparse
import asyncio
import select
import sys


async def run_git(
    args: list[str],
    check: bool = True,
    timeout: int | None = None,
) -> tuple[int, str, str]:
    process = await asyncio.create_subprocess_exec(
        "git",
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(
            process.communicate(),
            timeout=timeout,
        )
    except asyncio.CancelledError:
        process.kill()
        await process.wait()
        raise
    except asyncio.TimeoutError:
        process.kill()
        await process.wait()
        raise

    result = (
        process.returncode or 0,
        stdout.decode(),
        stderr.decode(),
    )
    if check and result[0] != 0:
        raise RuntimeError(result[2].strip() or f"git {' '.join(args)} failed")
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Verify current branch includes the latest main branch commit before push."
        )
    )
    parser.add_argument(
        "--remote",
        default="auto",
        help="Remote to compare against (default: auto -> upstream, else origin).",
    )
    parser.add_argument(
        "--base-branch",
        default="main",
        help="Base branch to validate against (default: main).",
    )
    parser.add_argument(
        "--fetch-timeout-seconds",
        type=int,
        default=60,
        help="Timeout for git fetch in seconds (default: 60).",
    )
    return parser.parse_args()


def pushed_local_refs_from_stdin() -> list[str]:
    if sys.stdin is None or sys.stdin.closed or sys.stdin.isatty():
        return []

    try:
        ready, _, _ = select.select([sys.stdin], [], [], 0.05)
    except (OSError, ValueError):
        return []

    if not ready:
        return []

    payload = sys.stdin.read()
    refs: list[str] = []
    for raw_line in payload.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split(maxsplit=3)
        if len(parts) < 4:
            continue
        refs.append(parts[0])
    return refs


def is_tag_only_push(local_refs: list[str]) -> bool:
    if not local_refs:
        return False
    return all(ref.startswith("refs/tags/") for ref in local_refs)


async def get_current_branch() -> str | None:
    returncode, stdout, _ = await run_git(
        ["symbolic-ref", "--quiet", "--short", "HEAD"],
        check=False,
    )
    if returncode != 0:
        return None
    return stdout.strip()


async def choose_remote(remote_arg: str) -> str:
    if remote_arg != "auto":
        return remote_arg

    _, stdout, _ = await run_git(["remote"])
    remotes = stdout.splitlines()
    if "upstream" in remotes:
        return "upstream"
    return "origin"


async def fetch_base(remote: str, base_branch: str, timeout_seconds: int) -> None:
    try:
        returncode, _, stderr = await run_git(
            [
                "fetch",
                "--quiet",
                "--no-tags",
                "--recurse-submodules=no",
                remote,
                f"+refs/heads/{base_branch}:refs/remotes/{remote}/{base_branch}",
            ],
            check=False,
            timeout=timeout_seconds,
        )
    except asyncio.TimeoutError as exc:
        raise RuntimeError(f"git fetch timed out after {timeout_seconds}s") from exc
    if returncode != 0:
        message = stderr.strip() or f"git fetch {remote} {base_branch} failed"
        raise RuntimeError(message)


async def remote_ref_exists(remote: str, base_branch: str) -> bool:
    remote_ref = f"refs/remotes/{remote}/{base_branch}"
    returncode, _, _ = await run_git(
        ["show-ref", "--verify", "--quiet", remote_ref],
        check=False,
    )
    return returncode == 0


async def is_base_ancestor_of_head(base_ref: str) -> bool:
    returncode, _, _ = await run_git(
        ["merge-base", "--is-ancestor", base_ref, "HEAD"],
        check=False,
    )
    return returncode == 0


async def ahead_behind(base_ref: str) -> tuple[int, int]:
    _, stdout, _ = await run_git(
        ["rev-list", "--left-right", "--count", f"HEAD...{base_ref}"]
    )
    parts = stdout.strip().split()
    if len(parts) != 2:
        return 0, 0
    ahead = int(parts[0])
    behind = int(parts[1])
    return ahead, behind


async def cancel_task(task: asyncio.Task[object]) -> None:
    task.cancel()
    await asyncio.gather(task, return_exceptions=True)


async def main() -> int:
    args = parse_args()
    local_refs = pushed_local_refs_from_stdin()
    if is_tag_only_push(local_refs):
        return 0

    branch_task = asyncio.create_task(get_current_branch())
    remote_task = asyncio.create_task(choose_remote(args.remote))

    branch = await branch_task
    if branch is None:
        await cancel_task(remote_task)
        print(
            "[pre-push] Detached HEAD detected; skipping base branch freshness check."
        )
        return 0

    if branch == args.base_branch:
        await cancel_task(remote_task)
        return 0

    remote = await remote_task
    try:
        await fetch_base(remote, args.base_branch, args.fetch_timeout_seconds)
    except RuntimeError as exc:
        print(
            f"[pre-push] Failed to fetch {remote}/{args.base_branch}: {exc}",
            file=sys.stderr,
        )
        return 1

    if not await remote_ref_exists(remote, args.base_branch):
        print(
            f"[pre-push] Missing remote tracking ref {remote}/{args.base_branch}.",
            file=sys.stderr,
        )
        return 1

    base_ref = f"{remote}/{args.base_branch}"
    if await is_base_ancestor_of_head(base_ref):
        return 0

    ahead, behind = await ahead_behind(base_ref)
    print(
        f"[pre-push] Branch '{branch}' is not up to date with {base_ref} "
        f"(ahead={ahead}, behind={behind}).",
        file=sys.stderr,
    )
    print(
        "[pre-push] Rebase before pushing:",
        file=sys.stderr,
    )
    print(
        f"  git fetch {remote} {args.base_branch}",
        file=sys.stderr,
    )
    print(
        f"  git rebase {base_ref}",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
