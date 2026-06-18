"""
TermuxForge Workflow Runner
=============================

Executes multi-step workflows with support for sequential and parallel
execution, conditional branching, retry logic, and detailed status
reporting.
"""

import asyncio
import json
import logging
import os
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional

logger = logging.getLogger("termux_forge.workflow_runner")


class StepStatus(Enum):
    """Status of a workflow step."""

    PENDING = "pending"
    RUNNING = "running"
    SUCCESS = "success"
    FAILED = "failed"
    SKIPPED = "skipped"
    RETRYING = "retrying"


class WorkflowStatus(Enum):
    """Overall workflow status."""

    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass
class WorkflowStep:
    """
    Definition of a single workflow step.

    Attributes
    ----------
    id : str
        Unique step identifier.
    name : str
        Human-readable step name.
    command : str
        Shell command to execute.
    cwd : str
        Working directory for the command.
    timeout : int
        Timeout in seconds (default 60).
    retries : int
        Maximum retry attempts on failure (default 0).
    retry_delay : int
        Seconds to wait between retries (default 5).
    condition : str
        Optional condition expression (e.g., "prev.success").
    depends_on : list[str]
        Step IDs that must complete before this step.
    env : dict[str, str]
        Extra environment variables for this step.
    continue_on_error : bool
        If True, workflow continues even if this step fails.
    parallel_group : str
        Steps with the same group run in parallel.
    """

    id: str
    name: str
    command: str
    cwd: str = ""
    timeout: int = 60
    retries: int = 0
    retry_delay: int = 5
    condition: str = ""
    depends_on: list[str] = field(default_factory=list)
    env: dict[str, str] = field(default_factory=dict)
    continue_on_error: bool = False
    parallel_group: str = ""


@dataclass
class StepResult:
    """Result of executing a workflow step."""

    step_id: str
    step_name: str
    status: StepStatus
    exit_code: int = 0
    stdout: str = ""
    stderr: str = ""
    duration: float = 0.0
    attempts: int = 1
    error: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "stepId": self.step_id,
            "stepName": self.step_name,
            "status": self.status.value,
            "exitCode": self.exit_code,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "duration": round(self.duration, 3),
            "attempts": self.attempts,
            "error": self.error,
        }


@dataclass
class WorkflowDefinition:
    """
    Complete workflow definition.

    Attributes
    ----------
    id : str
        Unique workflow identifier.
    name : str
        Human-readable workflow name.
    description : str
        Workflow description.
    steps : list[WorkflowStep]
        Ordered list of steps to execute.
    default_cwd : str
        Default working directory for steps.
    """

    id: str
    name: str
    description: str = ""
    steps: list[WorkflowStep] = field(default_factory=list)
    default_cwd: str = os.path.expanduser("~")

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "WorkflowDefinition":
        """Parse a workflow definition from a dictionary."""
        steps = []
        for s in data.get("steps", []):
            steps.append(WorkflowStep(
                id=s["id"],
                name=s.get("name", s["id"]),
                command=s["command"],
                cwd=s.get("cwd", ""),
                timeout=s.get("timeout", 60),
                retries=s.get("retries", 0),
                retry_delay=s.get("retryDelay", 5),
                condition=s.get("condition", ""),
                depends_on=s.get("dependsOn", []),
                env=s.get("env", {}),
                continue_on_error=s.get("continueOnError", False),
                parallel_group=s.get("parallelGroup", ""),
            ))
        return cls(
            id=data["id"],
            name=data.get("name", data["id"]),
            description=data.get("description", ""),
            steps=steps,
            default_cwd=data.get("defaultCwd", os.path.expanduser("~")),
        )


@dataclass
class WorkflowResult:
    """Result of a complete workflow execution."""

    workflow_id: str
    workflow_name: str
    status: WorkflowStatus
    step_results: list[StepResult] = field(default_factory=list)
    duration: float = 0.0
    error: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "workflowId": self.workflow_id,
            "workflowName": self.workflow_name,
            "status": self.status.value,
            "steps": [r.to_dict() for r in self.step_results],
            "duration": round(self.duration, 3),
            "error": self.error,
            "totalSteps": len(self.step_results),
            "passedSteps": sum(
                1 for r in self.step_results if r.status == StepStatus.SUCCESS
            ),
            "failedSteps": sum(
                1 for r in self.step_results if r.status == StepStatus.FAILED
            ),
        }


