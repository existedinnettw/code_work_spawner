import 'dart:convert';
import 'dart:io';

import '../config/config.dart';

typedef NotificationLogger = void Function(String message);
typedef DesktopNotificationCommandRunner =
    Future<ProcessResult> Function({
      required String executable,
      required List<String> arguments,
    });

class NotificationContext {
  const NotificationContext({
    required this.projectKey,
    required this.repo,
    required this.issueNumber,
    required this.issueTitle,
    required this.issueUrl,
    required this.trigger,
    this.mode,
    this.responderId,
    this.decision,
    this.summary,
    this.errorSummary,
  });

  final String projectKey;
  final String repo;
  final int issueNumber;
  final String issueTitle;
  final String issueUrl;
  final String trigger;
  final String? mode;
  final String? responderId;
  final String? decision;
  final String? summary;
  final String? errorSummary;
}

abstract interface class Notifier {
  Future<void> notify({
    required NotificationEvent event,
    required NotificationContext context,
  });
}

enum DesktopNotificationPlatform { linux, macos, windows, unsupported }

class DesktopNotificationCommand {
  const DesktopNotificationCommand({
    required this.executable,
    required this.arguments,
  });

  final String executable;
  final List<String> arguments;
}

class NotifierRegistry {
  NotifierRegistry({required this.notifiersByEvent, required this.log});

  final Map<NotificationEvent, List<Notifier>> notifiersByEvent;
  final NotificationLogger log;

  factory NotifierRegistry.fromConfigs(
    List<NotificationConfig> configs, {
    required NotificationLogger log,
  }) {
    final notifiersByEvent = <NotificationEvent, List<Notifier>>{};
    for (final config in configs) {
      if (!config.enabled) {
        continue;
      }

      final notifier = switch (config.type) {
        NotificationType.discordWebhook => DiscordWebhookNotifier(config),
        NotificationType.desktop => DesktopNotifier(config),
      };
      for (final event in config.events) {
        notifiersByEvent.putIfAbsent(event, () => <Notifier>[]).add(notifier);
      }
    }
    return NotifierRegistry(notifiersByEvent: notifiersByEvent, log: log);
  }

  Future<void> notify({
    required NotificationEvent event,
    required NotificationContext context,
  }) async {
    final notifiers = notifiersByEvent[event];
    if (notifiers == null || notifiers.isEmpty) {
      return;
    }

    for (final notifier in notifiers) {
      try {
        await notifier.notify(event: event, context: context);
      } catch (error) {
        log('notification_failed event=${event.name} error=$error');
      }
    }
  }
}

class DiscordWebhookNotifier implements Notifier {
  DiscordWebhookNotifier(this.config, {HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final NotificationConfig config;
  final HttpClient _httpClient;

  @override
  Future<void> notify({
    required NotificationEvent event,
    required NotificationContext context,
  }) async {
    final webhookUrl = config.webhookUrl;
    if (webhookUrl == null || webhookUrl.isEmpty) {
      throw const FormatException(
        'discordWebhook notifier requires webhookUrl.',
      );
    }

    final uri = Uri.parse(webhookUrl);
    final request = await _httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.add(
      utf8.encode(
        jsonEncode({
          'content': formatDiscordNotificationMessage(
            event: event,
            context: context,
          ),
          if (config.username != null && config.username!.isNotEmpty)
            'username': config.username,
          if (config.avatarUrl != null && config.avatarUrl!.isNotEmpty)
            'avatar_url': config.avatarUrl,
        }),
      ),
    );

    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Discord webhook returned ${response.statusCode}: $responseBody',
        uri: uri,
      );
    }
  }
}

class DesktopNotifier implements Notifier {
  DesktopNotifier(
    this.config, {
    DesktopNotificationPlatform? platform,
    DesktopNotificationCommandRunner? commandRunner,
  }) : _platform = platform ?? detectDesktopNotificationPlatform(),
       _commandRunner = commandRunner ?? _runDesktopNotificationCommand;

  final NotificationConfig config;
  final DesktopNotificationPlatform _platform;
  final DesktopNotificationCommandRunner _commandRunner;

