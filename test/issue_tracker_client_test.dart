import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:github/github.dart';
import 'package:test/test.dart';

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
  });
}
