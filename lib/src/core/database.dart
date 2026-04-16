import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

enum JobStatus { queued, running, completed, failed, skipped }

enum IssueLifecycleState { opened, closed }

class ProjectStates extends Table {
  TextColumn get projectKey => text()();
  TextColumn get repo => text()();
  TextColumn get lastSeenUpdatedAt => text().nullable()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {projectKey};
}

class IssueThreadStates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get projectKey => text()();
  IntColumn get issueNumber => integer()();
  TextColumn get issueState =>
      textEnum<IssueLifecycleState>().withDefault(const Constant('opened'))();
  TextColumn get fingerprint => text()();
  TextColumn get lastEvaluatedFingerprint => text().nullable()();
  TextColumn get lastDecision => text().nullable()();
  IntColumn get lastProcessedCommentId => integer().nullable()();
  TextColumn get responderSessionId => text().nullable()();
  TextColumn get workspacePath => text().nullable()();
  IntColumn get lastCommentId => integer().nullable()();
  TextColumn get lastCommentUrl => text().nullable()();
  TextColumn get updatedAt => text()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {projectKey, issueNumber},
  ];
}

class Jobs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get projectKey => text()();
  IntColumn get issueNumber => integer()();
  TextColumn get fingerprint => text()();
  TextColumn get trigger => text()();
  TextColumn get status => textEnum<JobStatus>()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
}

class ExecutionRuns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get jobId => integer()();
  TextColumn get responderId => text()();
  TextColumn get mode => text()();
  TextColumn get decision => text()();
  BoolColumn get success => boolean()();
  TextColumn get workspacePath => text().nullable()();
  TextColumn get stdout => text()();
  TextColumn get stderr => text()();
  TextColumn get createdAt => text()();
}

class Comments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get projectKey => text()();
  IntColumn get issueNumber => integer()();
  TextColumn get fingerprint => text()();
  IntColumn get githubCommentId => integer()();
  TextColumn get githubCommentUrl => text()();
  TextColumn get body => text()();
  TextColumn get createdAt => text()();
}

class PollRuns extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get projectKey => text()();
  TextColumn get startedAt => text()();
  TextColumn get finishedAt => text().nullable()();
  BoolColumn get success => boolean().nullable()();
  TextColumn get error => text().nullable()();
}

