import 'dart:io';

import 'package:code_work_spawner/code_work_spawner.dart';
import 'package:test/test.dart';

void main() {
  /// ```gherkin
  /// Feature: Desktop notifier
  ///
  ///   As a maintainer running code_work_spawner locally
  ///   I want desktop notifications for assistant events
  ///   So that I can notice mentions and failures without watching the terminal
  /// ```
  group('DesktopNotifier', () {
    /// ```gherkin
    /// Scenario: Send a Linux desktop notification for a posted reply
    ///   Given a desktop notifier configured for Linux
    ///   When it sends a reply_posted notification
    ///   Then it invokes notify-send with a readable title and body
    /// ```
    test('Send a Linux desktop notification for a posted reply', () async {
      // Given a desktop notifier configured for Linux.
      String? capturedExecutable;
      List<String>? capturedArguments;
      final notifier = DesktopNotifier(
        NotificationConfig(
          type: NotificationType.desktop,
          enabled: true,
          events: {NotificationEvent.replyPosted},
          webhookUrl: null,
          username: null,
          avatarUrl: null,
        ),
        platform: DesktopNotificationPlatform.linux,
        commandRunner: ({required executable, required arguments}) async {
          capturedExecutable = executable;
          capturedArguments = List<String>.from(arguments);
          return ProcessResult(0, 0, '', '');
        },
      );
      const context = NotificationContext(
        projectKey: 'sample',
        repo: 'owner/sample',
        issueNumber: 61,
        issueTitle: 'Need architecture help',
        issueUrl: 'https://example.test/issues/61',
        trigger: '@helper',
        mode: 'planning',
        summary: 'posted planning advice',
      );

      // When it sends a reply_posted notification.
      await notifier.notify(
        event: NotificationEvent.replyPosted,
        context: context,
      );

      // Then it invokes notify-send with a readable title and body.
      expect(capturedExecutable, 'notify-send');
      expect(capturedArguments, hasLength(2));
      expect(capturedArguments!.first, 'code_work_spawner: Reply posted');
      expect(
        capturedArguments!.last,
        contains('sample#61 Need architecture help'),
      );
      expect(
        capturedArguments!.last,
        contains('summary: posted planning advice'),
      );
    });

    /// ```gherkin
    /// Scenario: Reject unsupported desktop platforms
    ///   Given a desktop notifier configured for an unsupported platform
    ///   When it sends a mention_detected notification
    ///   Then it throws an UnsupportedError
    /// ```
    test('Reject unsupported desktop platforms', () async {
      // Given a desktop notifier configured for an unsupported platform.
      final notifier = DesktopNotifier(
        NotificationConfig(
          type: NotificationType.desktop,
          enabled: true,
          events: {NotificationEvent.mentionDetected},
          webhookUrl: null,
          username: null,
          avatarUrl: null,
        ),
        platform: DesktopNotificationPlatform.unsupported,
      );
      const context = NotificationContext(
        projectKey: 'sample',
        repo: 'owner/sample',
        issueNumber: 61,
        issueTitle: 'Need architecture help',
        issueUrl: 'https://example.test/issues/61',
        trigger: '@helper',
      );

      // When it sends a mention_detected notification.
      final future = notifier.notify(
        event: NotificationEvent.mentionDetected,
        context: context,
      );

      // Then it throws an UnsupportedError.
      await expectLater(future, throwsA(isA<UnsupportedError>()));
    });
  });
}