class WorkflowRunner:
    """
    Executes workflow definitions with full lifecycle management.

    Parameters
    ----------
    command_executor : object
        A CommandExecutor instance for running commands.
    """

    def __init__(self, command_executor: Any) -> None:
        self._executor = command_executor
        self._running_workflows: dict[str, WorkflowResult] = {}
        self._cancelled: set[str] = set()

    # ── Public API ────────────────────────────────────────────────────

    async def execute(
        self,
        workflow: WorkflowDefinition,
        on_step_update: Any = None,
    ) -> WorkflowResult:
        """
        Execute a complete workflow.

        Parameters
        ----------
        workflow : WorkflowDefinition
            The workflow to execute.
        on_step_update : callable, optional
            Called with ``StepResult`` after each step completes.

        Returns
        -------
        WorkflowResult
            Full results of the workflow execution.
        """
        logger.info("Starting workflow: %s (%s)", workflow.name, workflow.id)
        start = time.monotonic()

        result = WorkflowResult(
            workflow_id=workflow.id,
            workflow_name=workflow.name,
            status=WorkflowStatus.RUNNING,
        )
        self._running_workflows[workflow.id] = result

        completed_steps: dict[str, StepResult] = {}

        try:
            # Group steps for execution
            groups = self._build_execution_groups(workflow.steps)

            for group in groups:
                if workflow.id in self._cancelled:
                    result.status = WorkflowStatus.CANCELLED
                    break

                if len(group) == 1:
                    # Sequential execution
                    step = group[0]
                    step_result = await self._execute_step(
                        step, workflow.default_cwd, completed_steps,
                    )
                    result.step_results.append(step_result)
                    completed_steps[step.id] = step_result

                    if on_step_update:
                        on_step_update(step_result)

                    if (
                        step_result.status == StepStatus.FAILED
                        and not step.continue_on_error
                    ):
                        result.status = WorkflowStatus.FAILED
                        result.error = f"Step '{step.name}' failed"
                        break
                else:
                    # Parallel execution
                    tasks = [
                        self._execute_step(step, workflow.default_cwd, completed_steps)
                        for step in group
                    ]
                    step_results = await asyncio.gather(*tasks)

                    any_failed = False
                    for step, step_result in zip(group, step_results):
                        result.step_results.append(step_result)
                        completed_steps[step.id] = step_result
                        if on_step_update:
                            on_step_update(step_result)
                        if (
                            step_result.status == StepStatus.FAILED
                            and not step.continue_on_error
                        ):
                            any_failed = True

                    if any_failed:
                        result.status = WorkflowStatus.FAILED
                        result.error = "One or more parallel steps failed"
                        break

            if result.status == WorkflowStatus.RUNNING:
                result.status = WorkflowStatus.COMPLETED

        except Exception as exc:
            result.status = WorkflowStatus.FAILED
            result.error = str(exc)
            logger.exception("Workflow error: %s", workflow.id)

        result.duration = time.monotonic() - start
        self._running_workflows.pop(workflow.id, None)
        self._cancelled.discard(workflow.id)

        logger.info(
            "Workflow %s %s in %.1fs (%d/%d steps passed)",
            workflow.name, result.status.value, result.duration,
            sum(1 for r in result.step_results if r.status == StepStatus.SUCCESS),
            len(result.step_results),
        )
        return result

    def cancel(self, workflow_id: str) -> bool:
        """
        Request cancellation of a running workflow.

        Returns True if the workflow was found and cancellation requested.
        """
        if workflow_id in self._running_workflows:
            self._cancelled.add(workflow_id)
            return True
        return False

    def list_running(self) -> list[dict[str, Any]]:
        """Return status of all running workflows."""
        return [r.to_dict() for r in self._running_workflows.values()]

    # ── Private helpers ───────────────────────────────────────────────

    async def _execute_step(
        self,
        step: WorkflowStep,
        default_cwd: str,
        completed: dict[str, StepResult],
    ) -> StepResult:
        """Execute a single workflow step with retry logic."""
        # Evaluate condition
        if step.condition and not self._evaluate_condition(step.condition, completed):
            logger.info("Skipping step %s: condition not met", step.name)
            return StepResult(
                step_id=step.id, step_name=step.name,
                status=StepStatus.SKIPPED,
            )

        # Check dependencies
        for dep_id in step.depends_on:
            dep = completed.get(dep_id)
            if dep is None:
                return StepResult(
                    step_id=step.id, step_name=step.name,
                    status=StepStatus.SKIPPED,
                    error=f"Dependency '{dep_id}' not completed",
                )
            if dep.status == StepStatus.FAILED:
                return StepResult(
                    step_id=step.id, step_name=step.name,
                    status=StepStatus.SKIPPED,
                    error=f"Dependency '{dep_id}' failed",
                )

        cwd = step.cwd or default_cwd
        attempts = 0
        max_attempts = step.retries + 1

        while attempts < max_attempts:
            attempts += 1
            start = time.monotonic()

            try:
                cmd_result = await self._executor.execute(
                    command=step.command,
                    cwd=cwd,
                    timeout=step.timeout,
                    env=step.env or None,
                )

                duration = time.monotonic() - start

                if cmd_result.exit_code == 0:
                    return StepResult(
                        step_id=step.id, step_name=step.name,
                        status=StepStatus.SUCCESS,
                        exit_code=cmd_result.exit_code,
                        stdout=cmd_result.stdout,
                        stderr=cmd_result.stderr,
                        duration=duration,
                        attempts=attempts,
                    )

                if attempts < max_attempts:
                    logger.info(
                        "Step %s failed (attempt %d/%d), retrying in %ds…",
                        step.name, attempts, max_attempts, step.retry_delay,
                    )
                    await asyncio.sleep(step.retry_delay)
                    continue

                return StepResult(
                    step_id=step.id, step_name=step.name,
                    status=StepStatus.FAILED,
                    exit_code=cmd_result.exit_code,
                    stdout=cmd_result.stdout,
                    stderr=cmd_result.stderr,
                    duration=duration,
                    attempts=attempts,
                    error=f"Exit code {cmd_result.exit_code}",
                )

            except Exception as exc:
                duration = time.monotonic() - start
                if attempts < max_attempts:
                    await asyncio.sleep(step.retry_delay)
                    continue
                return StepResult(
                    step_id=step.id, step_name=step.name,
                    status=StepStatus.FAILED,
                    duration=duration, attempts=attempts,
                    error=str(exc),
                )

        # Should not reach here, but handle defensively
        return StepResult(
            step_id=step.id, step_name=step.name,
            status=StepStatus.FAILED,
            error="Exhausted all retry attempts",
            attempts=attempts,
        )

    @staticmethod
    def _evaluate_condition(
        condition: str,
        completed: dict[str, StepResult],
    ) -> bool:
        """
        Evaluate a simple condition expression.

        Supported forms:
        - ``"prev.success"`` – previous step succeeded
        - ``"step_id.success"`` – named step succeeded
        - ``"step_id.failed"`` – named step failed
        - ``"always"`` – always run
        """
        condition = condition.strip()

        if condition == "always":
            return True

        parts = condition.split(".")
        if len(parts) != 2:
            logger.warning("Invalid condition: %s", condition)
            return True  # Default to running

        step_ref, check = parts

        if step_ref == "prev":
            # Get last completed step
            if not completed:
                return False
            last = list(completed.values())[-1]
            target = last
        else:
            target = completed.get(step_ref)
            if target is None:
                return False

        if check == "success":
            return target.status == StepStatus.SUCCESS
        elif check == "failed":
            return target.status == StepStatus.FAILED
        elif check == "completed":
            return target.status in (StepStatus.SUCCESS, StepStatus.FAILED)

        return True

    @staticmethod
    def _build_execution_groups(
        steps: list[WorkflowStep],
    ) -> list[list[WorkflowStep]]:
        """
        Group steps into sequential batches and parallel groups.

        Steps with the same ``parallel_group`` value are executed
        concurrently. Steps without a group are executed sequentially.
        """
        groups: list[list[WorkflowStep]] = []
        current_parallel: dict[str, list[WorkflowStep]] = {}

        for step in steps:
            if step.parallel_group:
                if step.parallel_group not in current_parallel:
                    current_parallel[step.parallel_group] = []
                current_parallel[step.parallel_group].append(step)
            else:
                # Flush any pending parallel groups
                for pg_steps in current_parallel.values():
                    groups.append(pg_steps)
                current_parallel.clear()
                groups.append([step])

        # Flush remaining parallel groups
        for pg_steps in current_parallel.values():
            groups.append(pg_steps)

        return groups
