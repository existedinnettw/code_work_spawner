import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_support.dart';

part 'issue_assistant_app_run_once_core.dart';
part 'issue_assistant_app_run_once_worktree.dart';
part 'issue_assistant_app_run_once_notifications.dart';
part 'issue_assistant_app_run_once_concurrency.dart';
part 'issue_assistant_app_run_once_multi_project.dart';
part 'issue_assistant_app_run_webhook_forward.dart';
part 'issue_assistant_app_run_retry.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  registerIssueAssistantAppRunOnceCoreTests();
  registerIssueAssistantAppRunOnceWorktreeTests();
  registerIssueAssistantAppRunOnceNotificationTests();
  registerIssueAssistantAppRunOnceConcurrencyTests();
  registerIssueAssistantAppRunOnceMultiProjectTests();
  registerIssueAssistantAppRunWebhookForwardTests();
  registerIssueAssistantAppRunRetryTests();
}
