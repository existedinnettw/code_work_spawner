import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:github/github.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_support.dart';

void main() {
  /// ```gherkin
  /// Feature: Issue tracker payload mapping
  ///
  ///   As a maintainer extending tracker providers
  ///   I want issue summaries to serialize and deserialize consistently
  ///   So that stored tracker state can be reused safely across provider-specific API calls
  /// ```
  group('GitHubIssueSummary.fromJson', () {
    /// ```gherkin
    /// Scenario: Preserve repository slugs for repository-backed trackers
    ///   Given a GitHub issue summary created from a repository-backed tracker payload
    ///   When the summary is serialized and read back through fromJson
    ///   Then the repository slug remains available on the deserialized summary
    ///   And requiredRepoSlug still returns the original owner and repository
    /// ```
    test('Preserve repository slugs for repository-backed trackers', () {
      // Given a GitHub issue summary created from a repository-backed tracker payload.
      final original = GitHubIssueSummary.fromRepositoryJson(
        RepositorySlug('owner', 'sample'),
        <String, dynamic>{
          'number': 12,
          'title': 'Need architecture help',
          'body': 'Please review the API layering.',
          'state': 'open',
          'html_url': 'https://example.test/issues/12',
          'updated_at': '2026-04-04T12:00:00Z',
          'user': <String, dynamic>{'login': 'reporter'},
          'labels': <Map<String, String>>[
            <String, String>{'name': 'help'},
          ],
        },
      );

      // When the summary is serialized and read back through fromJson.
      final restored = GitHubIssueSummary.fromJson(
        original.toJson().cast<String, dynamic>(),
      );

      // Then the repository slug remains available on the deserialized summary.
      expect(restored.repoSlug, isNotNull);

      // And requiredRepoSlug still returns the original owner and repository.
      expect(restored.requiredRepoSlug.owner, 'owner');
      expect(restored.requiredRepoSlug.name, 'sample');
    });

    /// ```gherkin
    /// Scenario: Preserve GitLab project paths without forcing owner/repo slugs
    ///   Given a GitLab issue summary created from a namespaced GitLab project payload
    ///   When the summary is serialized and read back through fromJson
    ///   Then the original GitLab project path remains available on the deserialized summary
    ///   And the deserialized summary does not invent a two-segment repository slug
    /// ```
    test('Preserve GitLab project paths without forcing owner/repo slugs', () {
      // Given a GitLab issue summary created from a namespaced GitLab project payload.
      final original = GitHubIssueSummary.fromGitLabJson(
        'group/subgroup/sample',
        <String, dynamic>{
          'iid': 12,
          'title': 'Need GitLab support',
          'description': 'Please add glab support.',
          'state': 'opened',
          'web_url':
              'https://gitlab.example.test/group/subgroup/sample/issues/12',
          'updated_at': '2026-04-04T12:00:00Z',
          'author': <String, dynamic>{'username': 'reporter'},
          'labels': <String>['enhancement'],
        },
      );

      // When the summary is serialized and read back through fromJson.
      final restored = GitHubIssueSummary.fromJson(
        original.toJson().cast<String, dynamic>(),
      );

      // Then the original GitLab project path remains available on the deserialized summary.
      expect(restored.trackerProject, 'group/subgroup/sample');

      // And the deserialized summary does not invent a two-segment repository slug.
      expect(restored.repoSlug, isNull);
    });
  });

  /// ```gherkin
  /// Feature: GitLab tracker client integration
  ///
  ///   As a maintainer adding GitLab issue tracking
  ///   I want the tracker client to talk to glab and normalize GitLab payloads
  ///   So that polling, thread loading, and comment posting work like the existing providers
  /// ```
  group('IssueTrackerClient GitLab', () {
    /// ```gherkin
    /// Scenario: Fetch GitLab issues, comments, and login through glab
    ///   Given a fake glab executable with one GitLab issue and one note
    ///   When the tracker client fetches updates, loads the thread, resolves the login, and posts a comment
    ///   Then the GitLab issue payload is normalized into the shared issue summary model
    ///   And GitLab note URLs fall back to the issue note anchor when the API omits a web URL
    /// ```
    test('Fetch GitLab issues, comments, and login through glab', () async {
      // Given a fake glab executable with one GitLab issue and one note.
      final sandbox = await Directory.systemTemp.createTemp('cws-glab-');
      final glabScript = File(p.join(sandbox.path, 'glab'));
      final postedBodyFile = File(p.join(sandbox.path, 'posted-body.txt'));
      await writeFakeGlabScript(
        glabScript: glabScript,
        issueListResponsesByRepo: <String, List<Map<String, Object?>>>{
          'group/subgroup/sample': <Map<String, Object?>>[
            <String, Object?>{
              'iid': 12,
              'title': 'Need GitLab support',
              'description': 'Please add glab support.',
              'state': 'opened',
              'web_url':
                  'https://gitlab.example.test/group/subgroup/sample/issues/12',
              'updated_at': '2026-04-04T12:00:00Z',
              'author': <String, Object?>{'username': 'reporter'},
              'labels': <String>['enhancement'],
            },
          ],
        },
        commentResponsesByRepo: <String, Map<int, List<Map<String, Object?>>>>{
          'group/subgroup/sample': <int, List<Map<String, Object?>>>{
            12: <Map<String, Object?>>[
              <String, Object?>{
                'id': 501,
                'body': 'Working on it.',
                'created_at': '2026-04-04T12:05:00Z',
                'updated_at': '2026-04-04T12:06:00Z',
                'author': <String, Object?>{'username': 'maintainer'},
              },
            ],
          },
        },
        postedBodyFile: postedBodyFile,
        viewerLogin: 'glab-user',
      );
      final client = IssueTrackerClient(glabCommand: glabScript.path);

      // When the tracker client fetches updates, loads the thread, resolves the login, and posts a comment.
      final issues = await client.fetchUpdatedIssuesForRepos(
        provider: IssueTrackerProvider.gitlab,
        trackerProjects: const <String>['group/subgroup/sample'],
        since: null,
      );
      final thread = await client.fetchThread(
        provider: IssueTrackerProvider.gitlab,
        trackerProject: 'group/subgroup/sample',
        issue: issues.single,
      );
      final login = await client.getAuthenticatedLogin(
        provider: IssueTrackerProvider.gitlab,
      );
      final posted = await client.createIssueComment(
        provider: IssueTrackerProvider.gitlab,
        trackerProject: 'group/subgroup/sample',
        issueNumber: 12,
        body: 'Reply from glab',
      );

      // Then the GitLab issue payload is normalized into the shared issue summary model.
      expect(client.trackerCliName(IssueTrackerProvider.gitlab), 'glab');
      expect(login, 'glab-user');
      expect(issues.single.trackerProject, 'group/subgroup/sample');
      expect(issues.single.repoSlug, isNull);
      expect(issues.single.number, 12);
      expect(issues.single.state, 'opened');
      expect(issues.single.labels, ['enhancement']);

      // And GitLab note URLs fall back to the issue note anchor when the API omits a web URL.
      expect(thread.comments.single.url, endsWith('/issues/12#note_501'));
      expect(await postedBodyFile.readAsString(), 'Reply from glab');
      expect(posted.id, 901);
      expect(posted.url, endsWith('/issues/12#note_901'));
      expect(posted.body, 'posted');
    });
  });
}
