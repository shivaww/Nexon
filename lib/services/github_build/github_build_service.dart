/// GitHub Actions integration service for CI/CD from Termux.
///
/// [GitHubBuildService] wraps the `git` and `gh` CLI tools available in
/// Termux to push code, trigger GitHub Actions workflows, monitor build
/// status, and download build artifacts.
library;

import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';

// ---------------------------------------------------------------------------
// BuildStatus
// ---------------------------------------------------------------------------

/// Status of a GitHub Actions workflow run.
enum BuildStatus {
  /// The workflow run is queued.
  queued,

  /// The workflow run is in progress.
  inProgress,

  /// The workflow run completed successfully.
  success,

  /// The workflow run failed.
  failure,

  /// The workflow run was cancelled.
  cancelled,

  /// Status is unknown.
  unknown,
}

// ---------------------------------------------------------------------------
// BuildInfo
// ---------------------------------------------------------------------------

/// Summary of a GitHub Actions workflow run.
class BuildInfo {
  const BuildInfo({
    required this.runId,
    required this.workflowName,
    required this.status,
    this.conclusion,
    this.htmlUrl,
    this.createdAt,
    this.updatedAt,
  });

  /// The workflow run ID.
  final String runId;

  /// Name of the workflow.
  final String workflowName;

  /// Current status.
  final BuildStatus status;

  /// Final conclusion (if completed).
  final String? conclusion;

  /// URL to the run on GitHub.
  final String? htmlUrl;

  /// When the run was created.
  final DateTime? createdAt;

  /// When the run was last updated.
  final DateTime? updatedAt;
}

// ---------------------------------------------------------------------------
// GitHubBuildService
// ---------------------------------------------------------------------------

/// Service for interacting with GitHub Actions through the Termux CLI bridge.
///
/// Requires `git` and `gh` (GitHub CLI) to be installed in Termux.
class GitHubBuildService {
  GitHubBuildService({this.workingDirectory});

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  /// The git repository working directory. Defaults to current directory.
  final String? workingDirectory;

  // ---- Helpers ------------------------------------------------------------

  /// Run a shell command and return stdout.
  Future<String> _run(String command, List<String> args) async {
    _log.d('Running: $command ${args.join(' ')}');
    final result = await Process.run(
      command,
      args,
      workingDirectory: workingDirectory,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      final error = 'Command failed ($command): ${result.stderr}';
      _log.e(error);
      throw Exception(error);
    }
    return (result.stdout as String).trim();
  }

  // ---- Git operations -----------------------------------------------------

  /// Stage all changes, commit, and push to the remote.
  Future<String> pushAndBuild({
    String message = 'Auto-commit from TermuxForge',
    String branch = 'main',
  }) async {
    await _run('git', ['add', '.']);
    await _run('git', ['commit', '-m', message]);
    final output = await _run('git', ['push', 'origin', branch]);
    _log.i('Pushed to $branch');
    return output;
  }

  // ---- GitHub Actions operations ------------------------------------------

  /// Get the status of the latest workflow run.
  Future<BuildInfo> getBuildStatus({String? workflowName}) async {
    final args = [
      'run',
      'list',
      '--limit',
      '1',
      '--json',
      'databaseId,name,status,conclusion,url,createdAt,updatedAt',
    ];
    if (workflowName != null) {
      args.addAll(['--workflow', workflowName]);
    }

    final output = await _run('gh', args);
    final runs = jsonDecode(output) as List;
    if (runs.isEmpty) {
      return const BuildInfo(
        runId: '',
        workflowName: 'none',
        status: BuildStatus.unknown,
      );
    }

    final run = runs.first as Map<String, dynamic>;
    return BuildInfo(
      runId: run['databaseId'].toString(),
      workflowName: run['name'] as String? ?? 'unknown',
      status: _parseStatus(run['status'] as String?),
      conclusion: run['conclusion'] as String?,
      htmlUrl: run['url'] as String?,
      createdAt: run['createdAt'] != null
          ? DateTime.tryParse(run['createdAt'] as String)
          : null,
      updatedAt: run['updatedAt'] != null
          ? DateTime.tryParse(run['updatedAt'] as String)
          : null,
    );
  }

  /// Download a build artifact by name.
  Future<String> downloadArtifact(
    String artifactName, {
    String outputDir = '.',
  }) async {
    final output = await _run('gh', [
      'run',
      'download',
      '--name',
      artifactName,
      '--dir',
      outputDir,
    ]);
    _log.i('Downloaded artifact: $artifactName → $outputDir');
    return output;
  }

  /// List available workflows.
  Future<List<String>> listWorkflows() async {
    final output = await _run('gh', [
      'workflow',
      'list',
      '--json',
      'name',
    ]);
    final workflows = jsonDecode(output) as List;
    return workflows
        .map((w) => (w as Map<String, dynamic>)['name'] as String)
        .toList();
  }

  /// Trigger a workflow dispatch event.
  Future<void> triggerWorkflow(
    String workflowName, {
    String ref = 'main',
    Map<String, String> inputs = const {},
  }) async {
    final args = [
      'workflow',
      'run',
      workflowName,
      '--ref',
      ref,
    ];
    for (final entry in inputs.entries) {
      args.addAll(['-f', '${entry.key}=${entry.value}']);
    }
    await _run('gh', args);
    _log.i('Triggered workflow: $workflowName');
  }

  /// Get the logs for a specific run.
  Future<String> getBuildLogs(String runId) async {
    return _run('gh', ['run', 'view', runId, '--log']);
  }

  /// Get artifacts from the latest run.
  Future<String> getArtifacts({String? runId}) async {
    final args = ['run', 'view'];
    if (runId != null) args.add(runId);
    args.addAll(['--json', 'artifacts']);
    return _run('gh', args);
  }

  // ---- Helpers ------------------------------------------------------------

  BuildStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'queued':
        return BuildStatus.queued;
      case 'in_progress':
        return BuildStatus.inProgress;
      case 'completed':
        return BuildStatus.success;
      case 'failure':
        return BuildStatus.failure;
      case 'cancelled':
        return BuildStatus.cancelled;
      default:
        return BuildStatus.unknown;
    }
  }
}
