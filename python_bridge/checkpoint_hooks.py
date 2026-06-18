"""
TermuxForge Checkpoint Hooks
===============================

Checkpoint management for creating and restoring file and git
state snapshots. Enables safe experimentation by allowing
rollback to known-good states.
"""

import asyncio
import hashlib
import json
import logging
import os
import shutil
import time
from dataclasses import dataclass, field
from typing import Any, Optional

logger = logging.getLogger("termux_forge.checkpoint_hooks")

CHECKPOINT_DIR = os.path.expanduser("~/.termux_forge/checkpoints")


@dataclass
class FileSnapshot:
    """Snapshot of a single file."""

    path: str
    hash: str
    size: int
    exists: bool
    content: str = ""  # Only stored for small files

    def to_dict(self) -> dict[str, Any]:
        return {
            "path": self.path,
            "hash": self.hash,
            "size": self.size,
            "exists": self.exists,
        }


@dataclass
class GitSnapshot:
    """Snapshot of the git repository state."""

    branch: str = ""
    commit_hash: str = ""
    has_changes: bool = False
    staged_files: list[str] = field(default_factory=list)
    modified_files: list[str] = field(default_factory=list)
    untracked_files: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "branch": self.branch,
            "commitHash": self.commit_hash,
            "hasChanges": self.has_changes,
            "stagedFiles": self.staged_files,
            "modifiedFiles": self.modified_files,
            "untrackedFiles": self.untracked_files,
        }


@dataclass
class Checkpoint:
    """
    A complete checkpoint capturing file and git state.

    Attributes
    ----------
    id : str
        Unique checkpoint identifier.
    name : str
        Human-readable checkpoint name.
    created_at : float
        Unix timestamp of creation.
    workspace : str
        Workspace root directory.
    files : list[FileSnapshot]
        Captured file snapshots.
    git_state : GitSnapshot | None
        Git repository state at checkpoint time.
    description : str
        Optional description.
    """

    id: str
    name: str
    created_at: float
    workspace: str
    files: list[FileSnapshot] = field(default_factory=list)
    git_state: Optional[GitSnapshot] = None
    description: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "createdAt": self.created_at,
            "workspace": self.workspace,
            "fileCount": len(self.files),
            "gitState": self.git_state.to_dict() if self.git_state else None,
            "description": self.description,
        }


