import 'dart:convert';
import 'dart:io';

import 'config.dart';

typedef NotificationLogger = void Function(String message);

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
    request.write(
      jsonEncode({
        'content': _formatDiscordMessage(event: event, context: context),
        if (config.username != null && config.username!.isNotEmpty)
          'username': config.username,
        if (config.avatarUrl != null && config.avatarUrl!.isNotEmpty)
          'avatar_url': config.avatarUrl,
      }),
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

  String _formatDiscordMessage({
    required NotificationEvent event,
    required NotificationContext context,
  }) {
    final headline = switch (event) {
      NotificationEvent.mentionDetected => 'Mention detected',
      NotificationEvent.replyPosted => 'Reply posted',
      NotificationEvent.noReply => 'No reply',
      NotificationEvent.responderFailed => 'Responder failed',
    };

    final details = <String>[
      '**$headline**',
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
}
