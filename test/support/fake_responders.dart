import 'dart:convert';
import 'dart:io';

import 'script_utils.dart';

Future<void> writeResponderScript(
  File responderScript,
  Map<String, Object?> response, {
  String stderr = '',
  int exitCode = 0,
}) async {
  await responderScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
${stderr.isEmpty ? '' : "printf '%s\\n' ${jsonEncode(stderr)} >&2"}
cat <<'JSON'
${jsonEncode(response)}
JSON
exit $exitCode
''');
  await makeScriptExecutable(responderScript);
}

Future<void> writeJsonlResponderScript(
  File responderScript,
  Map<String, Object?> response,
) async {
  await responderScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
cat <<'JSON'
{"type":"thread.started","thread_id":"test-thread"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":${jsonEncode(jsonEncode(response))}}}
{"type":"turn.completed"}
JSON
''');
  await makeScriptExecutable(responderScript);
}

Future<void> writeDelayedLoggingResponderScript(
  File responderScript, {
  required File eventLog,
  required Duration delay,
  required Map<String, Object?> response,
}) async {
  await responderScript.writeAsString('''#!/usr/bin/env bash
set -euo pipefail
timestamp_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}
printf 'start:%s:%s\n' "\$CWS_ISSUE_NUMBER" "\$(timestamp_ms)" >> "${bashScriptPath(eventLog.path)}"
cat >/dev/null
sleep ${delay.inSeconds}
printf 'end:%s:%s\n' "\$CWS_ISSUE_NUMBER" "\$(timestamp_ms)" >> "${bashScriptPath(eventLog.path)}"
cat <<'JSON'
${jsonEncode(response)}
JSON
''');
  await makeScriptExecutable(responderScript);
}
