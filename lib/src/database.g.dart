// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProjectStatesTable extends ProjectStates
    with TableInfo<$ProjectStatesTable, ProjectState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _projectKeyMeta = const VerificationMeta(
    'projectKey',
  );
  @override
  late final GeneratedColumn<String> projectKey = GeneratedColumn<String>(
    'project_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repoMeta = const VerificationMeta('repo');
  @override
  late final GeneratedColumn<String> repo = GeneratedColumn<String>(
    'repo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenUpdatedAtMeta = const VerificationMeta(
    'lastSeenUpdatedAt',
  );
  @override
  late final GeneratedColumn<String> lastSeenUpdatedAt =
      GeneratedColumn<String>(
        'last_seen_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    projectKey,
    repo,
    lastSeenUpdatedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('project_key')) {
      context.handle(
        _projectKeyMeta,
        projectKey.isAcceptableOrUnknown(data['project_key']!, _projectKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_projectKeyMeta);
    }
    if (data.containsKey('repo')) {
      context.handle(
        _repoMeta,
        repo.isAcceptableOrUnknown(data['repo']!, _repoMeta),
      );
    } else if (isInserting) {
      context.missing(_repoMeta);
    }
    if (data.containsKey('last_seen_updated_at')) {
      context.handle(
        _lastSeenUpdatedAtMeta,
        lastSeenUpdatedAt.isAcceptableOrUnknown(
          data['last_seen_updated_at']!,
          _lastSeenUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {projectKey};
  @override
  ProjectState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectState(
      projectKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_key'],
      )!,
      repo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repo'],
      )!,
      lastSeenUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_seen_updated_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProjectStatesTable createAlias(String alias) {
    return $ProjectStatesTable(attachedDatabase, alias);
  }
}

class ProjectState extends DataClass implements Insertable<ProjectState> {
  final String projectKey;
  final String repo;
  final String? lastSeenUpdatedAt;
  final String updatedAt;
  const ProjectState({
    required this.projectKey,
    required this.repo,
    this.lastSeenUpdatedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['project_key'] = Variable<String>(projectKey);
    map['repo'] = Variable<String>(repo);
    if (!nullToAbsent || lastSeenUpdatedAt != null) {
      map['last_seen_updated_at'] = Variable<String>(lastSeenUpdatedAt);
    }
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  ProjectStatesCompanion toCompanion(bool nullToAbsent) {
    return ProjectStatesCompanion(
      projectKey: Value(projectKey),
      repo: Value(repo),
      lastSeenUpdatedAt: lastSeenUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenUpdatedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProjectState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectState(
      projectKey: serializer.fromJson<String>(json['projectKey']),
      repo: serializer.fromJson<String>(json['repo']),
      lastSeenUpdatedAt: serializer.fromJson<String?>(
        json['lastSeenUpdatedAt'],
      ),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'projectKey': serializer.toJson<String>(projectKey),
      'repo': serializer.toJson<String>(repo),
      'lastSeenUpdatedAt': serializer.toJson<String?>(lastSeenUpdatedAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  ProjectState copyWith({
    String? projectKey,
    String? repo,
    Value<String?> lastSeenUpdatedAt = const Value.absent(),
    String? updatedAt,
  }) => ProjectState(
    projectKey: projectKey ?? this.projectKey,
    repo: repo ?? this.repo,
    lastSeenUpdatedAt: lastSeenUpdatedAt.present
        ? lastSeenUpdatedAt.value
        : this.lastSeenUpdatedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProjectState copyWithCompanion(ProjectStatesCompanion data) {
    return ProjectState(
      projectKey: data.projectKey.present
          ? data.projectKey.value
          : this.projectKey,
      repo: data.repo.present ? data.repo.value : this.repo,
      lastSeenUpdatedAt: data.lastSeenUpdatedAt.present
          ? data.lastSeenUpdatedAt.value
          : this.lastSeenUpdatedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectState(')
          ..write('projectKey: $projectKey, ')
          ..write('repo: $repo, ')
          ..write('lastSeenUpdatedAt: $lastSeenUpdatedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(projectKey, repo, lastSeenUpdatedAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectState &&
          other.projectKey == this.projectKey &&
          other.repo == this.repo &&
          other.lastSeenUpdatedAt == this.lastSeenUpdatedAt &&
          other.updatedAt == this.updatedAt);
}

class ProjectStatesCompanion extends UpdateCompanion<ProjectState> {
  final Value<String> projectKey;
  final Value<String> repo;
  final Value<String?> lastSeenUpdatedAt;
  final Value<String> updatedAt;
  final Value<int> rowid;
  const ProjectStatesCompanion({
    this.projectKey = const Value.absent(),
    this.repo = const Value.absent(),
    this.lastSeenUpdatedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectStatesCompanion.insert({
    required String projectKey,
    required String repo,
    this.lastSeenUpdatedAt = const Value.absent(),
    required String updatedAt,
    this.rowid = const Value.absent(),
  }) : projectKey = Value(projectKey),
       repo = Value(repo),
       updatedAt = Value(updatedAt);
  static Insertable<ProjectState> custom({
    Expression<String>? projectKey,
    Expression<String>? repo,
    Expression<String>? lastSeenUpdatedAt,
    Expression<String>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (projectKey != null) 'project_key': projectKey,
      if (repo != null) 'repo': repo,
      if (lastSeenUpdatedAt != null) 'last_seen_updated_at': lastSeenUpdatedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectStatesCompanion copyWith({
    Value<String>? projectKey,
    Value<String>? repo,
    Value<String?>? lastSeenUpdatedAt,
    Value<String>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProjectStatesCompanion(
      projectKey: projectKey ?? this.projectKey,
      repo: repo ?? this.repo,
      lastSeenUpdatedAt: lastSeenUpdatedAt ?? this.lastSeenUpdatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (projectKey.present) {
      map['project_key'] = Variable<String>(projectKey.value);
    }
    if (repo.present) {
      map['repo'] = Variable<String>(repo.value);
    }
    if (lastSeenUpdatedAt.present) {
      map['last_seen_updated_at'] = Variable<String>(lastSeenUpdatedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectStatesCompanion(')
          ..write('projectKey: $projectKey, ')
          ..write('repo: $repo, ')
          ..write('lastSeenUpdatedAt: $lastSeenUpdatedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IssueThreadStatesTable extends IssueThreadStates
    with TableInfo<$IssueThreadStatesTable, IssueThreadState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IssueThreadStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _projectKeyMeta = const VerificationMeta(
    'projectKey',
  );
  @override
  late final GeneratedColumn<String> projectKey = GeneratedColumn<String>(
    'project_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _issueNumberMeta = const VerificationMeta(
    'issueNumber',
  );
  @override
  late final GeneratedColumn<int> issueNumber = GeneratedColumn<int>(
    'issue_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastEvaluatedFingerprintMeta =
      const VerificationMeta('lastEvaluatedFingerprint');
  @override
  late final GeneratedColumn<String> lastEvaluatedFingerprint =
      GeneratedColumn<String>(
        'last_evaluated_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastDecisionMeta = const VerificationMeta(
    'lastDecision',
  );
  @override
  late final GeneratedColumn<String> lastDecision = GeneratedColumn<String>(
    'last_decision',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCommentIdMeta = const VerificationMeta(
    'lastCommentId',
  );
  @override
  late final GeneratedColumn<int> lastCommentId = GeneratedColumn<int>(
    'last_comment_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCommentUrlMeta = const VerificationMeta(
    'lastCommentUrl',
  );
  @override
  late final GeneratedColumn<String> lastCommentUrl = GeneratedColumn<String>(
    'last_comment_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectKey,
    issueNumber,
    fingerprint,
    lastEvaluatedFingerprint,
    lastDecision,
    lastCommentId,
    lastCommentUrl,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'issue_thread_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<IssueThreadState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('project_key')) {
      context.handle(
        _projectKeyMeta,
        projectKey.isAcceptableOrUnknown(data['project_key']!, _projectKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_projectKeyMeta);
    }
    if (data.containsKey('issue_number')) {
      context.handle(
        _issueNumberMeta,
        issueNumber.isAcceptableOrUnknown(
          data['issue_number']!,
          _issueNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_issueNumberMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('last_evaluated_fingerprint')) {
      context.handle(
        _lastEvaluatedFingerprintMeta,
        lastEvaluatedFingerprint.isAcceptableOrUnknown(
          data['last_evaluated_fingerprint']!,
          _lastEvaluatedFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('last_decision')) {
      context.handle(
        _lastDecisionMeta,
        lastDecision.isAcceptableOrUnknown(
          data['last_decision']!,
          _lastDecisionMeta,
        ),
      );
    }
    if (data.containsKey('last_comment_id')) {
      context.handle(
        _lastCommentIdMeta,
        lastCommentId.isAcceptableOrUnknown(
          data['last_comment_id']!,
          _lastCommentIdMeta,
        ),
      );
    }
    if (data.containsKey('last_comment_url')) {
      context.handle(
        _lastCommentUrlMeta,
        lastCommentUrl.isAcceptableOrUnknown(
          data['last_comment_url']!,
          _lastCommentUrlMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {projectKey, issueNumber},
  ];
  @override
  IssueThreadState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IssueThreadState(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      projectKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_key'],
      )!,
      issueNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}issue_number'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      lastEvaluatedFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_evaluated_fingerprint'],
      ),
      lastDecision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_decision'],
      ),
      lastCommentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_comment_id'],
      ),
      lastCommentUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_comment_url'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $IssueThreadStatesTable createAlias(String alias) {
    return $IssueThreadStatesTable(attachedDatabase, alias);
  }
}

class IssueThreadState extends DataClass
    implements Insertable<IssueThreadState> {
  final int id;
  final String projectKey;
  final int issueNumber;
  final String fingerprint;
  final String? lastEvaluatedFingerprint;
  final String? lastDecision;
  final int? lastCommentId;
  final String? lastCommentUrl;
  final String updatedAt;
  const IssueThreadState({
    required this.id,
    required this.projectKey,
    required this.issueNumber,
    required this.fingerprint,
    this.lastEvaluatedFingerprint,
    this.lastDecision,
    this.lastCommentId,
    this.lastCommentUrl,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['project_key'] = Variable<String>(projectKey);
    map['issue_number'] = Variable<int>(issueNumber);
    map['fingerprint'] = Variable<String>(fingerprint);
    if (!nullToAbsent || lastEvaluatedFingerprint != null) {
      map['last_evaluated_fingerprint'] = Variable<String>(
        lastEvaluatedFingerprint,
      );
    }
    if (!nullToAbsent || lastDecision != null) {
      map['last_decision'] = Variable<String>(lastDecision);
    }
    if (!nullToAbsent || lastCommentId != null) {
      map['last_comment_id'] = Variable<int>(lastCommentId);
    }
    if (!nullToAbsent || lastCommentUrl != null) {
      map['last_comment_url'] = Variable<String>(lastCommentUrl);
    }
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  IssueThreadStatesCompanion toCompanion(bool nullToAbsent) {
    return IssueThreadStatesCompanion(
      id: Value(id),
      projectKey: Value(projectKey),
      issueNumber: Value(issueNumber),
      fingerprint: Value(fingerprint),
      lastEvaluatedFingerprint: lastEvaluatedFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(lastEvaluatedFingerprint),
      lastDecision: lastDecision == null && nullToAbsent
          ? const Value.absent()
          : Value(lastDecision),
      lastCommentId: lastCommentId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCommentId),
      lastCommentUrl: lastCommentUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCommentUrl),
      updatedAt: Value(updatedAt),
    );
  }

  factory IssueThreadState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IssueThreadState(
      id: serializer.fromJson<int>(json['id']),
      projectKey: serializer.fromJson<String>(json['projectKey']),
      issueNumber: serializer.fromJson<int>(json['issueNumber']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      lastEvaluatedFingerprint: serializer.fromJson<String?>(
        json['lastEvaluatedFingerprint'],
      ),
      lastDecision: serializer.fromJson<String?>(json['lastDecision']),
      lastCommentId: serializer.fromJson<int?>(json['lastCommentId']),
      lastCommentUrl: serializer.fromJson<String?>(json['lastCommentUrl']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'projectKey': serializer.toJson<String>(projectKey),
      'issueNumber': serializer.toJson<int>(issueNumber),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'lastEvaluatedFingerprint': serializer.toJson<String?>(
        lastEvaluatedFingerprint,
      ),
      'lastDecision': serializer.toJson<String?>(lastDecision),
      'lastCommentId': serializer.toJson<int?>(lastCommentId),
      'lastCommentUrl': serializer.toJson<String?>(lastCommentUrl),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  IssueThreadState copyWith({
    int? id,
    String? projectKey,
    int? issueNumber,
    String? fingerprint,
    Value<String?> lastEvaluatedFingerprint = const Value.absent(),
    Value<String?> lastDecision = const Value.absent(),
    Value<int?> lastCommentId = const Value.absent(),
    Value<String?> lastCommentUrl = const Value.absent(),
    String? updatedAt,
  }) => IssueThreadState(
    id: id ?? this.id,
    projectKey: projectKey ?? this.projectKey,
    issueNumber: issueNumber ?? this.issueNumber,
    fingerprint: fingerprint ?? this.fingerprint,
    lastEvaluatedFingerprint: lastEvaluatedFingerprint.present
        ? lastEvaluatedFingerprint.value
        : this.lastEvaluatedFingerprint,
    lastDecision: lastDecision.present ? lastDecision.value : this.lastDecision,
    lastCommentId: lastCommentId.present
        ? lastCommentId.value
        : this.lastCommentId,
    lastCommentUrl: lastCommentUrl.present
        ? lastCommentUrl.value
        : this.lastCommentUrl,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  IssueThreadState copyWithCompanion(IssueThreadStatesCompanion data) {
    return IssueThreadState(
      id: data.id.present ? data.id.value : this.id,
      projectKey: data.projectKey.present
          ? data.projectKey.value
          : this.projectKey,
      issueNumber: data.issueNumber.present
          ? data.issueNumber.value
          : this.issueNumber,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      lastEvaluatedFingerprint: data.lastEvaluatedFingerprint.present
          ? data.lastEvaluatedFingerprint.value
          : this.lastEvaluatedFingerprint,
      lastDecision: data.lastDecision.present
          ? data.lastDecision.value
          : this.lastDecision,
      lastCommentId: data.lastCommentId.present
          ? data.lastCommentId.value
          : this.lastCommentId,
      lastCommentUrl: data.lastCommentUrl.present
          ? data.lastCommentUrl.value
          : this.lastCommentUrl,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IssueThreadState(')
          ..write('id: $id, ')
          ..write('projectKey: $projectKey, ')
          ..write('issueNumber: $issueNumber, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('lastEvaluatedFingerprint: $lastEvaluatedFingerprint, ')
          ..write('lastDecision: $lastDecision, ')
          ..write('lastCommentId: $lastCommentId, ')
          ..write('lastCommentUrl: $lastCommentUrl, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectKey,
    issueNumber,
    fingerprint,
    lastEvaluatedFingerprint,
    lastDecision,
    lastCommentId,
    lastCommentUrl,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IssueThreadState &&
          other.id == this.id &&
          other.projectKey == this.projectKey &&
          other.issueNumber == this.issueNumber &&
          other.fingerprint == this.fingerprint &&
          other.lastEvaluatedFingerprint == this.lastEvaluatedFingerprint &&
          other.lastDecision == this.lastDecision &&
          other.lastCommentId == this.lastCommentId &&
          other.lastCommentUrl == this.lastCommentUrl &&
          other.updatedAt == this.updatedAt);
}

class IssueThreadStatesCompanion extends UpdateCompanion<IssueThreadState> {
  final Value<int> id;
  final Value<String> projectKey;
  final Value<int> issueNumber;
  final Value<String> fingerprint;
  final Value<String?> lastEvaluatedFingerprint;
  final Value<String?> lastDecision;
  final Value<int?> lastCommentId;
  final Value<String?> lastCommentUrl;
  final Value<String> updatedAt;
  const IssueThreadStatesCompanion({
    this.id = const Value.absent(),
    this.projectKey = const Value.absent(),
    this.issueNumber = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.lastEvaluatedFingerprint = const Value.absent(),
    this.lastDecision = const Value.absent(),
    this.lastCommentId = const Value.absent(),
    this.lastCommentUrl = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  IssueThreadStatesCompanion.insert({
    this.id = const Value.absent(),
    required String projectKey,
    required int issueNumber,
    required String fingerprint,
    this.lastEvaluatedFingerprint = const Value.absent(),
    this.lastDecision = const Value.absent(),
    this.lastCommentId = const Value.absent(),
    this.lastCommentUrl = const Value.absent(),
    required String updatedAt,
  }) : projectKey = Value(projectKey),
       issueNumber = Value(issueNumber),
       fingerprint = Value(fingerprint),
       updatedAt = Value(updatedAt);
  static Insertable<IssueThreadState> custom({
    Expression<int>? id,
    Expression<String>? projectKey,
    Expression<int>? issueNumber,
    Expression<String>? fingerprint,
    Expression<String>? lastEvaluatedFingerprint,
    Expression<String>? lastDecision,
    Expression<int>? lastCommentId,
    Expression<String>? lastCommentUrl,
    Expression<String>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectKey != null) 'project_key': projectKey,
      if (issueNumber != null) 'issue_number': issueNumber,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (lastEvaluatedFingerprint != null)
        'last_evaluated_fingerprint': lastEvaluatedFingerprint,
      if (lastDecision != null) 'last_decision': lastDecision,
      if (lastCommentId != null) 'last_comment_id': lastCommentId,
      if (lastCommentUrl != null) 'last_comment_url': lastCommentUrl,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  IssueThreadStatesCompanion copyWith({
    Value<int>? id,
    Value<String>? projectKey,
    Value<int>? issueNumber,
    Value<String>? fingerprint,
    Value<String?>? lastEvaluatedFingerprint,
    Value<String?>? lastDecision,
    Value<int?>? lastCommentId,
    Value<String?>? lastCommentUrl,
    Value<String>? updatedAt,
  }) {
    return IssueThreadStatesCompanion(
      id: id ?? this.id,
      projectKey: projectKey ?? this.projectKey,
      issueNumber: issueNumber ?? this.issueNumber,
      fingerprint: fingerprint ?? this.fingerprint,
      lastEvaluatedFingerprint:
          lastEvaluatedFingerprint ?? this.lastEvaluatedFingerprint,
      lastDecision: lastDecision ?? this.lastDecision,
      lastCommentId: lastCommentId ?? this.lastCommentId,
      lastCommentUrl: lastCommentUrl ?? this.lastCommentUrl,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (projectKey.present) {
      map['project_key'] = Variable<String>(projectKey.value);
    }
    if (issueNumber.present) {
      map['issue_number'] = Variable<int>(issueNumber.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (lastEvaluatedFingerprint.present) {
      map['last_evaluated_fingerprint'] = Variable<String>(
        lastEvaluatedFingerprint.value,
      );
    }
    if (lastDecision.present) {
      map['last_decision'] = Variable<String>(lastDecision.value);
    }
    if (lastCommentId.present) {
      map['last_comment_id'] = Variable<int>(lastCommentId.value);
    }
    if (lastCommentUrl.present) {
      map['last_comment_url'] = Variable<String>(lastCommentUrl.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IssueThreadStatesCompanion(')
          ..write('id: $id, ')
          ..write('projectKey: $projectKey, ')
          ..write('issueNumber: $issueNumber, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('lastEvaluatedFingerprint: $lastEvaluatedFingerprint, ')
          ..write('lastDecision: $lastDecision, ')
          ..write('lastCommentId: $lastCommentId, ')
          ..write('lastCommentUrl: $lastCommentUrl, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $JobsTable extends Jobs with TableInfo<$JobsTable, Job> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _projectKeyMeta = const VerificationMeta(
    'projectKey',
  );
  @override
  late final GeneratedColumn<String> projectKey = GeneratedColumn<String>(
    'project_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _issueNumberMeta = const VerificationMeta(
    'issueNumber',
  );
  @override
  late final GeneratedColumn<int> issueNumber = GeneratedColumn<int>(
    'issue_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _triggerMeta = const VerificationMeta(
    'trigger',
  );
  @override
  late final GeneratedColumn<String> trigger = GeneratedColumn<String>(
    'trigger',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectKey,
    issueNumber,
    fingerprint,
    trigger,
    status,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Job> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('project_key')) {
      context.handle(
        _projectKeyMeta,
        projectKey.isAcceptableOrUnknown(data['project_key']!, _projectKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_projectKeyMeta);
    }
    if (data.containsKey('issue_number')) {
      context.handle(
        _issueNumberMeta,
        issueNumber.isAcceptableOrUnknown(
          data['issue_number']!,
          _issueNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_issueNumberMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('trigger')) {
      context.handle(
        _triggerMeta,
        trigger.isAcceptableOrUnknown(data['trigger']!, _triggerMeta),
      );
    } else if (isInserting) {
      context.missing(_triggerMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Job map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Job(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      projectKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_key'],
      )!,
      issueNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}issue_number'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      trigger: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $JobsTable createAlias(String alias) {
    return $JobsTable(attachedDatabase, alias);
  }
}

class Job extends DataClass implements Insertable<Job> {
  final int id;
  final String projectKey;
  final int issueNumber;
  final String fingerprint;
  final String trigger;
  final String status;
  final String createdAt;
  final String updatedAt;
  const Job({
    required this.id,
    required this.projectKey,
    required this.issueNumber,
    required this.fingerprint,
    required this.trigger,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['project_key'] = Variable<String>(projectKey);
    map['issue_number'] = Variable<int>(issueNumber);
    map['fingerprint'] = Variable<String>(fingerprint);
    map['trigger'] = Variable<String>(trigger);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<String>(createdAt);
    map['updated_at'] = Variable<String>(updatedAt);
    return map;
  }

  JobsCompanion toCompanion(bool nullToAbsent) {
    return JobsCompanion(
      id: Value(id),
      projectKey: Value(projectKey),
      issueNumber: Value(issueNumber),
      fingerprint: Value(fingerprint),
      trigger: Value(trigger),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Job.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Job(
      id: serializer.fromJson<int>(json['id']),
      projectKey: serializer.fromJson<String>(json['projectKey']),
      issueNumber: serializer.fromJson<int>(json['issueNumber']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      trigger: serializer.fromJson<String>(json['trigger']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'projectKey': serializer.toJson<String>(projectKey),
      'issueNumber': serializer.toJson<int>(issueNumber),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'trigger': serializer.toJson<String>(trigger),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<String>(createdAt),
      'updatedAt': serializer.toJson<String>(updatedAt),
    };
  }

  Job copyWith({
    int? id,
    String? projectKey,
    int? issueNumber,
    String? fingerprint,
    String? trigger,
    String? status,
    String? createdAt,
    String? updatedAt,
  }) => Job(
    id: id ?? this.id,
    projectKey: projectKey ?? this.projectKey,
    issueNumber: issueNumber ?? this.issueNumber,
    fingerprint: fingerprint ?? this.fingerprint,
    trigger: trigger ?? this.trigger,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Job copyWithCompanion(JobsCompanion data) {
    return Job(
      id: data.id.present ? data.id.value : this.id,
      projectKey: data.projectKey.present
          ? data.projectKey.value
          : this.projectKey,
      issueNumber: data.issueNumber.present
          ? data.issueNumber.value
          : this.issueNumber,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      trigger: data.trigger.present ? data.trigger.value : this.trigger,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Job(')
          ..write('id: $id, ')
          ..write('projectKey: $projectKey, ')
          ..write('issueNumber: $issueNumber, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('trigger: $trigger, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectKey,
    issueNumber,
    fingerprint,
    trigger,
    status,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Job &&
          other.id == this.id &&
          other.projectKey == this.projectKey &&
          other.issueNumber == this.issueNumber &&
          other.fingerprint == this.fingerprint &&
          other.trigger == this.trigger &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class JobsCompanion extends UpdateCompanion<Job> {
  final Value<int> id;
  final Value<String> projectKey;
  final Value<int> issueNumber;
  final Value<String> fingerprint;
  final Value<String> trigger;
  final Value<String> status;
  final Value<String> createdAt;
  final Value<String> updatedAt;
  const JobsCompanion({
    this.id = const Value.absent(),
    this.projectKey = const Value.absent(),
    this.issueNumber = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.trigger = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  JobsCompanion.insert({
    this.id = const Value.absent(),
    required String projectKey,
    required int issueNumber,
    required String fingerprint,
    required String trigger,
    required String status,
    required String createdAt,
    required String updatedAt,
  }) : projectKey = Value(projectKey),
       issueNumber = Value(issueNumber),
       fingerprint = Value(fingerprint),
       trigger = Value(trigger),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Job> custom({
    Expression<int>? id,
    Expression<String>? projectKey,
    Expression<int>? issueNumber,
    Expression<String>? fingerprint,
    Expression<String>? trigger,
    Expression<String>? status,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectKey != null) 'project_key': projectKey,
      if (issueNumber != null) 'issue_number': issueNumber,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (trigger != null) 'trigger': trigger,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  JobsCompanion copyWith({
    Value<int>? id,
    Value<String>? projectKey,
    Value<int>? issueNumber,
    Value<String>? fingerprint,
    Value<String>? trigger,
    Value<String>? status,
    Value<String>? createdAt,
    Value<String>? updatedAt,
  }) {
    return JobsCompanion(
      id: id ?? this.id,
      projectKey: projectKey ?? this.projectKey,
      issueNumber: issueNumber ?? this.issueNumber,
      fingerprint: fingerprint ?? this.fingerprint,
      trigger: trigger ?? this.trigger,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (projectKey.present) {
      map['project_key'] = Variable<String>(projectKey.value);
    }
    if (issueNumber.present) {
      map['issue_number'] = Variable<int>(issueNumber.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (trigger.present) {
      map['trigger'] = Variable<String>(trigger.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JobsCompanion(')
          ..write('id: $id, ')
          ..write('projectKey: $projectKey, ')
          ..write('issueNumber: $issueNumber, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('trigger: $trigger, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ExecutionRunsTable extends ExecutionRuns
    with TableInfo<$ExecutionRunsTable, ExecutionRun> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExecutionRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<int> jobId = GeneratedColumn<int>(
    'job_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _responderIdMeta = const VerificationMeta(
    'responderId',
  );
  @override
  late final GeneratedColumn<String> responderId = GeneratedColumn<String>(
    'responder_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decisionMeta = const VerificationMeta(
    'decision',
  );
  @override
  late final GeneratedColumn<String> decision = GeneratedColumn<String>(
    'decision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _successMeta = const VerificationMeta(
    'success',
  );
  @override
  late final GeneratedColumn<bool> success = GeneratedColumn<bool>(
    'success',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("success" IN (0, 1))',
    ),
  );
  static const VerificationMeta _workspacePathMeta = const VerificationMeta(
    'workspacePath',
  );
  @override
  late final GeneratedColumn<String> workspacePath = GeneratedColumn<String>(
    'workspace_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stdoutMeta = const VerificationMeta('stdout');
  @override
  late final GeneratedColumn<String> stdout = GeneratedColumn<String>(
    'stdout',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stderrMeta = const VerificationMeta('stderr');
  @override
  late final GeneratedColumn<String> stderr = GeneratedColumn<String>(
    'stderr',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    jobId,
    responderId,
    mode,
    decision,
    success,
    workspacePath,
    stdout,
    stderr,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'execution_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExecutionRun> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('responder_id')) {
      context.handle(
        _responderIdMeta,
        responderId.isAcceptableOrUnknown(
          data['responder_id']!,
          _responderIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_responderIdMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('decision')) {
      context.handle(
        _decisionMeta,
        decision.isAcceptableOrUnknown(data['decision']!, _decisionMeta),
      );
    } else if (isInserting) {
      context.missing(_decisionMeta);
    }
    if (data.containsKey('success')) {
      context.handle(
        _successMeta,
        success.isAcceptableOrUnknown(data['success']!, _successMeta),
      );
    } else if (isInserting) {
      context.missing(_successMeta);
    }
    if (data.containsKey('workspace_path')) {
      context.handle(
        _workspacePathMeta,
        workspacePath.isAcceptableOrUnknown(
          data['workspace_path']!,
          _workspacePathMeta,
        ),
      );
    }
    if (data.containsKey('stdout')) {
      context.handle(
        _stdoutMeta,
        stdout.isAcceptableOrUnknown(data['stdout']!, _stdoutMeta),
      );
    } else if (isInserting) {
      context.missing(_stdoutMeta);
    }
    if (data.containsKey('stderr')) {
      context.handle(
        _stderrMeta,
        stderr.isAcceptableOrUnknown(data['stderr']!, _stderrMeta),
      );
    } else if (isInserting) {
      context.missing(_stderrMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExecutionRun map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExecutionRun(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}job_id'],
      )!,
      responderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}responder_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      decision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decision'],
      )!,
      success: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}success'],
      )!,
      workspacePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_path'],
      ),
      stdout: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stdout'],
      )!,
      stderr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stderr'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ExecutionRunsTable createAlias(String alias) {
    return $ExecutionRunsTable(attachedDatabase, alias);
  }
}

class ExecutionRun extends DataClass implements Insertable<ExecutionRun> {
  final int id;
  final int jobId;
  final String responderId;
  final String mode;
  final String decision;
  final bool success;
  final String? workspacePath;
  final String stdout;
  final String stderr;
  final String createdAt;
  const ExecutionRun({
    required this.id,
    required this.jobId,
    required this.responderId,
    required this.mode,
    required this.decision,
    required this.success,
    this.workspacePath,
    required this.stdout,
    required this.stderr,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['job_id'] = Variable<int>(jobId);
    map['responder_id'] = Variable<String>(responderId);
    map['mode'] = Variable<String>(mode);
    map['decision'] = Variable<String>(decision);
    map['success'] = Variable<bool>(success);
    if (!nullToAbsent || workspacePath != null) {
      map['workspace_path'] = Variable<String>(workspacePath);
    }
    map['stdout'] = Variable<String>(stdout);
    map['stderr'] = Variable<String>(stderr);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  ExecutionRunsCompanion toCompanion(bool nullToAbsent) {
    return ExecutionRunsCompanion(
      id: Value(id),
      jobId: Value(jobId),
      responderId: Value(responderId),
      mode: Value(mode),
      decision: Value(decision),
      success: Value(success),
      workspacePath: workspacePath == null && nullToAbsent
          ? const Value.absent()
          : Value(workspacePath),
      stdout: Value(stdout),
      stderr: Value(stderr),
      createdAt: Value(createdAt),
    );
  }

  factory ExecutionRun.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExecutionRun(
      id: serializer.fromJson<int>(json['id']),
      jobId: serializer.fromJson<int>(json['jobId']),
      responderId: serializer.fromJson<String>(json['responderId']),
      mode: serializer.fromJson<String>(json['mode']),
      decision: serializer.fromJson<String>(json['decision']),
      success: serializer.fromJson<bool>(json['success']),
      workspacePath: serializer.fromJson<String?>(json['workspacePath']),
      stdout: serializer.fromJson<String>(json['stdout']),
      stderr: serializer.fromJson<String>(json['stderr']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'jobId': serializer.toJson<int>(jobId),
      'responderId': serializer.toJson<String>(responderId),
      'mode': serializer.toJson<String>(mode),
      'decision': serializer.toJson<String>(decision),
      'success': serializer.toJson<bool>(success),
      'workspacePath': serializer.toJson<String?>(workspacePath),
      'stdout': serializer.toJson<String>(stdout),
      'stderr': serializer.toJson<String>(stderr),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  ExecutionRun copyWith({
    int? id,
    int? jobId,
    String? responderId,
    String? mode,
    String? decision,
    bool? success,
    Value<String?> workspacePath = const Value.absent(),
    String? stdout,
    String? stderr,
    String? createdAt,
  }) => ExecutionRun(
    id: id ?? this.id,
    jobId: jobId ?? this.jobId,
    responderId: responderId ?? this.responderId,
    mode: mode ?? this.mode,
    decision: decision ?? this.decision,
    success: success ?? this.success,
    workspacePath: workspacePath.present
        ? workspacePath.value
        : this.workspacePath,
    stdout: stdout ?? this.stdout,
    stderr: stderr ?? this.stderr,
    createdAt: createdAt ?? this.createdAt,
  );
  ExecutionRun copyWithCompanion(ExecutionRunsCompanion data) {
    return ExecutionRun(
      id: data.id.present ? data.id.value : this.id,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      responderId: data.responderId.present
          ? data.responderId.value
          : this.responderId,
      mode: data.mode.present ? data.mode.value : this.mode,
      decision: data.decision.present ? data.decision.value : this.decision,
      success: data.success.present ? data.success.value : this.success,
      workspacePath: data.workspacePath.present
          ? data.workspacePath.value
          : this.workspacePath,
      stdout: data.stdout.present ? data.stdout.value : this.stdout,
      stderr: data.stderr.present ? data.stderr.value : this.stderr,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExecutionRun(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('responderId: $responderId, ')
          ..write('mode: $mode, ')
          ..write('decision: $decision, ')
          ..write('success: $success, ')
          ..write('workspacePath: $workspacePath, ')
          ..write('stdout: $stdout, ')
          ..write('stderr: $stderr, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    jobId,
    responderId,
    mode,
    decision,
    success,
    workspacePath,
    stdout,
    stderr,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExecutionRun &&
          other.id == this.id &&
          other.jobId == this.jobId &&
          other.responderId == this.responderId &&
          other.mode == this.mode &&
          other.decision == this.decision &&
          other.success == this.success &&
          other.workspacePath == this.workspacePath &&
          other.stdout == this.stdout &&
          other.stderr == this.stderr &&
          other.createdAt == this.createdAt);
}

class ExecutionRunsCompanion extends UpdateCompanion<ExecutionRun> {
  final Value<int> id;
  final Value<int> jobId;
  final Value<String> responderId;
  final Value<String> mode;
  final Value<String> decision;
  final Value<bool> success;
  final Value<String?> workspacePath;
  final Value<String> stdout;
  final Value<String> stderr;
  final Value<String> createdAt;
  const ExecutionRunsCompanion({
    this.id = const Value.absent(),
    this.jobId = const Value.absent(),
    this.responderId = const Value.absent(),
    this.mode = const Value.absent(),
    this.decision = const Value.absent(),
    this.success = const Value.absent(),
    this.workspacePath = const Value.absent(),
    this.stdout = const Value.absent(),
    this.stderr = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ExecutionRunsCompanion.insert({
    this.id = const Value.absent(),
    required int jobId,
    required String responderId,
    required String mode,
    required String decision,
    required bool success,
    this.workspacePath = const Value.absent(),
    required String stdout,
    required String stderr,
    required String createdAt,
  }) : jobId = Value(jobId),
       responderId = Value(responderId),
       mode = Value(mode),
       decision = Value(decision),
       success = Value(success),
       stdout = Value(stdout),
       stderr = Value(stderr),
       createdAt = Value(createdAt);
  static Insertable<ExecutionRun> custom({
    Expression<int>? id,
    Expression<int>? jobId,
    Expression<String>? responderId,
    Expression<String>? mode,
    Expression<String>? decision,
    Expression<bool>? success,
    Expression<String>? workspacePath,
    Expression<String>? stdout,
    Expression<String>? stderr,
    Expression<String>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (jobId != null) 'job_id': jobId,
      if (responderId != null) 'responder_id': responderId,
      if (mode != null) 'mode': mode,
      if (decision != null) 'decision': decision,
      if (success != null) 'success': success,
      if (workspacePath != null) 'workspace_path': workspacePath,
      if (stdout != null) 'stdout': stdout,
      if (stderr != null) 'stderr': stderr,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ExecutionRunsCompanion copyWith({
    Value<int>? id,
    Value<int>? jobId,
    Value<String>? responderId,
    Value<String>? mode,
    Value<String>? decision,
    Value<bool>? success,
    Value<String?>? workspacePath,
    Value<String>? stdout,
    Value<String>? stderr,
    Value<String>? createdAt,
  }) {
    return ExecutionRunsCompanion(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      responderId: responderId ?? this.responderId,
      mode: mode ?? this.mode,
      decision: decision ?? this.decision,
      success: success ?? this.success,
      workspacePath: workspacePath ?? this.workspacePath,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<int>(jobId.value);
    }
    if (responderId.present) {
      map['responder_id'] = Variable<String>(responderId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (decision.present) {
      map['decision'] = Variable<String>(decision.value);
    }
    if (success.present) {
      map['success'] = Variable<bool>(success.value);
    }
    if (workspacePath.present) {
      map['workspace_path'] = Variable<String>(workspacePath.value);
    }
    if (stdout.present) {
      map['stdout'] = Variable<String>(stdout.value);
    }
    if (stderr.present) {
      map['stderr'] = Variable<String>(stderr.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExecutionRunsCompanion(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('responderId: $responderId, ')
          ..write('mode: $mode, ')
          ..write('decision: $decision, ')
          ..write('success: $success, ')
          ..write('workspacePath: $workspacePath, ')
          ..write('stdout: $stdout, ')
          ..write('stderr: $stderr, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CommentsTable extends Comments with TableInfo<$CommentsTable, Comment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CommentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _projectKeyMeta = const VerificationMeta(
    'projectKey',
  );
  @override
  late final GeneratedColumn<String> projectKey = GeneratedColumn<String>(
    'project_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _issueNumberMeta = const VerificationMeta(
    'issueNumber',
  );
  @override
  late final GeneratedColumn<int> issueNumber = GeneratedColumn<int>(
    'issue_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _githubCommentIdMeta = const VerificationMeta(
    'githubCommentId',
  );
  @override
  late final GeneratedColumn<int> githubCommentId = GeneratedColumn<int>(
    'github_comment_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _githubCommentUrlMeta = const VerificationMeta(
    'githubCommentUrl',
  );
  @override
  late final GeneratedColumn<String> githubCommentUrl = GeneratedColumn<String>(
    'github_comment_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectKey,
    issueNumber,
    fingerprint,
    githubCommentId,
    githubCommentUrl,
    body,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'comments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Comment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('project_key')) {
      context.handle(
        _projectKeyMeta,
        projectKey.isAcceptableOrUnknown(data['project_key']!, _projectKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_projectKeyMeta);
    }
    if (data.containsKey('issue_number')) {
      context.handle(
        _issueNumberMeta,
        issueNumber.isAcceptableOrUnknown(
          data['issue_number']!,
          _issueNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_issueNumberMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('github_comment_id')) {
      context.handle(
        _githubCommentIdMeta,
        githubCommentId.isAcceptableOrUnknown(
          data['github_comment_id']!,
          _githubCommentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_githubCommentIdMeta);
    }
    if (data.containsKey('github_comment_url')) {
      context.handle(
        _githubCommentUrlMeta,
        githubCommentUrl.isAcceptableOrUnknown(
          data['github_comment_url']!,
          _githubCommentUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_githubCommentUrlMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Comment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Comment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      projectKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_key'],
      )!,
      issueNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}issue_number'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      githubCommentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}github_comment_id'],
      )!,
      githubCommentUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}github_comment_url'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CommentsTable createAlias(String alias) {
    return $CommentsTable(attachedDatabase, alias);
  }
}

class Comment extends DataClass implements Insertable<Comment> {
  final int id;
  final String projectKey;
  final int issueNumber;
  final String fingerprint;
  final int githubCommentId;
  final String githubCommentUrl;
  final String body;
  final String createdAt;
  const Comment({
    required this.id,
    required this.projectKey,
    required this.issueNumber,
    required this.fingerprint,
    required this.githubCommentId,
    required this.githubCommentUrl,
    required this.body,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['project_key'] = Variable<String>(projectKey);
    map['issue_number'] = Variable<int>(issueNumber);
    map['fingerprint'] = Variable<String>(fingerprint);
    map['github_comment_id'] = Variable<int>(githubCommentId);
    map['github_comment_url'] = Variable<String>(githubCommentUrl);
    map['body'] = Variable<String>(body);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  CommentsCompanion toCompanion(bool nullToAbsent) {
    return CommentsCompanion(
      id: Value(id),
      projectKey: Value(projectKey),
      issueNumber: Value(issueNumber),
      fingerprint: Value(fingerprint),
      githubCommentId: Value(githubCommentId),
      githubCommentUrl: Value(githubCommentUrl),
      body: Value(body),
      createdAt: Value(createdAt),
    );
  }

  factory Comment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Comment(
      id: serializer.fromJson<int>(json['id']),
      projectKey: serializer.fromJson<String>(json['projectKey']),
      issueNumber: serializer.fromJson<int>(json['issueNumber']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      githubCommentId: serializer.fromJson<int>(json['githubCommentId']),
      githubCommentUrl: serializer.fromJson<String>(json['githubCommentUrl']),
      body: serializer.fromJson<String>(json['body']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'projectKey': serializer.toJson<String>(projectKey),
      'issueNumber': serializer.toJson<int>(issueNumber),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'githubCommentId': serializer.toJson<int>(githubCommentId),
      'githubCommentUrl': serializer.toJson<String>(githubCommentUrl),
      'body': serializer.toJson<String>(body),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  Comment copyWith({
    int? id,
    String? projectKey,
    int? issueNumber,
    String? fingerprint,
    int? githubCommentId,
    String? githubCommentUrl,
    String? body,
    String? createdAt,
  }) => Comment(
    id: id ?? this.id,
    projectKey: projectKey ?? this.projectKey,
    issueNumber: issueNumber ?? this.issueNumber,
    fingerprint: fingerprint ?? this.fingerprint,
    githubCommentId: githubCommentId ?? this.githubCommentId,
    githubCommentUrl: githubCommentUrl ?? this.githubCommentUrl,
    body: body ?? this.body,
    createdAt: createdAt ?? this.createdAt,
  );
  Comment copyWithCompanion(CommentsCompanion data) {
    return Comment(
      id: data.id.present ? data.id.value : this.id,
      projectKey: data.projectKey.present
          ? data.projectKey.value
          : this.projectKey,
      issueNumber: data.issueNumber.present
          ? data.issueNumber.value
          : this.issueNumber,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      githubCommentId: data.githubCommentId.present
          ? data.githubCommentId.value
          : this.githubCommentId,
      githubCommentUrl: data.githubCommentUrl.present
          ? data.githubCommentUrl.value
          : this.githubCommentUrl,
      body: data.body.present ? data.body.value : this.body,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Comment(')
          ..write('id: $id, ')
          ..write('projectKey: $projectKey, ')
          ..write('issueNumber: $issueNumber, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('githubCommentId: $githubCommentId, ')
          ..write('githubCommentUrl: $githubCommentUrl, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectKey,
    issueNumber,
    fingerprint,
    githubCommentId,
    githubCommentUrl,
    body,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Comment &&
          other.id == this.id &&
          other.projectKey == this.projectKey &&
          other.issueNumber == this.issueNumber &&
          other.fingerprint == this.fingerprint &&
          other.githubCommentId == this.githubCommentId &&
          other.githubCommentUrl == this.githubCommentUrl &&
          other.body == this.body &&
          other.createdAt == this.createdAt);
}

class CommentsCompanion extends UpdateCompanion<Comment> {
  final Value<int> id;
  final Value<String> projectKey;
  final Value<int> issueNumber;
  final Value<String> fingerprint;
  final Value<int> githubCommentId;
  final Value<String> githubCommentUrl;
  final Value<String> body;
  final Value<String> createdAt;
  const CommentsCompanion({
    this.id = const Value.absent(),
    this.projectKey = const Value.absent(),
    this.issueNumber = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.githubCommentId = const Value.absent(),
    this.githubCommentUrl = const Value.absent(),
    this.body = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CommentsCompanion.insert({
    this.id = const Value.absent(),
    required String projectKey,
    required int issueNumber,
    required String fingerprint,
    required int githubCommentId,
    required String githubCommentUrl,
    required String body,
    required String createdAt,
  }) : projectKey = Value(projectKey),
       issueNumber = Value(issueNumber),
       fingerprint = Value(fingerprint),
       githubCommentId = Value(githubCommentId),
       githubCommentUrl = Value(githubCommentUrl),
       body = Value(body),
       createdAt = Value(createdAt);
  static Insertable<Comment> custom({
    Expression<int>? id,
    Expression<String>? projectKey,
    Expression<int>? issueNumber,
    Expression<String>? fingerprint,
    Expression<int>? githubCommentId,
    Expression<String>? githubCommentUrl,
    Expression<String>? body,
    Expression<String>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectKey != null) 'project_key': projectKey,
      if (issueNumber != null) 'issue_number': issueNumber,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (githubCommentId != null) 'github_comment_id': githubCommentId,
      if (githubCommentUrl != null) 'github_comment_url': githubCommentUrl,
      if (body != null) 'body': body,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CommentsCompanion copyWith({
    Value<int>? id,
    Value<String>? projectKey,
    Value<int>? issueNumber,
    Value<String>? fingerprint,
    Value<int>? githubCommentId,
    Value<String>? githubCommentUrl,
    Value<String>? body,
    Value<String>? createdAt,
  }) {
    return CommentsCompanion(
      id: id ?? this.id,
      projectKey: projectKey ?? this.projectKey,
      issueNumber: issueNumber ?? this.issueNumber,
      fingerprint: fingerprint ?? this.fingerprint,
      githubCommentId: githubCommentId ?? this.githubCommentId,
      githubCommentUrl: githubCommentUrl ?? this.githubCommentUrl,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (projectKey.present) {
      map['project_key'] = Variable<String>(projectKey.value);
    }
    if (issueNumber.present) {
      map['issue_number'] = Variable<int>(issueNumber.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (githubCommentId.present) {
      map['github_comment_id'] = Variable<int>(githubCommentId.value);
    }
    if (githubCommentUrl.present) {
      map['github_comment_url'] = Variable<String>(githubCommentUrl.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CommentsCompanion(')
          ..write('id: $id, ')
          ..write('projectKey: $projectKey, ')
          ..write('issueNumber: $issueNumber, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('githubCommentId: $githubCommentId, ')
          ..write('githubCommentUrl: $githubCommentUrl, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $PollRunsTable extends PollRuns with TableInfo<$PollRunsTable, PollRun> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PollRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _projectKeyMeta = const VerificationMeta(
    'projectKey',
  );
  @override
  late final GeneratedColumn<String> projectKey = GeneratedColumn<String>(
    'project_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<String> startedAt = GeneratedColumn<String>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<String> finishedAt = GeneratedColumn<String>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _successMeta = const VerificationMeta(
    'success',
  );
  @override
  late final GeneratedColumn<bool> success = GeneratedColumn<bool>(
    'success',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("success" IN (0, 1))',
    ),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectKey,
    startedAt,
    finishedAt,
    success,
    error,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'poll_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<PollRun> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('project_key')) {
      context.handle(
        _projectKeyMeta,
        projectKey.isAcceptableOrUnknown(data['project_key']!, _projectKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_projectKeyMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    if (data.containsKey('success')) {
      context.handle(
        _successMeta,
        success.isAcceptableOrUnknown(data['success']!, _successMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PollRun map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PollRun(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      projectKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_key'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}started_at'],
      )!,
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}finished_at'],
      ),
      success: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}success'],
      ),
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
    );
  }

  @override
  $PollRunsTable createAlias(String alias) {
    return $PollRunsTable(attachedDatabase, alias);
  }
}

class PollRun extends DataClass implements Insertable<PollRun> {
  final int id;
  final String projectKey;
  final String startedAt;
  final String? finishedAt;
  final bool? success;
  final String? error;
  const PollRun({
    required this.id,
    required this.projectKey,
    required this.startedAt,
    this.finishedAt,
    this.success,
    this.error,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['project_key'] = Variable<String>(projectKey);
    map['started_at'] = Variable<String>(startedAt);
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<String>(finishedAt);
    }
    if (!nullToAbsent || success != null) {
      map['success'] = Variable<bool>(success);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    return map;
  }

  PollRunsCompanion toCompanion(bool nullToAbsent) {
    return PollRunsCompanion(
      id: Value(id),
      projectKey: Value(projectKey),
      startedAt: Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
      success: success == null && nullToAbsent
          ? const Value.absent()
          : Value(success),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
    );
  }

  factory PollRun.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PollRun(
      id: serializer.fromJson<int>(json['id']),
      projectKey: serializer.fromJson<String>(json['projectKey']),
      startedAt: serializer.fromJson<String>(json['startedAt']),
      finishedAt: serializer.fromJson<String?>(json['finishedAt']),
      success: serializer.fromJson<bool?>(json['success']),
      error: serializer.fromJson<String?>(json['error']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'projectKey': serializer.toJson<String>(projectKey),
      'startedAt': serializer.toJson<String>(startedAt),
      'finishedAt': serializer.toJson<String?>(finishedAt),
      'success': serializer.toJson<bool?>(success),
      'error': serializer.toJson<String?>(error),
    };
  }

  PollRun copyWith({
    int? id,
    String? projectKey,
    String? startedAt,
    Value<String?> finishedAt = const Value.absent(),
    Value<bool?> success = const Value.absent(),
    Value<String?> error = const Value.absent(),
  }) => PollRun(
    id: id ?? this.id,
    projectKey: projectKey ?? this.projectKey,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
    success: success.present ? success.value : this.success,
    error: error.present ? error.value : this.error,
  );
  PollRun copyWithCompanion(PollRunsCompanion data) {
    return PollRun(
      id: data.id.present ? data.id.value : this.id,
      projectKey: data.projectKey.present
          ? data.projectKey.value
          : this.projectKey,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      success: data.success.present ? data.success.value : this.success,
      error: data.error.present ? data.error.value : this.error,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PollRun(')
          ..write('id: $id, ')
          ..write('projectKey: $projectKey, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('success: $success, ')
          ..write('error: $error')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, projectKey, startedAt, finishedAt, success, error);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PollRun &&
          other.id == this.id &&
          other.projectKey == this.projectKey &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt &&
          other.success == this.success &&
          other.error == this.error);
}

class PollRunsCompanion extends UpdateCompanion<PollRun> {
  final Value<int> id;
  final Value<String> projectKey;
  final Value<String> startedAt;
  final Value<String?> finishedAt;
  final Value<bool?> success;
  final Value<String?> error;
  const PollRunsCompanion({
    this.id = const Value.absent(),
    this.projectKey = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.success = const Value.absent(),
    this.error = const Value.absent(),
  });
  PollRunsCompanion.insert({
    this.id = const Value.absent(),
    required String projectKey,
    required String startedAt,
    this.finishedAt = const Value.absent(),
    this.success = const Value.absent(),
    this.error = const Value.absent(),
  }) : projectKey = Value(projectKey),
       startedAt = Value(startedAt);
  static Insertable<PollRun> custom({
    Expression<int>? id,
    Expression<String>? projectKey,
    Expression<String>? startedAt,
    Expression<String>? finishedAt,
    Expression<bool>? success,
    Expression<String>? error,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectKey != null) 'project_key': projectKey,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (success != null) 'success': success,
      if (error != null) 'error': error,
    });
  }

  PollRunsCompanion copyWith({
    Value<int>? id,
    Value<String>? projectKey,
    Value<String>? startedAt,
    Value<String?>? finishedAt,
    Value<bool?>? success,
    Value<String?>? error,
  }) {
    return PollRunsCompanion(
      id: id ?? this.id,
      projectKey: projectKey ?? this.projectKey,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      success: success ?? this.success,
      error: error ?? this.error,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (projectKey.present) {
      map['project_key'] = Variable<String>(projectKey.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<String>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<String>(finishedAt.value);
    }
    if (success.present) {
      map['success'] = Variable<bool>(success.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PollRunsCompanion(')
          ..write('id: $id, ')
          ..write('projectKey: $projectKey, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('success: $success, ')
          ..write('error: $error')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProjectStatesTable projectStates = $ProjectStatesTable(this);
  late final $IssueThreadStatesTable issueThreadStates =
      $IssueThreadStatesTable(this);
  late final $JobsTable jobs = $JobsTable(this);
  late final $ExecutionRunsTable executionRuns = $ExecutionRunsTable(this);
  late final $CommentsTable comments = $CommentsTable(this);
  late final $PollRunsTable pollRuns = $PollRunsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    projectStates,
    issueThreadStates,
    jobs,
    executionRuns,
    comments,
    pollRuns,
  ];
}

typedef $$ProjectStatesTableCreateCompanionBuilder =
    ProjectStatesCompanion Function({
      required String projectKey,
      required String repo,
      Value<String?> lastSeenUpdatedAt,
      required String updatedAt,
      Value<int> rowid,
    });
typedef $$ProjectStatesTableUpdateCompanionBuilder =
    ProjectStatesCompanion Function({
      Value<String> projectKey,
      Value<String> repo,
      Value<String?> lastSeenUpdatedAt,
      Value<String> updatedAt,
      Value<int> rowid,
    });

class $$ProjectStatesTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectStatesTable> {
  $$ProjectStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repo => $composableBuilder(
    column: $table.repo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSeenUpdatedAt => $composableBuilder(
    column: $table.lastSeenUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectStatesTable> {
  $$ProjectStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repo => $composableBuilder(
    column: $table.repo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSeenUpdatedAt => $composableBuilder(
    column: $table.lastSeenUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectStatesTable> {
  $$ProjectStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get repo =>
      $composableBuilder(column: $table.repo, builder: (column) => column);

  GeneratedColumn<String> get lastSeenUpdatedAt => $composableBuilder(
    column: $table.lastSeenUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProjectStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectStatesTable,
          ProjectState,
          $$ProjectStatesTableFilterComposer,
          $$ProjectStatesTableOrderingComposer,
          $$ProjectStatesTableAnnotationComposer,
          $$ProjectStatesTableCreateCompanionBuilder,
          $$ProjectStatesTableUpdateCompanionBuilder,
          (
            ProjectState,
            BaseReferences<_$AppDatabase, $ProjectStatesTable, ProjectState>,
          ),
          ProjectState,
          PrefetchHooks Function()
        > {
  $$ProjectStatesTableTableManager(_$AppDatabase db, $ProjectStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> projectKey = const Value.absent(),
                Value<String> repo = const Value.absent(),
                Value<String?> lastSeenUpdatedAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectStatesCompanion(
                projectKey: projectKey,
                repo: repo,
                lastSeenUpdatedAt: lastSeenUpdatedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String projectKey,
                required String repo,
                Value<String?> lastSeenUpdatedAt = const Value.absent(),
                required String updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProjectStatesCompanion.insert(
                projectKey: projectKey,
                repo: repo,
                lastSeenUpdatedAt: lastSeenUpdatedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProjectStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectStatesTable,
      ProjectState,
      $$ProjectStatesTableFilterComposer,
      $$ProjectStatesTableOrderingComposer,
      $$ProjectStatesTableAnnotationComposer,
      $$ProjectStatesTableCreateCompanionBuilder,
      $$ProjectStatesTableUpdateCompanionBuilder,
      (
        ProjectState,
        BaseReferences<_$AppDatabase, $ProjectStatesTable, ProjectState>,
      ),
      ProjectState,
      PrefetchHooks Function()
    >;
typedef $$IssueThreadStatesTableCreateCompanionBuilder =
    IssueThreadStatesCompanion Function({
      Value<int> id,
      required String projectKey,
      required int issueNumber,
      required String fingerprint,
      Value<String?> lastEvaluatedFingerprint,
      Value<String?> lastDecision,
      Value<int?> lastCommentId,
      Value<String?> lastCommentUrl,
      required String updatedAt,
    });
typedef $$IssueThreadStatesTableUpdateCompanionBuilder =
    IssueThreadStatesCompanion Function({
      Value<int> id,
      Value<String> projectKey,
      Value<int> issueNumber,
      Value<String> fingerprint,
      Value<String?> lastEvaluatedFingerprint,
      Value<String?> lastDecision,
      Value<int?> lastCommentId,
      Value<String?> lastCommentUrl,
      Value<String> updatedAt,
    });

class $$IssueThreadStatesTableFilterComposer
    extends Composer<_$AppDatabase, $IssueThreadStatesTable> {
  $$IssueThreadStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get issueNumber => $composableBuilder(
    column: $table.issueNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastEvaluatedFingerprint => $composableBuilder(
    column: $table.lastEvaluatedFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastDecision => $composableBuilder(
    column: $table.lastDecision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastCommentId => $composableBuilder(
    column: $table.lastCommentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCommentUrl => $composableBuilder(
    column: $table.lastCommentUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$IssueThreadStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $IssueThreadStatesTable> {
  $$IssueThreadStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get issueNumber => $composableBuilder(
    column: $table.issueNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastEvaluatedFingerprint => $composableBuilder(
    column: $table.lastEvaluatedFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastDecision => $composableBuilder(
    column: $table.lastDecision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCommentId => $composableBuilder(
    column: $table.lastCommentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCommentUrl => $composableBuilder(
    column: $table.lastCommentUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IssueThreadStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $IssueThreadStatesTable> {
  $$IssueThreadStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get issueNumber => $composableBuilder(
    column: $table.issueNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastEvaluatedFingerprint => $composableBuilder(
    column: $table.lastEvaluatedFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastDecision => $composableBuilder(
    column: $table.lastDecision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastCommentId => $composableBuilder(
    column: $table.lastCommentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastCommentUrl => $composableBuilder(
    column: $table.lastCommentUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$IssueThreadStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IssueThreadStatesTable,
          IssueThreadState,
          $$IssueThreadStatesTableFilterComposer,
          $$IssueThreadStatesTableOrderingComposer,
          $$IssueThreadStatesTableAnnotationComposer,
          $$IssueThreadStatesTableCreateCompanionBuilder,
          $$IssueThreadStatesTableUpdateCompanionBuilder,
          (
            IssueThreadState,
            BaseReferences<
              _$AppDatabase,
              $IssueThreadStatesTable,
              IssueThreadState
            >,
          ),
          IssueThreadState,
          PrefetchHooks Function()
        > {
  $$IssueThreadStatesTableTableManager(
    _$AppDatabase db,
    $IssueThreadStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IssueThreadStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IssueThreadStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IssueThreadStatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> projectKey = const Value.absent(),
                Value<int> issueNumber = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<String?> lastEvaluatedFingerprint = const Value.absent(),
                Value<String?> lastDecision = const Value.absent(),
                Value<int?> lastCommentId = const Value.absent(),
                Value<String?> lastCommentUrl = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
              }) => IssueThreadStatesCompanion(
                id: id,
                projectKey: projectKey,
                issueNumber: issueNumber,
                fingerprint: fingerprint,
                lastEvaluatedFingerprint: lastEvaluatedFingerprint,
                lastDecision: lastDecision,
                lastCommentId: lastCommentId,
                lastCommentUrl: lastCommentUrl,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String projectKey,
                required int issueNumber,
                required String fingerprint,
                Value<String?> lastEvaluatedFingerprint = const Value.absent(),
                Value<String?> lastDecision = const Value.absent(),
                Value<int?> lastCommentId = const Value.absent(),
                Value<String?> lastCommentUrl = const Value.absent(),
                required String updatedAt,
              }) => IssueThreadStatesCompanion.insert(
                id: id,
                projectKey: projectKey,
                issueNumber: issueNumber,
                fingerprint: fingerprint,
                lastEvaluatedFingerprint: lastEvaluatedFingerprint,
                lastDecision: lastDecision,
                lastCommentId: lastCommentId,
                lastCommentUrl: lastCommentUrl,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IssueThreadStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IssueThreadStatesTable,
      IssueThreadState,
      $$IssueThreadStatesTableFilterComposer,
      $$IssueThreadStatesTableOrderingComposer,
      $$IssueThreadStatesTableAnnotationComposer,
      $$IssueThreadStatesTableCreateCompanionBuilder,
      $$IssueThreadStatesTableUpdateCompanionBuilder,
      (
        IssueThreadState,
        BaseReferences<
          _$AppDatabase,
          $IssueThreadStatesTable,
          IssueThreadState
        >,
      ),
      IssueThreadState,
      PrefetchHooks Function()
    >;
typedef $$JobsTableCreateCompanionBuilder =
    JobsCompanion Function({
      Value<int> id,
      required String projectKey,
      required int issueNumber,
      required String fingerprint,
      required String trigger,
      required String status,
      required String createdAt,
      required String updatedAt,
    });
typedef $$JobsTableUpdateCompanionBuilder =
    JobsCompanion Function({
      Value<int> id,
      Value<String> projectKey,
      Value<int> issueNumber,
      Value<String> fingerprint,
      Value<String> trigger,
      Value<String> status,
      Value<String> createdAt,
      Value<String> updatedAt,
    });

class $$JobsTableFilterComposer extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get issueNumber => $composableBuilder(
    column: $table.issueNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trigger => $composableBuilder(
    column: $table.trigger,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$JobsTableOrderingComposer extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get issueNumber => $composableBuilder(
    column: $table.issueNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trigger => $composableBuilder(
    column: $table.trigger,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$JobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get issueNumber => $composableBuilder(
    column: $table.issueNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get trigger =>
      $composableBuilder(column: $table.trigger, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$JobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $JobsTable,
          Job,
          $$JobsTableFilterComposer,
          $$JobsTableOrderingComposer,
          $$JobsTableAnnotationComposer,
          $$JobsTableCreateCompanionBuilder,
          $$JobsTableUpdateCompanionBuilder,
          (Job, BaseReferences<_$AppDatabase, $JobsTable, Job>),
          Job,
          PrefetchHooks Function()
        > {
  $$JobsTableTableManager(_$AppDatabase db, $JobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> projectKey = const Value.absent(),
                Value<int> issueNumber = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<String> trigger = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
              }) => JobsCompanion(
                id: id,
                projectKey: projectKey,
                issueNumber: issueNumber,
                fingerprint: fingerprint,
                trigger: trigger,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String projectKey,
                required int issueNumber,
                required String fingerprint,
                required String trigger,
                required String status,
                required String createdAt,
                required String updatedAt,
              }) => JobsCompanion.insert(
                id: id,
                projectKey: projectKey,
                issueNumber: issueNumber,
                fingerprint: fingerprint,
                trigger: trigger,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$JobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $JobsTable,
      Job,
      $$JobsTableFilterComposer,
      $$JobsTableOrderingComposer,
      $$JobsTableAnnotationComposer,
      $$JobsTableCreateCompanionBuilder,
      $$JobsTableUpdateCompanionBuilder,
      (Job, BaseReferences<_$AppDatabase, $JobsTable, Job>),
      Job,
      PrefetchHooks Function()
    >;
typedef $$ExecutionRunsTableCreateCompanionBuilder =
    ExecutionRunsCompanion Function({
      Value<int> id,
      required int jobId,
      required String responderId,
      required String mode,
      required String decision,
      required bool success,
      Value<String?> workspacePath,
      required String stdout,
      required String stderr,
      required String createdAt,
    });
typedef $$ExecutionRunsTableUpdateCompanionBuilder =
    ExecutionRunsCompanion Function({
      Value<int> id,
      Value<int> jobId,
      Value<String> responderId,
      Value<String> mode,
      Value<String> decision,
      Value<bool> success,
      Value<String?> workspacePath,
      Value<String> stdout,
      Value<String> stderr,
      Value<String> createdAt,
    });

class $$ExecutionRunsTableFilterComposer
    extends Composer<_$AppDatabase, $ExecutionRunsTable> {
  $$ExecutionRunsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get responderId => $composableBuilder(
    column: $table.responderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get decision => $composableBuilder(
    column: $table.decision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get success => $composableBuilder(
    column: $table.success,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspacePath => $composableBuilder(
    column: $table.workspacePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stdout => $composableBuilder(
    column: $table.stdout,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stderr => $composableBuilder(
    column: $table.stderr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExecutionRunsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExecutionRunsTable> {
  $$ExecutionRunsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get jobId => $composableBuilder(
    column: $table.jobId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get responderId => $composableBuilder(
    column: $table.responderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get decision => $composableBuilder(
    column: $table.decision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get success => $composableBuilder(
    column: $table.success,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspacePath => $composableBuilder(
    column: $table.workspacePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stdout => $composableBuilder(
    column: $table.stdout,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stderr => $composableBuilder(
    column: $table.stderr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExecutionRunsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExecutionRunsTable> {
  $$ExecutionRunsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get jobId =>
      $composableBuilder(column: $table.jobId, builder: (column) => column);

  GeneratedColumn<String> get responderId => $composableBuilder(
    column: $table.responderId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get decision =>
      $composableBuilder(column: $table.decision, builder: (column) => column);

  GeneratedColumn<bool> get success =>
      $composableBuilder(column: $table.success, builder: (column) => column);

  GeneratedColumn<String> get workspacePath => $composableBuilder(
    column: $table.workspacePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stdout =>
      $composableBuilder(column: $table.stdout, builder: (column) => column);

  GeneratedColumn<String> get stderr =>
      $composableBuilder(column: $table.stderr, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ExecutionRunsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExecutionRunsTable,
          ExecutionRun,
          $$ExecutionRunsTableFilterComposer,
          $$ExecutionRunsTableOrderingComposer,
          $$ExecutionRunsTableAnnotationComposer,
          $$ExecutionRunsTableCreateCompanionBuilder,
          $$ExecutionRunsTableUpdateCompanionBuilder,
          (
            ExecutionRun,
            BaseReferences<_$AppDatabase, $ExecutionRunsTable, ExecutionRun>,
          ),
          ExecutionRun,
          PrefetchHooks Function()
        > {
  $$ExecutionRunsTableTableManager(_$AppDatabase db, $ExecutionRunsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExecutionRunsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExecutionRunsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExecutionRunsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> jobId = const Value.absent(),
                Value<String> responderId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String> decision = const Value.absent(),
                Value<bool> success = const Value.absent(),
                Value<String?> workspacePath = const Value.absent(),
                Value<String> stdout = const Value.absent(),
                Value<String> stderr = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
              }) => ExecutionRunsCompanion(
                id: id,
                jobId: jobId,
                responderId: responderId,
                mode: mode,
                decision: decision,
                success: success,
                workspacePath: workspacePath,
                stdout: stdout,
                stderr: stderr,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int jobId,
                required String responderId,
                required String mode,
                required String decision,
                required bool success,
                Value<String?> workspacePath = const Value.absent(),
                required String stdout,
                required String stderr,
                required String createdAt,
              }) => ExecutionRunsCompanion.insert(
                id: id,
                jobId: jobId,
                responderId: responderId,
                mode: mode,
                decision: decision,
                success: success,
                workspacePath: workspacePath,
                stdout: stdout,
                stderr: stderr,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExecutionRunsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExecutionRunsTable,
      ExecutionRun,
      $$ExecutionRunsTableFilterComposer,
      $$ExecutionRunsTableOrderingComposer,
      $$ExecutionRunsTableAnnotationComposer,
      $$ExecutionRunsTableCreateCompanionBuilder,
      $$ExecutionRunsTableUpdateCompanionBuilder,
      (
        ExecutionRun,
        BaseReferences<_$AppDatabase, $ExecutionRunsTable, ExecutionRun>,
      ),
      ExecutionRun,
      PrefetchHooks Function()
    >;
typedef $$CommentsTableCreateCompanionBuilder =
    CommentsCompanion Function({
      Value<int> id,
      required String projectKey,
      required int issueNumber,
      required String fingerprint,
      required int githubCommentId,
      required String githubCommentUrl,
      required String body,
      required String createdAt,
    });
typedef $$CommentsTableUpdateCompanionBuilder =
    CommentsCompanion Function({
      Value<int> id,
      Value<String> projectKey,
      Value<int> issueNumber,
      Value<String> fingerprint,
      Value<int> githubCommentId,
      Value<String> githubCommentUrl,
      Value<String> body,
      Value<String> createdAt,
    });

class $$CommentsTableFilterComposer
    extends Composer<_$AppDatabase, $CommentsTable> {
  $$CommentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get issueNumber => $composableBuilder(
    column: $table.issueNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get githubCommentId => $composableBuilder(
    column: $table.githubCommentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get githubCommentUrl => $composableBuilder(
    column: $table.githubCommentUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CommentsTableOrderingComposer
    extends Composer<_$AppDatabase, $CommentsTable> {
  $$CommentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get issueNumber => $composableBuilder(
    column: $table.issueNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get githubCommentId => $composableBuilder(
    column: $table.githubCommentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get githubCommentUrl => $composableBuilder(
    column: $table.githubCommentUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CommentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CommentsTable> {
  $$CommentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get issueNumber => $composableBuilder(
    column: $table.issueNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get githubCommentId => $composableBuilder(
    column: $table.githubCommentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get githubCommentUrl => $composableBuilder(
    column: $table.githubCommentUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CommentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CommentsTable,
          Comment,
          $$CommentsTableFilterComposer,
          $$CommentsTableOrderingComposer,
          $$CommentsTableAnnotationComposer,
          $$CommentsTableCreateCompanionBuilder,
          $$CommentsTableUpdateCompanionBuilder,
          (Comment, BaseReferences<_$AppDatabase, $CommentsTable, Comment>),
          Comment,
          PrefetchHooks Function()
        > {
  $$CommentsTableTableManager(_$AppDatabase db, $CommentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CommentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CommentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CommentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> projectKey = const Value.absent(),
                Value<int> issueNumber = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<int> githubCommentId = const Value.absent(),
                Value<String> githubCommentUrl = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> createdAt = const Value.absent(),
              }) => CommentsCompanion(
                id: id,
                projectKey: projectKey,
                issueNumber: issueNumber,
                fingerprint: fingerprint,
                githubCommentId: githubCommentId,
                githubCommentUrl: githubCommentUrl,
                body: body,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String projectKey,
                required int issueNumber,
                required String fingerprint,
                required int githubCommentId,
                required String githubCommentUrl,
                required String body,
                required String createdAt,
              }) => CommentsCompanion.insert(
                id: id,
                projectKey: projectKey,
                issueNumber: issueNumber,
                fingerprint: fingerprint,
                githubCommentId: githubCommentId,
                githubCommentUrl: githubCommentUrl,
                body: body,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CommentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CommentsTable,
      Comment,
      $$CommentsTableFilterComposer,
      $$CommentsTableOrderingComposer,
      $$CommentsTableAnnotationComposer,
      $$CommentsTableCreateCompanionBuilder,
      $$CommentsTableUpdateCompanionBuilder,
      (Comment, BaseReferences<_$AppDatabase, $CommentsTable, Comment>),
      Comment,
      PrefetchHooks Function()
    >;
typedef $$PollRunsTableCreateCompanionBuilder =
    PollRunsCompanion Function({
      Value<int> id,
      required String projectKey,
      required String startedAt,
      Value<String?> finishedAt,
      Value<bool?> success,
      Value<String?> error,
    });
typedef $$PollRunsTableUpdateCompanionBuilder =
    PollRunsCompanion Function({
      Value<int> id,
      Value<String> projectKey,
      Value<String> startedAt,
      Value<String?> finishedAt,
      Value<bool?> success,
      Value<String?> error,
    });

class $$PollRunsTableFilterComposer
    extends Composer<_$AppDatabase, $PollRunsTable> {
  $$PollRunsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get success => $composableBuilder(
    column: $table.success,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PollRunsTableOrderingComposer
    extends Composer<_$AppDatabase, $PollRunsTable> {
  $$PollRunsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get success => $composableBuilder(
    column: $table.success,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PollRunsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PollRunsTable> {
  $$PollRunsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get projectKey => $composableBuilder(
    column: $table.projectKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<String> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get success =>
      $composableBuilder(column: $table.success, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);
}

class $$PollRunsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PollRunsTable,
          PollRun,
          $$PollRunsTableFilterComposer,
          $$PollRunsTableOrderingComposer,
          $$PollRunsTableAnnotationComposer,
          $$PollRunsTableCreateCompanionBuilder,
          $$PollRunsTableUpdateCompanionBuilder,
          (PollRun, BaseReferences<_$AppDatabase, $PollRunsTable, PollRun>),
          PollRun,
          PrefetchHooks Function()
        > {
  $$PollRunsTableTableManager(_$AppDatabase db, $PollRunsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PollRunsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PollRunsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PollRunsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> projectKey = const Value.absent(),
                Value<String> startedAt = const Value.absent(),
                Value<String?> finishedAt = const Value.absent(),
                Value<bool?> success = const Value.absent(),
                Value<String?> error = const Value.absent(),
              }) => PollRunsCompanion(
                id: id,
                projectKey: projectKey,
                startedAt: startedAt,
                finishedAt: finishedAt,
                success: success,
                error: error,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String projectKey,
                required String startedAt,
                Value<String?> finishedAt = const Value.absent(),
                Value<bool?> success = const Value.absent(),
                Value<String?> error = const Value.absent(),
              }) => PollRunsCompanion.insert(
                id: id,
                projectKey: projectKey,
                startedAt: startedAt,
                finishedAt: finishedAt,
                success: success,
                error: error,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PollRunsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PollRunsTable,
      PollRun,
      $$PollRunsTableFilterComposer,
      $$PollRunsTableOrderingComposer,
      $$PollRunsTableAnnotationComposer,
      $$PollRunsTableCreateCompanionBuilder,
      $$PollRunsTableUpdateCompanionBuilder,
      (PollRun, BaseReferences<_$AppDatabase, $PollRunsTable, PollRun>),
      PollRun,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProjectStatesTableTableManager get projectStates =>
      $$ProjectStatesTableTableManager(_db, _db.projectStates);
  $$IssueThreadStatesTableTableManager get issueThreadStates =>
      $$IssueThreadStatesTableTableManager(_db, _db.issueThreadStates);
  $$JobsTableTableManager get jobs => $$JobsTableTableManager(_db, _db.jobs);
  $$ExecutionRunsTableTableManager get executionRuns =>
      $$ExecutionRunsTableTableManager(_db, _db.executionRuns);
  $$CommentsTableTableManager get comments =>
      $$CommentsTableTableManager(_db, _db.comments);
  $$PollRunsTableTableManager get pollRuns =>
      $$PollRunsTableTableManager(_db, _db.pollRuns);
}