@DriftDatabase(
  tables: [
    ProjectStates,
    IssueThreadStates,
    Jobs,
    ExecutionRuns,
    Comments,
    PollRuns,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.e);

  factory AppDatabase.open(String path) {
    return AppDatabase._(
      NativeDatabase.createInBackground(File(p.absolute(path))),
    );
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(
          issueThreadStates,
          issueThreadStates.issueState,
        );
        await migrator.addColumn(
          issueThreadStates,
          issueThreadStates.lastProcessedCommentId,
        );
        await migrator.addColumn(
          issueThreadStates,
          issueThreadStates.responderSessionId,
        );
        await migrator.addColumn(
          issueThreadStates,
          issueThreadStates.workspacePath,
        );
      }
    },
  );

  Future<ProjectState?> findProjectState(String projectKey) {
    return (select(
      projectStates,
    )..where((tbl) => tbl.projectKey.equals(projectKey))).getSingleOrNull();
  }

  Future<void> upsertProjectState({
    required String projectKey,
    required String repo,
    required DateTime? lastSeenUpdatedAt,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return into(projectStates).insertOnConflictUpdate(
      ProjectStatesCompanion.insert(
        projectKey: projectKey,
        repo: repo,
        lastSeenUpdatedAt: Value(lastSeenUpdatedAt?.toIso8601String()),
        updatedAt: now,
      ),
    );
  }

  Future<IssueThreadState?> findIssueThread(
    String projectKey,
    int issueNumber,
  ) {
    return (select(issueThreadStates)
          ..where((tbl) => tbl.projectKey.equals(projectKey))
          ..where((tbl) => tbl.issueNumber.equals(issueNumber)))
        .getSingleOrNull();
  }

  Future<void> upsertIssueThread({
    required String projectKey,
    required int issueNumber,
    IssueLifecycleState issueState = IssueLifecycleState.opened,
    required String fingerprint,
    required DateTime updatedAt,
    String? lastEvaluatedFingerprint,
    String? lastDecision,
    int? lastProcessedCommentId,
    String? responderSessionId,
    String? workspacePath,
    int? lastCommentId,
    String? lastCommentUrl,
  }) async {
    final existing = await findIssueThread(projectKey, issueNumber);
    final companion = IssueThreadStatesCompanion(
      projectKey: Value(projectKey),
      issueNumber: Value(issueNumber),
      issueState: Value(issueState),
      fingerprint: Value(fingerprint),
      lastEvaluatedFingerprint: Value(lastEvaluatedFingerprint),
      lastDecision: Value(lastDecision),
      lastProcessedCommentId: Value(lastProcessedCommentId),
      responderSessionId: Value(responderSessionId),
      workspacePath: Value(workspacePath),
      lastCommentId: Value(lastCommentId),
      lastCommentUrl: Value(lastCommentUrl),
      updatedAt: Value(updatedAt.toUtc().toIso8601String()),
    );

    if (existing == null) {
      await into(issueThreadStates).insert(
        IssueThreadStatesCompanion.insert(
          projectKey: projectKey,
          issueNumber: issueNumber,
          issueState: Value(issueState),
          fingerprint: fingerprint,
          updatedAt: updatedAt.toUtc().toIso8601String(),
          lastEvaluatedFingerprint: Value(lastEvaluatedFingerprint),
          lastDecision: Value(lastDecision),
          lastProcessedCommentId: Value(lastProcessedCommentId),
          responderSessionId: Value(responderSessionId),
          workspacePath: Value(workspacePath),
          lastCommentId: Value(lastCommentId),
          lastCommentUrl: Value(lastCommentUrl),
        ),
      );
      return;
    }

    await (update(
      issueThreadStates,
    )..where((tbl) => tbl.id.equals(existing.id))).write(companion);
  }

  Future<int> createJob({
    required String projectKey,
    required int issueNumber,
    required String fingerprint,
    required String trigger,
    required JobStatus status,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return into(jobs).insert(
      JobsCompanion.insert(
        projectKey: projectKey,
        issueNumber: issueNumber,
        fingerprint: fingerprint,
        trigger: trigger,
        status: status,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> updateJobStatus(int jobId, JobStatus status) {
    return (update(jobs)..where((tbl) => tbl.id.equals(jobId))).write(
      JobsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now().toUtc().toIso8601String()),
      ),
    );
  }

  Future<void> addExecutionRun({
    required int jobId,
    required String responderId,
    required String mode,
    required String decision,
    required bool success,
    required String workspacePath,
    required String stdout,
    required String stderr,
  }) {
    return into(executionRuns).insert(
      ExecutionRunsCompanion.insert(
        jobId: jobId,
        responderId: responderId,
        mode: mode,
        decision: decision,
        success: success,
        workspacePath: Value(workspacePath),
        stdout: stdout,
        stderr: stderr,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  Future<void> addCommentRecord({
    required String projectKey,
    required int issueNumber,
    required String fingerprint,
    required int githubCommentId,
    required String githubCommentUrl,
    required String body,
  }) {
    return into(comments).insert(
      CommentsCompanion.insert(
        projectKey: projectKey,
        issueNumber: issueNumber,
        fingerprint: fingerprint,
        githubCommentId: githubCommentId,
        githubCommentUrl: githubCommentUrl,
        body: body,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  Future<int> startPollRun(String projectKey) {
    return into(pollRuns).insert(
      PollRunsCompanion.insert(
        projectKey: projectKey,
        startedAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  Future<void> finishPollRun({
    required int pollRunId,
    required bool success,
    String? error,
  }) {
    return (update(pollRuns)..where((tbl) => tbl.id.equals(pollRunId))).write(
      PollRunsCompanion(
        finishedAt: Value(DateTime.now().toUtc().toIso8601String()),
        success: Value(success),
        error: Value(error),
      ),
    );
  }
}