class CheckpointManager:
    """
    Manages checkpoints for file and git state snapshots.

    Checkpoints are stored in ``~/.termux_forge/checkpoints/``.

    Parameters
    ----------
    workspace : str
        Default workspace root directory.
    max_file_size : int
        Maximum file size (bytes) to store content inline (default 1 MB).
    """

    def __init__(
        self,
        workspace: str = os.path.expanduser("~"),
        max_file_size: int = 1_048_576,
    ) -> None:
        self.workspace = workspace
        self.max_file_size = max_file_size
        os.makedirs(CHECKPOINT_DIR, exist_ok=True)

    # ── Create ────────────────────────────────────────────────────────

    async def create(
        self,
        name: str,
        paths: list[str] | None = None,
        include_git: bool = True,
        description: str = "",
    ) -> Checkpoint:
        """
        Create a new checkpoint.

        Parameters
        ----------
        name : str
            Checkpoint name.
        paths : list[str], optional
            Specific file paths to snapshot. If omitted, only git state
            is captured.
        include_git : bool
            Whether to capture git repository state.
        description : str
            Optional description.

        Returns
        -------
        Checkpoint
            The created checkpoint.
        """
        checkpoint_id = f"cp_{int(time.time())}_{name.replace(' ', '_')}"
        logger.info("Creating checkpoint: %s", checkpoint_id)

        files: list[FileSnapshot] = []
        if paths:
            files = await self._snapshot_files(paths)

        git_state = None
        if include_git:
            git_state = await self._snapshot_git(self.workspace)

        checkpoint = Checkpoint(
            id=checkpoint_id,
            name=name,
            created_at=time.time(),
            workspace=self.workspace,
            files=files,
            git_state=git_state,
            description=description,
        )

        # Persist checkpoint
        self._save_checkpoint(checkpoint)
        logger.info(
            "Checkpoint created: %s (%d files)",
            checkpoint_id, len(files),
        )
        return checkpoint

    # ── List ──────────────────────────────────────────────────────────

    def list_checkpoints(self) -> list[dict[str, Any]]:
        """
        List all available checkpoints.

        Returns
        -------
        list[dict]
            Summary information for each checkpoint.
        """
        checkpoints = []
        if not os.path.isdir(CHECKPOINT_DIR):
            return checkpoints

        for fname in sorted(os.listdir(CHECKPOINT_DIR)):
            if not fname.endswith(".json"):
                continue
            path = os.path.join(CHECKPOINT_DIR, fname)
            try:
                with open(path) as f:
                    data = json.load(f)
                checkpoints.append({
                    "id": data["id"],
                    "name": data["name"],
                    "createdAt": data["createdAt"],
                    "workspace": data["workspace"],
                    "fileCount": data.get("fileCount", 0),
                    "description": data.get("description", ""),
                })
            except Exception as exc:
                logger.error("Error reading checkpoint %s: %s", fname, exc)

        return checkpoints

    # ── Compare ───────────────────────────────────────────────────────

    async def compare(self, checkpoint_id: str) -> dict[str, Any]:
        """
        Compare the current state with a checkpoint.

        Parameters
        ----------
        checkpoint_id : str
            Checkpoint ID to compare against.

        Returns
        -------
        dict
            Differences between current state and checkpoint.
        """
        checkpoint = self._load_checkpoint(checkpoint_id)
        if not checkpoint:
            return {"error": f"Checkpoint not found: {checkpoint_id}"}

        differences: dict[str, Any] = {
            "checkpointId": checkpoint_id,
            "checkpointName": checkpoint.get("name", ""),
            "files": {"modified": [], "added": [], "deleted": []},
            "git": {},
        }

        # Compare files
        for file_data in checkpoint.get("files", []):
            path = file_data["path"]
            old_hash = file_data["hash"]

            if os.path.exists(path):
                current_hash = self._file_hash(path)
                if current_hash != old_hash:
                    differences["files"]["modified"].append(path)
            else:
                differences["files"]["deleted"].append(path)

        # Compare git state
        if checkpoint.get("gitState"):
            current_git = await self._snapshot_git(
                checkpoint.get("workspace", self.workspace),
            )
            if current_git:
                old_git = checkpoint["gitState"]
                differences["git"] = {
                    "branchChanged": current_git.branch != old_git.get("branch", ""),
                    "currentBranch": current_git.branch,
                    "checkpointBranch": old_git.get("branch", ""),
                    "currentCommit": current_git.commit_hash,
                    "checkpointCommit": old_git.get("commitHash", ""),
                    "commitsAhead": await self._commits_between(
                        old_git.get("commitHash", ""),
                        current_git.commit_hash,
                        checkpoint.get("workspace", self.workspace),
                    ),
                }

        return differences

    # ── Rollback ──────────────────────────────────────────────────────

    async def rollback(
        self,
        checkpoint_id: str,
        restore_files: bool = True,
        restore_git: bool = False,
    ) -> dict[str, Any]:
        """
        Rollback to a checkpoint state.

        Parameters
        ----------
        checkpoint_id : str
            Checkpoint to rollback to.
        restore_files : bool
            Whether to restore file contents.
        restore_git : bool
            Whether to restore git state (git checkout).

        Returns
        -------
        dict
            Summary of rollback actions taken.
        """
        checkpoint = self._load_checkpoint(checkpoint_id)
        if not checkpoint:
            return {"success": False, "error": f"Checkpoint not found: {checkpoint_id}"}

        actions: list[str] = []

        # Restore files
        if restore_files:
            backup_dir = os.path.join(
                CHECKPOINT_DIR, checkpoint_id, "files",
            )
            for file_data in checkpoint.get("files", []):
                path = file_data["path"]
                backup = os.path.join(
                    backup_dir,
                    hashlib.md5(path.encode()).hexdigest(),
                )
                if os.path.exists(backup):
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    shutil.copy2(backup, path)
                    actions.append(f"Restored: {path}")
                elif not file_data.get("exists", True):
                    if os.path.exists(path):
                        os.remove(path)
                        actions.append(f"Removed: {path}")

        # Restore git state
        if restore_git and checkpoint.get("gitState"):
            git = checkpoint["gitState"]
            cwd = checkpoint.get("workspace", self.workspace)
            commit = git.get("commitHash", "")
            branch = git.get("branch", "")
            if commit:
                result = await self._run_git(
                    f"git checkout {branch} && git reset --hard {commit}",
                    cwd,
                )
                if result:
                    actions.append(f"Git restored to {commit[:8]} on {branch}")

        logger.info(
            "Rollback to %s: %d actions", checkpoint_id, len(actions),
        )
        return {
            "success": True,
            "checkpointId": checkpoint_id,
            "actions": actions,
        }

    # ── Delete ────────────────────────────────────────────────────────

    def delete_checkpoint(self, checkpoint_id: str) -> bool:
        """Delete a checkpoint and its stored files."""
        meta_path = os.path.join(CHECKPOINT_DIR, f"{checkpoint_id}.json")
        files_dir = os.path.join(CHECKPOINT_DIR, checkpoint_id)

        deleted = False
        if os.path.exists(meta_path):
            os.remove(meta_path)
            deleted = True
        if os.path.isdir(files_dir):
            shutil.rmtree(files_dir)
            deleted = True

        if deleted:
            logger.info("Deleted checkpoint: %s", checkpoint_id)
        return deleted

    # ── Private: file snapshots ───────────────────────────────────────

    async def _snapshot_files(
        self, paths: list[str],
    ) -> list[FileSnapshot]:
        """Create snapshots for a list of file paths."""
        snapshots = []
        for path in paths:
            if os.path.exists(path):
                file_hash = self._file_hash(path)
                size = os.path.getsize(path)
                snapshots.append(FileSnapshot(
                    path=path, hash=file_hash,
                    size=size, exists=True,
                ))
            else:
                snapshots.append(FileSnapshot(
                    path=path, hash="", size=0, exists=False,
                ))
        return snapshots

    @staticmethod
    def _file_hash(path: str) -> str:
        """Compute the SHA-256 hash of a file."""
        h = hashlib.sha256()
        try:
            with open(path, "rb") as f:
                for chunk in iter(lambda: f.read(8192), b""):
                    h.update(chunk)
            return h.hexdigest()
        except Exception:
            return ""

    # ── Private: git snapshots ────────────────────────────────────────

    async def _snapshot_git(self, cwd: str) -> Optional[GitSnapshot]:
        """Capture the current git state."""
        try:
            branch = await self._run_git("git branch --show-current", cwd)
            commit = await self._run_git("git rev-parse HEAD", cwd)
            status = await self._run_git("git status --porcelain", cwd)

            if not commit:
                return None

            staged = []
            modified = []
            untracked = []

            for line in (status or "").splitlines():
                if not line or len(line) < 3:
                    continue
                idx, wt = line[0], line[1]
                fname = line[3:]
                if idx in ("A", "M", "D", "R"):
                    staged.append(fname)
                if wt == "M":
                    modified.append(fname)
                if idx == "?":
                    untracked.append(fname)

            return GitSnapshot(
                branch=branch or "main",
                commit_hash=commit,
                has_changes=bool(status),
                staged_files=staged,
                modified_files=modified,
                untracked_files=untracked,
            )
        except Exception as exc:
            logger.error("Git snapshot error: %s", exc)
            return None

    async def _commits_between(
        self, from_hash: str, to_hash: str, cwd: str,
    ) -> int:
        """Count commits between two hashes."""
        if not from_hash or not to_hash:
            return 0
        output = await self._run_git(
            f"git rev-list --count {from_hash}..{to_hash}", cwd,
        )
        try:
            return int(output) if output else 0
        except ValueError:
            return 0

    @staticmethod
    async def _run_git(command: str, cwd: str) -> str:
        """Run a git command and return stripped stdout."""
        try:
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                cwd=cwd,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=15)
            return stdout.decode("utf-8", errors="replace").strip()
        except Exception:
            return ""

    # ── Private: persistence ──────────────────────────────────────────

    def _save_checkpoint(self, checkpoint: Checkpoint) -> None:
        """Save checkpoint metadata and file backups to disk."""
        # Save metadata
        meta_path = os.path.join(CHECKPOINT_DIR, f"{checkpoint.id}.json")
        data = checkpoint.to_dict()
        data["files"] = [f.to_dict() for f in checkpoint.files]
        if checkpoint.git_state:
            data["gitState"] = checkpoint.git_state.to_dict()

        with open(meta_path, "w") as f:
            json.dump(data, f, indent=2)

        # Backup file contents
        if checkpoint.files:
            backup_dir = os.path.join(
                CHECKPOINT_DIR, checkpoint.id, "files",
            )
            os.makedirs(backup_dir, exist_ok=True)

            for file_snap in checkpoint.files:
                if file_snap.exists and file_snap.size <= self.max_file_size:
                    backup_name = hashlib.md5(
                        file_snap.path.encode()
                    ).hexdigest()
                    try:
                        shutil.copy2(
                            file_snap.path,
                            os.path.join(backup_dir, backup_name),
                        )
                    except Exception as exc:
                        logger.error(
                            "Failed to backup %s: %s",
                            file_snap.path, exc,
                        )

    def _load_checkpoint(self, checkpoint_id: str) -> Optional[dict]:
        """Load checkpoint metadata from disk."""
        meta_path = os.path.join(CHECKPOINT_DIR, f"{checkpoint_id}.json")
        if not os.path.exists(meta_path):
            return None
        try:
            with open(meta_path) as f:
                return json.load(f)
        except Exception as exc:
            logger.error("Failed to load checkpoint %s: %s", checkpoint_id, exc)
            return None
