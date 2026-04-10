import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:github/github.dart';
import 'package:test/test.dart';

void main() {
  /// ```gherkin
  /// Feature: Routed issue event sources
  ///
  ///   As a maintainer configuring channel-based event sources
  ///   I want startup reconciliation and continuous reconciliation to route differently
  ///   So that channel sources can opt into either startup-only or background recovery polling
  /// ```
  group('RoutedIssueEventSource', () {
    /// ```gherkin
    /// Scenario: Run startup-only reconciliation for channel sources
    ///   Given a routed event source with fake polling and channel handlers
    ///   And a project that uses gh/webhook-forward with startup-only reconciliation
    ///   When the routed event source starts in long-running mode
    ///   Then the polling source runs once for startup reconciliation
    ///   And only the channel source stays registered for long-running execution
    /// ```
    test('Run startup-only reconciliation for channel sources', () async {
      // Given a routed event source with fake polling and channel handlers.
      final polling = _RecordingIssueEventSource();
      final webhookForward = _RecordingIssueEventSource();
      final routed = RoutedIssueEventSource(
        sources: {
          IssueTrackerEventSourceKind.ghPolling: polling,
          IssueTrackerEventSourceKind.teaPolling: polling,
          IssueTrackerEventSourceKind.ghWebhookForward: webhookForward,
        },
      );

      // And a project that uses gh/webhook-forward with startup-only reconciliation.
      final project = _project(
        eventSource: IssueTrackerEventSourceKind.ghWebhookForward,
        reconciliation: IssueTrackerReconciliationKind.startupOnly,
      );

      // When the routed event source starts in long-running mode.
      await routed.run(projects: [project], onBatch: (_) async {});

      // Then the polling source runs once for startup reconciliation.
      expect(polling.runOnceProjects, ['sample']);

      // And only the channel source stays registered for long-running execution.
      expect(polling.runProjects, isEmpty);
      expect(webhookForward.runProjects, ['sample']);
    });

    /// ```gherkin
    /// Scenario: Keep continuous reconciliation polling active for channel sources
    ///   Given a routed event source with fake polling and channel handlers
    ///   And a project that uses gh/webhook-forward with continuous reconciliation
    ///   When the routed event source starts in long-running mode
    ///   Then the polling source runs once for startup reconciliation
    ///   And the polling source also stays registered for background recovery
    /// ```
    test(
      'Keep continuous reconciliation polling active for channel sources',
      () async {
        // Given a routed event source with fake polling and channel handlers.
        final polling = _RecordingIssueEventSource();
        final webhookForward = _RecordingIssueEventSource();
        final routed = RoutedIssueEventSource(
          sources: {
            IssueTrackerEventSourceKind.ghPolling: polling,
            IssueTrackerEventSourceKind.teaPolling: polling,
            IssueTrackerEventSourceKind.ghWebhookForward: webhookForward,
          },
        );

        // And a project that uses gh/webhook-forward with continuous reconciliation.
        final project = _project(
          eventSource: IssueTrackerEventSourceKind.ghWebhookForward,
          reconciliation: IssueTrackerReconciliationKind.continuous,
        );

        // When the routed event source starts in long-running mode.
        await routed.run(projects: [project], onBatch: (_) async {});

        // Then the polling source runs once for startup reconciliation.
        expect(polling.runOnceProjects, ['sample']);

        // And the polling source also stays registered for background recovery.
        expect(polling.runProjects, ['sample']);
        expect(webhookForward.runProjects, ['sample']);
      },
    );
  });
}

class _RecordingIssueEventSource implements IssueEventSource {
  final List<String> runProjects = <String>[];
  final List<String> runOnceProjects = <String>[];

  @override
  Future<void> run({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) async {
    runProjects.addAll(projects.map((project) => project.key));
  }

  @override
  Future<void> runOnce({
    required List<ProjectConfig> projects,
    required IssueEventBatchHandler onBatch,
  }) async {
    runOnceProjects.addAll(projects.map((project) => project.key));
  }

  @override
  Future<void> close() async {}
}

ProjectConfig _project({
  required IssueTrackerEventSourceKind eventSource,
  required IssueTrackerReconciliationKind reconciliation,
}) {
  return ProjectConfig(
    key: 'sample',
    provider: IssueTrackerProvider.github,
    scm: const ScmConfig(provider: ScmProvider.github),
    repo: 'owner/sample',
    repoSlug: RepositorySlug('owner', 'sample'),
    path: '/tmp/sample',
    defaultBranch: 'main',
    sessionPrefix: 'sam',
    issueAssistant: IssueAssistantConfig(
      enabled: true,
      eventSource: ChannelIssueEventSourceConfig(
        type: eventSource,
        reconciliation: reconciliation,
        reconcileInterval: const Duration(seconds: 30),
      ),
      maxConcurrentIssues: 3,
      mentionTriggers: const ['@helper'],
      prompt: defaultIssueAssistantPrompt,
      responders: const <CliResponderConfig>[],
      capabilities: {AssistantCapability.planning},
      notifications: const <NotificationConfig>[],
      commentTag: 'code-work-spawner',
      commentPrefixTemplate: defaultCommentPrefixTemplate,
      commentFooterTemplate: defaultCommentFooterTemplate,
    ),
  );
}
