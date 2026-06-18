"""
TermuxForge GitHub Hooks
==========================

Integration with the GitHub CLI (``gh``) for git operations,
workflow management, build status, artifact downloading, and
release creation.

Requires ``git`` and ``gh`` to be installed and authenticated.
"""

import asyncio
import json
import logging
import os
import time
from dataclasses import dataclass, field
from typing import Any, Optional

logger = logging.getLogger("termux_forge.github_hooks")

DEFAULT_CWD = os.path.expanduser("~")


@dataclass
class GitResult:
    """Result of a git/GitHub CLI operation."""

    success: bool
    output: str = ""
    error: str = ""
    data: Any = None

    def to_dict(self) -> dict[str, Any]:
        result = {
            "success": self.success,
            "output": self.output,
            "error": self.error,
        }
        if self.data is not None:
            result["data"] = self.data
        return result


class GitHubHooks:
    """
    GitHub CLI integration for TermuxForge.

    Provides methods for common git and GitHub operations including
    pushing code, triggering workflows, checking build status,
    downloading artifacts, and creating releases.

    Parameters
    ----------
    cwd : str
        Default working directory (should be a git repository).
    """

    def __init__(self, cwd: str = DEFAULT_CWD) -> None:
        self.cwd = cwd

    # ── Git operations ────────────────────────────────────────────────

    async def git_status(self, cwd: str | None = None) -> GitResult:
        """Get the current git status."""
        return await self._run("git status --porcelain", cwd)

    async def git_diff(
        self, cwd: str | None = None, staged: bool = False,
    ) -> GitResult:
        """Get the current git diff."""
        cmd = "git diff --staged" if staged else "git diff"
        return await self._run(cmd, cwd)

    async def git_commit(
        self,
        message: str,
        cwd: str | None = None,
        add_all: bool = True,
    ) -> GitResult:
        """
        Commit changes to git.

        Parameters
        ----------
        message : str
            Commit message.
        cwd : str, optional
            Working directory.
        add_all : bool
            If True, stage all changes before committing.
        """
        work_dir = cwd or self.cwd

        if add_all:
            add_result = await self._run("git add -A", work_dir)
            if not add_result.success:
                return add_result

        # Escape message for shell
        safe_message = message.replace("'", "'\\''")
        return await self._run(f"git commit -m '{safe_message}'", work_dir)

    async def push_code(
        self,
        message: str = "Update",
        branch: str | None = None,
        cwd: str | None = None,
    ) -> GitResult:
        """
        Stage, commit, and push all changes.

        Parameters
        ----------
        message : str
            Commit message.
        branch : str, optional
            Branch to push to (auto-detected if omitted).
        cwd : str, optional
            Working directory.
        """
        work_dir = cwd or self.cwd

        # Stage
        result = await self._run("git add -A", work_dir)
        if not result.success:
            return result

        # Commit
        safe_message = message.replace("'", "'\\''")
        result = await self._run(f"git commit -m '{safe_message}'", work_dir)
        if not result.success and "nothing to commit" not in result.output:
            return result

        # Push
        if branch:
            cmd = f"git push origin {branch}"
        else:
            cmd = "git push"
        return await self._run(cmd, work_dir)

    async def git_pull(
        self,
        branch: str | None = None,
        cwd: str | None = None,
    ) -> GitResult:
        """Pull latest changes from remote."""
        cmd = f"git pull origin {branch}" if branch else "git pull"
        return await self._run(cmd, cwd)

    # ── GitHub Actions workflows ──────────────────────────────────────

    async def trigger_workflow(
        self,
        workflow: str,
        ref: str = "main",
        inputs: dict[str, str] | None = None,
        cwd: str | None = None,
    ) -> GitResult:
        """
        Trigger a GitHub Actions workflow.

        Parameters
        ----------
        workflow : str
            Workflow filename or ID (e.g., "build.yml").
        ref : str
            Branch or tag to run against.
        inputs : dict, optional
            Workflow input parameters.
        """
        cmd = f"gh workflow run {workflow} --ref {ref}"
        if inputs:
            for key, value in inputs.items():
                safe_val = value.replace("'", "'\\''")
                cmd += f" -f {key}='{safe_val}'"
        return await self._run(cmd, cwd)

    async def list_workflows(self, cwd: str | None = None) -> GitResult:
        """List all GitHub Actions workflows in the repository."""
        result = await self._run(
            "gh workflow list --json name,id,state", cwd,
        )
        if result.success:
            try:
                result.data = json.loads(result.output)
            except json.JSONDecodeError:
                pass
        return result

    async def get_build_status(
        self,
        workflow: str | None = None,
        limit: int = 5,
        cwd: str | None = None,
    ) -> GitResult:
        """
        Get the status of recent workflow runs.

        Parameters
        ----------
        workflow : str, optional
            Filter by workflow name.
        limit : int
            Number of runs to return.
        """
        cmd = f"gh run list --limit {limit} --json databaseId,displayTitle,status,conclusion,createdAt,headBranch,workflowName"
        if workflow:
            cmd += f" --workflow {workflow}"
        result = await self._run(cmd, cwd)
        if result.success:
            try:
                result.data = json.loads(result.output)
            except json.JSONDecodeError:
                pass
        return result

    async def get_build_logs(
        self,
        run_id: str,
        cwd: str | None = None,
    ) -> GitResult:
        """Get logs for a specific workflow run."""
        return await self._run(f"gh run view {run_id} --log", cwd)

    async def download_artifact(
        self,
        run_id: str,
        name: str | None = None,
        output_dir: str | None = None,
        cwd: str | None = None,
    ) -> GitResult:
        """
        Download artifacts from a workflow run.

        Parameters
        ----------
        run_id : str
            The workflow run ID.
        name : str, optional
            Specific artifact name to download.
        output_dir : str, optional
            Directory to save artifacts to.
        """
        cmd = f"gh run download {run_id}"
        if name:
            cmd += f" -n {name}"
        if output_dir:
            cmd += f" -D {output_dir}"
        return await self._run(cmd, cwd)

    # ── Releases ──────────────────────────────────────────────────────

    async def create_release(
        self,
        tag: str,
        title: str | None = None,
        notes: str | None = None,
        files: list[str] | None = None,
        draft: bool = False,
        prerelease: bool = False,
        cwd: str | None = None,
    ) -> GitResult:
        """
        Create a GitHub release.

        Parameters
        ----------
        tag : str
            Release tag (e.g., "v1.0.0").
        title : str, optional
            Release title (defaults to tag).
        notes : str, optional
            Release notes body.
        files : list[str], optional
            Files to attach to the release.
        draft : bool
            Create as a draft release.
        prerelease : bool
            Mark as pre-release.
        """
        title = title or tag
        safe_title = title.replace("'", "'\\''")
        cmd = f"gh release create {tag} --title '{safe_title}'"

        if notes:
            safe_notes = notes.replace("'", "'\\''")
            cmd += f" --notes '{safe_notes}'"
        else:
            cmd += " --generate-notes"

        if draft:
            cmd += " --draft"
        if prerelease:
            cmd += " --prerelease"
        if files:
            cmd += " " + " ".join(files)

        return await self._run(cmd, cwd)

    # ── Utility ───────────────────────────────────────────────────────

    async def check_auth(self) -> GitResult:
        """Check if the GitHub CLI is authenticated."""
        return await self._run("gh auth status")

    async def get_repo_info(self, cwd: str | None = None) -> GitResult:
        """Get information about the current repository."""
        result = await self._run(
            "gh repo view --json name,owner,url,description,defaultBranchRef",
            cwd,
        )
        if result.success:
            try:
                result.data = json.loads(result.output)
            except json.JSONDecodeError:
                pass
        return result

    # ── Private subprocess runner ─────────────────────────────────────

    async def _run(
        self,
        command: str,
        cwd: str | None = None,
        timeout: int = 120,
    ) -> GitResult:
        """
        Execute a shell command and return a GitResult.

        Parameters
        ----------
        command : str
            Shell command to run.
        cwd : str, optional
            Working directory.
        timeout : int
            Timeout in seconds.
        """
        work_dir = cwd or self.cwd
        logger.debug("Running: %s (cwd=%s)", command, work_dir)

        try:
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=work_dir,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=timeout,
            )

            stdout_text = stdout.decode("utf-8", errors="replace").strip()
            stderr_text = stderr.decode("utf-8", errors="replace").strip()

            success = proc.returncode == 0
            return GitResult(
                success=success,
                output=stdout_text or stderr_text,
                error=stderr_text if not success else "",
            )

        except asyncio.TimeoutError:
            return GitResult(
                success=False,
                error=f"Command timed out after {timeout}s: {command}",
            )
        except Exception as exc:
            logger.exception("GitHub hook error: %s", command)
            return GitResult(success=False, error=str(exc))