  @override
  Future<void> notify({
    required NotificationEvent event,
    required NotificationContext context,
  }) async {
    final command = _buildCommand(event: event, context: context);
    final result = await _commandRunner(
      executable: command.executable,
      arguments: command.arguments,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        command.executable,
        command.arguments,
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
  }

  DesktopNotificationCommand _buildCommand({
    required NotificationEvent event,
    required NotificationContext context,
  }) {
    final title = 'code_work_spawner: ${notificationHeadline(event)}';
    final body = formatDesktopNotificationMessage(
      event: event,
      context: context,
    );
    return switch (_platform) {
      DesktopNotificationPlatform.linux => DesktopNotificationCommand(
        executable: 'notify-send',
        arguments: [title, body],
      ),
      DesktopNotificationPlatform.macos => DesktopNotificationCommand(
        executable: 'osascript',
        arguments: [
          '-e',
          'display notification ${_appleScriptLiteral(body)} '
              'with title ${_appleScriptLiteral(title)}',
        ],
      ),
      DesktopNotificationPlatform.windows => DesktopNotificationCommand(
        executable: 'powershell',
        arguments: [
          '-NoProfile',
          '-Command',
          _buildWindowsToastCommand(title: title, body: body),
        ],
      ),
      DesktopNotificationPlatform.unsupported => throw UnsupportedError(
        'Desktop notifications are not supported on this platform.',
      ),
    };
  }
}

DesktopNotificationPlatform detectDesktopNotificationPlatform() {
  if (Platform.isLinux) {
    return DesktopNotificationPlatform.linux;
  }
  if (Platform.isMacOS) {
    return DesktopNotificationPlatform.macos;
  }
  if (Platform.isWindows) {
    return DesktopNotificationPlatform.windows;
  }
  return DesktopNotificationPlatform.unsupported;
}

Future<ProcessResult> _runDesktopNotificationCommand({
  required String executable,
  required List<String> arguments,
}) {
  return Process.run(executable, arguments);
}

String notificationHeadline(NotificationEvent event) {
  return switch (event) {
    NotificationEvent.mentionDetected => 'Mention detected',
    NotificationEvent.replyPosted => 'Reply posted',
    NotificationEvent.noReply => 'No reply',
    NotificationEvent.responderFailed => 'Responder failed',
  };
}

List<String> _notificationDetailLines(NotificationContext context) {
  return <String>[
    '${context.projectKey}#${context.issueNumber} ${context.issueTitle}',
    context.issueUrl,
    'repo: ${context.repo}',
    'trigger: ${context.trigger}',
    if (context.mode != null) 'mode: ${context.mode}',
    if (context.responderId != null) 'responder: ${context.responderId}',
    if (context.decision != null) 'decision: ${context.decision}',
    if (context.summary != null && context.summary!.isNotEmpty)
      'summary: ${context.summary}',
    if (context.errorSummary != null && context.errorSummary!.isNotEmpty)
      'error: ${context.errorSummary}',
  ];
}

String formatDesktopNotificationMessage({
  required NotificationEvent event,
  required NotificationContext context,
}) {
  return '${notificationHeadline(event)}\n${_notificationDetailLines(context).join('\n')}';
}

String formatDiscordNotificationMessage({
  required NotificationEvent event,
  required NotificationContext context,
}) {
  final details = <String>[
    '**${notificationHeadline(event)}**',
    '`${context.projectKey}#${context.issueNumber}` ${context.issueTitle}',
    context.issueUrl,
    'repo: `${context.repo}`',
    'trigger: `${context.trigger}`',
    if (context.mode != null) 'mode: `${context.mode}`',
    if (context.responderId != null) 'responder: `${context.responderId}`',
    if (context.decision != null) 'decision: `${context.decision}`',
    if (context.summary != null && context.summary!.isNotEmpty)
      'summary: ${context.summary}',
    if (context.errorSummary != null && context.errorSummary!.isNotEmpty)
      'error: ${context.errorSummary}',
  ];
  return details.join('\n');
}

String _appleScriptLiteral(String value) {
  return '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}

String _buildWindowsToastCommand({
  required String title,
  required String body,
}) {
  final escapedTitle = _escapeXmlText(title);
  final escapedBody = _escapeXmlText(body);
  return r'''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null
$template = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>''' +
      escapedTitle +
      r'''</text>
      <text>''' +
      escapedBody +
      r'''</text>
    </binding>
  </visual>
</toast>
"@
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml($template)
$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('code_work_spawner')
$notifier.Show($toast)
''';
}

String _escapeXmlText(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
