-- Codex Mobile local persistence schema
-- Version: 1
-- Ownership: backend/data layer. The MAUI frontend consumes typed services/contracts.
-- Secrets and OAuth tokens MUST NOT be stored in this database. Store secret material
-- in Android Keystore-backed secure storage and keep only opaque references here.
-- Large binaries (photos, attachments, snapshots) live as files; SQL stores paths and hashes.

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;

BEGIN IMMEDIATE;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version             INTEGER PRIMARY KEY,
    migration_name     TEXT NOT NULL,
    checksum_sha256    TEXT NOT NULL,
    applied_at_utc     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    execution_ms       INTEGER
);

CREATE TABLE IF NOT EXISTS app_metadata (
    key                 TEXT PRIMARY KEY,
    value               TEXT NOT NULL,
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS app_settings (
    setting_key         TEXT PRIMARY KEY,
    category            TEXT NOT NULL,
    value_json          TEXT NOT NULL,
    is_sensitive        INTEGER NOT NULL DEFAULT 0 CHECK (is_sensitive IN (0,1)),
    secure_reference    TEXT,
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    CHECK (is_sensitive = 0 OR secure_reference IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS workspaces (
    id                  TEXT PRIMARY KEY,
    name                TEXT NOT NULL,
    workspace_kind      TEXT NOT NULL DEFAULT 'local' CHECK (workspace_kind IN ('local','github','other')),
    root_uri            TEXT,
    display_path        TEXT,
    default_branch      TEXT,
    state               TEXT NOT NULL DEFAULT 'configured' CHECK (state IN ('configured','unavailable','archived')),
    settings_json       TEXT NOT NULL DEFAULT '{}',
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    last_opened_at_utc  TEXT
);

CREATE TABLE IF NOT EXISTS repository_accounts (
    id                  TEXT PRIMARY KEY,
    provider            TEXT NOT NULL DEFAULT 'github' CHECK (provider = 'github'),
    account_id          TEXT,
    account_login       TEXT NOT NULL,
    account_type        TEXT NOT NULL DEFAULT 'user' CHECK (account_type IN ('user','organization','installation')),
    auth_mode           TEXT NOT NULL CHECK (auth_mode IN ('user_oauth','installation_token','device_flow')),
    granted_scopes_json TEXT NOT NULL DEFAULT '[]',
    status              TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','connected','expired','revoked','error')),
    secret_reference    TEXT,
    connected_at_utc    TEXT,
    last_checked_at_utc TEXT,
    metadata_json       TEXT NOT NULL DEFAULT '{}',
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS repositories (
    id                  TEXT PRIMARY KEY,
    account_id          TEXT REFERENCES repository_accounts(id) ON DELETE SET NULL,
    provider_repo_id    TEXT,
    owner_login         TEXT NOT NULL,
    repository_name     TEXT NOT NULL,
    full_name           TEXT NOT NULL,
    default_branch      TEXT,
    visibility          TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('public','private','internal','unknown')),
    is_archived         INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0,1)),
    html_url            TEXT,
    updated_at_utc      TEXT,
    metadata_json       TEXT NOT NULL DEFAULT '{}',
    UNIQUE(account_id, provider_repo_id)
);

CREATE TABLE IF NOT EXISTS workspace_repositories (
    workspace_id        TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    repository_id       TEXT NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
    local_root_uri      TEXT,
    branch_name         TEXT,
    linked_at_utc       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    PRIMARY KEY(workspace_id, repository_id)
);

CREATE TABLE IF NOT EXISTS repository_permissions (
    id                  TEXT PRIMARY KEY,
    repository_id       TEXT NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
    permission_key      TEXT NOT NULL CHECK (permission_key IN ('metadata.read','contents.read','contents.write','pull_requests.read','pull_requests.write')),
    permission_state    TEXT NOT NULL CHECK (permission_state IN ('requested','granted','denied','revoked')),
    granted_at_utc      TEXT,
    expires_at_utc      TEXT,
    UNIQUE(repository_id, permission_key)
);

CREATE TABLE IF NOT EXISTS agent_modes (
    mode_key            TEXT PRIMARY KEY,
    provider            TEXT NOT NULL DEFAULT 'codex' CHECK (provider = 'codex'),
    display_name        TEXT NOT NULL,
    description         TEXT NOT NULL,
    availability        TEXT NOT NULL CHECK (availability IN ('active','coming_soon','retired')),
    is_optional         INTEGER NOT NULL DEFAULT 0 CHECK (is_optional IN (0,1)),
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

INSERT OR IGNORE INTO agent_modes(mode_key, provider, display_name, description, availability, is_optional)
VALUES
('codex_standard','codex','Codex padrão','Modo normal de uso do Codex.','active',0),
('aisto_specialized','codex','AiSTo','Artificial Intelligence Specialized in Tools: modo futuro para configurar uma IA especializada em um assunto usando o Codex.','coming_soon',1);

CREATE TABLE IF NOT EXISTS agents (
    id                  TEXT PRIMARY KEY,
    mode_key            TEXT NOT NULL DEFAULT 'codex_standard' REFERENCES agent_modes(mode_key),
    display_name        TEXT NOT NULL,
    description         TEXT NOT NULL DEFAULT '',
    avatar_relative_path TEXT,
    engine_provider     TEXT NOT NULL DEFAULT 'codex' CHECK (engine_provider = 'codex'),
    profile_status      TEXT NOT NULL DEFAULT 'local' CHECK (profile_status IN ('local','ready','disabled','archived')),
    configuration_json TEXT NOT NULL DEFAULT '{}',
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    last_used_at_utc    TEXT
);

CREATE TABLE IF NOT EXISTS agent_capabilities (
    id                  TEXT PRIMARY KEY,
    agent_id            TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    capability_key      TEXT NOT NULL CHECK (capability_key IN (
        'repository.read','repository.write','web.search','semantic.navigation',
        'documentation.current','architecture.rules')),
    is_enabled          INTEGER NOT NULL DEFAULT 0 CHECK (is_enabled IN (0,1)),
    execution_state     TEXT NOT NULL DEFAULT 'backend_pending' CHECK (execution_state IN ('available','backend_pending','disabled','blocked')),
    configuration_json TEXT NOT NULL DEFAULT '{}',
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(agent_id, capability_key)
);

CREATE TABLE IF NOT EXISTS agent_repository_bindings (
    agent_id            TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    repository_id       TEXT NOT NULL REFERENCES repositories(id) ON DELETE CASCADE,
    access_level        TEXT NOT NULL CHECK (access_level IN ('read','write')),
    requires_confirmation INTEGER NOT NULL DEFAULT 1 CHECK (requires_confirmation IN (0,1)),
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    PRIMARY KEY(agent_id, repository_id)
);

CREATE TABLE IF NOT EXISTS agent_plugin_bindings (
    agent_id            TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    plugin_id           TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
    is_enabled          INTEGER NOT NULL DEFAULT 0 CHECK (is_enabled IN (0,1)),
    configuration_json TEXT NOT NULL DEFAULT '{}',
    PRIMARY KEY(agent_id, plugin_id)
);

CREATE TABLE IF NOT EXISTS conversations (
    id                  TEXT PRIMARY KEY,
    agent_id            TEXT REFERENCES agents(id) ON DELETE SET NULL,
    workspace_id        TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
    provider            TEXT NOT NULL DEFAULT 'codex' CHECK (provider = 'codex'),
    title               TEXT NOT NULL DEFAULT 'Nova conversa',
    model_id            TEXT,
    reasoning_effort    TEXT,
    conversation_state  TEXT NOT NULL DEFAULT 'active' CHECK (conversation_state IN ('active','completed','interrupted','failed','archived')),
    metadata_json       TEXT NOT NULL DEFAULT '{}',
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    archived_at_utc     TEXT
);

CREATE TABLE IF NOT EXISTS codex_threads (
    id                  TEXT PRIMARY KEY,
    conversation_id     TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    codex_thread_id     TEXT NOT NULL UNIQUE,
    cwd_uri             TEXT,
    model_id            TEXT,
    thread_status       TEXT NOT NULL DEFAULT 'active' CHECK (thread_status IN ('active','closed','unknown')),
    raw_metadata_json   TEXT NOT NULL DEFAULT '{}',
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS codex_turns (
    id                  TEXT PRIMARY KEY,
    thread_record_id    TEXT NOT NULL REFERENCES codex_threads(id) ON DELETE CASCADE,
    codex_turn_id       TEXT NOT NULL UNIQUE,
    turn_number         INTEGER NOT NULL,
    model_id            TEXT,
    reasoning_effort    TEXT,
    turn_status         TEXT NOT NULL CHECK (turn_status IN ('queued','in_progress','completed','interrupted','failed','unknown')),
    usage_json          TEXT NOT NULL DEFAULT '{}',
    error_json          TEXT,
    started_at_utc      TEXT,
    completed_at_utc    TEXT,
    UNIQUE(thread_record_id, turn_number)
);

CREATE TABLE IF NOT EXISTS messages (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    public_id           TEXT NOT NULL UNIQUE,
    conversation_id     TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    turn_record_id      TEXT REFERENCES codex_turns(id) ON DELETE SET NULL,
    sequence_number     INTEGER NOT NULL,
    role                TEXT NOT NULL CHECK (role IN ('user','assistant','tool','system_notice')),
    author_label        TEXT NOT NULL,
    message_kind        TEXT NOT NULL DEFAULT 'text' CHECK (message_kind IN ('text','tool_summary','approval','status','error')),
    body_text           TEXT NOT NULL DEFAULT '',
    body_json           TEXT NOT NULL DEFAULT '{}',
    visibility          TEXT NOT NULL DEFAULT 'visible' CHECK (visibility IN ('visible','collapsed_tool_detail')),
    delivery_state      TEXT NOT NULL DEFAULT 'complete' CHECK (delivery_state IN ('streaming','complete','failed','cancelled')),
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    completed_at_utc    TEXT,
    UNIQUE(conversation_id, sequence_number)
);

CREATE TABLE IF NOT EXISTS message_parts (
    search_rowid        INTEGER PRIMARY KEY AUTOINCREMENT,
    id                  TEXT NOT NULL UNIQUE,
    message_id          INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    part_number         INTEGER NOT NULL,
    part_type           TEXT NOT NULL CHECK (part_type IN ('text','code','diff','image_ref','file_ref','tool_summary','citation')),
    text_content        TEXT,
    structured_json     TEXT NOT NULL DEFAULT '{}',
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(message_id, part_number)
);

CREATE TABLE IF NOT EXISTS attachments (
    id                  TEXT PRIMARY KEY,
    owner_kind          TEXT NOT NULL CHECK (owner_kind IN ('message','agent','workspace','tool_run')),
    owner_id            TEXT NOT NULL,
    relative_path       TEXT NOT NULL,
    file_name           TEXT NOT NULL,
    mime_type           TEXT,
    byte_size           INTEGER NOT NULL DEFAULT 0 CHECK (byte_size >= 0),
    sha256              TEXT,
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS conversation_events (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id     TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    turn_record_id      TEXT REFERENCES codex_turns(id) ON DELETE SET NULL,
    event_sequence      INTEGER NOT NULL,
    method_name         TEXT NOT NULL,
    params_json         TEXT NOT NULL DEFAULT '{}',
    is_redacted         INTEGER NOT NULL DEFAULT 1 CHECK (is_redacted IN (0,1)),
    received_at_utc     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(conversation_id, event_sequence)
);

CREATE TABLE IF NOT EXISTS tool_catalog (
    id                  TEXT PRIMARY KEY,
    tool_key            TEXT NOT NULL UNIQUE,
    provider            TEXT NOT NULL DEFAULT 'codex' CHECK (provider = 'codex'),
    display_name        TEXT NOT NULL,
    description         TEXT NOT NULL DEFAULT '',
    tool_kind           TEXT NOT NULL CHECK (tool_kind IN ('codex_builtin','mcp','github','web_search','local')),
    availability        TEXT NOT NULL DEFAULT 'backend_pending' CHECK (availability IN ('available','backend_pending','disabled','error')),
    input_schema_json   TEXT NOT NULL DEFAULT '{}',
    output_schema_json  TEXT NOT NULL DEFAULT '{}',
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS tool_runs (
    id                  TEXT PRIMARY KEY,
    conversation_id     TEXT REFERENCES conversations(id) ON DELETE SET NULL,
    turn_record_id      TEXT REFERENCES codex_turns(id) ON DELETE SET NULL,
    tool_id             TEXT REFERENCES tool_catalog(id) ON DELETE SET NULL,
    provider            TEXT NOT NULL DEFAULT 'codex' CHECK (provider = 'codex'),
    tool_name           TEXT NOT NULL,
    arguments_json      TEXT NOT NULL DEFAULT '{}',
    result_summary      TEXT,
    result_json         TEXT,
    run_status          TEXT NOT NULL CHECK (run_status IN ('queued','running','completed','failed','cancelled','awaiting_approval')),
    started_at_utc      TEXT,
    completed_at_utc    TEXT,
    error_json          TEXT
);

CREATE TABLE IF NOT EXISTS approval_requests (
    id                  TEXT PRIMARY KEY,
    conversation_id     TEXT REFERENCES conversations(id) ON DELETE SET NULL,
    turn_record_id      TEXT REFERENCES codex_turns(id) ON DELETE SET NULL,
    tool_run_id         TEXT REFERENCES tool_runs(id) ON DELETE SET NULL,
    request_kind        TEXT NOT NULL CHECK (request_kind IN ('command','file_change','network','repository_write','other')),
    summary             TEXT NOT NULL,
    details_json        TEXT NOT NULL DEFAULT '{}',
    risk_level          TEXT NOT NULL DEFAULT 'unknown' CHECK (risk_level IN ('low','medium','high','unknown')),
    approval_state      TEXT NOT NULL DEFAULT 'pending' CHECK (approval_state IN ('pending','approved','declined','cancelled','expired')),
    requested_at_utc    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    resolved_at_utc     TEXT
);

CREATE TABLE IF NOT EXISTS approval_decisions (
    id                  TEXT PRIMARY KEY,
    approval_id         TEXT NOT NULL REFERENCES approval_requests(id) ON DELETE CASCADE,
    decision            TEXT NOT NULL CHECK (decision IN ('approve_once','approve_session','decline','cancel')),
    actor               TEXT NOT NULL DEFAULT 'user',
    note                TEXT,
    decided_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS plugins (
    id                  TEXT PRIMARY KEY,
    plugin_key          TEXT NOT NULL UNIQUE,
    provider            TEXT NOT NULL DEFAULT 'codex' CHECK (provider = 'codex'),
    display_name        TEXT NOT NULL,
    description         TEXT NOT NULL DEFAULT '',
    plugin_kind         TEXT NOT NULL CHECK (plugin_kind IN ('mcp_server','github_connector','web_research','codex_extension')),
    source_uri          TEXT,
    trust_level         TEXT NOT NULL DEFAULT 'unverified' CHECK (trust_level IN ('official','verified','community','unverified')),
    availability        TEXT NOT NULL DEFAULT 'backend_pending' CHECK (availability IN ('available','backend_pending','coming_soon','disabled','error')),
    manifest_json       TEXT NOT NULL DEFAULT '{}',
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

INSERT OR IGNORE INTO plugins(
    id, plugin_key, provider, display_name, description, plugin_kind,
    trust_level, availability, manifest_json
) VALUES
('codex.app_server', 'codex_app_server', 'codex', 'Codex App Server',
 'Protocolo de conversas, sessões, eventos e aprovações do Codex.',
 'codex_extension', 'unverified', 'backend_pending',
 '{"source":"initial_catalog","installed":false}'),
('github.connector', 'github_connector', 'codex', 'GitHub',
 'Conexão futura para selecionar repositórios, ler arquivos e propor alterações revisáveis.',
 'github_connector', 'unverified', 'backend_pending',
 '{"source":"initial_catalog","installed":false}'),
('codex.web_research', 'codex_web_research', 'codex', 'Pesquisa na web',
 'Pesquisa futura de fontes e documentação usada pelo Codex.',
 'web_research', 'unverified', 'backend_pending',
 '{"source":"initial_catalog","installed":false}');

CREATE TABLE IF NOT EXISTS plugin_versions (
    id                  TEXT PRIMARY KEY,
    plugin_id           TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
    version             TEXT NOT NULL,
    manifest_sha256     TEXT,
    compatibility_json  TEXT NOT NULL DEFAULT '{}',
    released_at_utc     TEXT,
    UNIQUE(plugin_id, version)
);

CREATE TABLE IF NOT EXISTS plugin_installations (
    id                  TEXT PRIMARY KEY,
    plugin_id           TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
    version_id          TEXT REFERENCES plugin_versions(id) ON DELETE SET NULL,
    install_scope       TEXT NOT NULL DEFAULT 'device' CHECK (install_scope IN ('device','workspace','agent')),
    install_state       TEXT NOT NULL DEFAULT 'not_installed' CHECK (install_state IN ('not_installed','installed','disabled','error','removed')),
    installed_at_utc   TEXT,
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(plugin_id, install_scope)
);

CREATE TABLE IF NOT EXISTS plugin_permissions (
    id                  TEXT PRIMARY KEY,
    plugin_id           TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
    permission_key      TEXT NOT NULL,
    permission_label    TEXT NOT NULL,
    is_required         INTEGER NOT NULL DEFAULT 0 CHECK (is_required IN (0,1)),
    permission_state    TEXT NOT NULL DEFAULT 'not_granted' CHECK (permission_state IN ('not_granted','granted','denied','revoked')),
    UNIQUE(plugin_id, permission_key)
);

CREATE TABLE IF NOT EXISTS plugin_configurations (
    id                  TEXT PRIMARY KEY,
    installation_id     TEXT NOT NULL REFERENCES plugin_installations(id) ON DELETE CASCADE,
    configuration_key   TEXT NOT NULL,
    configuration_json  TEXT NOT NULL DEFAULT '{}',
    secure_reference    TEXT,
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(installation_id, configuration_key)
);

CREATE TABLE IF NOT EXISTS plugin_tools (
    plugin_id           TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
    tool_id             TEXT NOT NULL REFERENCES tool_catalog(id) ON DELETE CASCADE,
    exposed_name        TEXT NOT NULL,
    is_enabled          INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0,1)),
    PRIMARY KEY(plugin_id, tool_id)
);

CREATE TABLE IF NOT EXISTS plugin_execution_logs (
    id                  TEXT PRIMARY KEY,
    plugin_id           TEXT NOT NULL REFERENCES plugins(id) ON DELETE CASCADE,
    tool_run_id         TEXT REFERENCES tool_runs(id) ON DELETE SET NULL,
    level               TEXT NOT NULL CHECK (level IN ('debug','info','warning','error')),
    message             TEXT NOT NULL,
    details_json        TEXT NOT NULL DEFAULT '{}',
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS documentation_sources (
    id                  TEXT PRIMARY KEY,
    source_key          TEXT NOT NULL UNIQUE,
    publisher           TEXT NOT NULL,
    product_name        TEXT NOT NULL,
    canonical_url       TEXT NOT NULL,
    documentation_kind  TEXT NOT NULL DEFAULT 'official' CHECK (documentation_kind IN ('official','reference','repository','release_notes')),
    product_version     TEXT,
    preferred_locale    TEXT NOT NULL DEFAULT 'en',
    source_priority     INTEGER NOT NULL DEFAULT 100,
    is_enabled          INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0,1)),
    latest_checksum     TEXT,
    etag                TEXT,
    last_checked_at_utc TEXT,
    last_updated_at_utc TEXT,
    freshness_state     TEXT NOT NULL DEFAULT 'not_checked' CHECK (freshness_state IN ('fresh','stale','not_checked','unavailable')),
    metadata_json       TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS documentation_snapshots (
    id                  TEXT PRIMARY KEY,
    source_id           TEXT NOT NULL REFERENCES documentation_sources(id) ON DELETE CASCADE,
    observed_version    TEXT,
    content_relative_path TEXT,
    checksum_sha256     TEXT,
    etag                TEXT,
    http_status         INTEGER,
    retrieved_at_utc    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    snapshot_state      TEXT NOT NULL DEFAULT 'captured' CHECK (snapshot_state IN ('captured','partial','failed','superseded')),
    metadata_json       TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS documentation_chunks (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    snapshot_id         TEXT NOT NULL REFERENCES documentation_snapshots(id) ON DELETE CASCADE,
    source_id           TEXT NOT NULL REFERENCES documentation_sources(id) ON DELETE CASCADE,
    chunk_number        INTEGER NOT NULL,
    page_title          TEXT NOT NULL,
    heading_path        TEXT NOT NULL DEFAULT '',
    canonical_url       TEXT NOT NULL,
    content_text        TEXT NOT NULL,
    language_code       TEXT NOT NULL DEFAULT 'en',
    token_count         INTEGER NOT NULL DEFAULT 0,
    content_hash        TEXT,
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(snapshot_id, chunk_number)
);

CREATE TABLE IF NOT EXISTS documentation_links (
    id                  TEXT PRIMARY KEY,
    source_id           TEXT NOT NULL REFERENCES documentation_sources(id) ON DELETE CASCADE,
    from_chunk_id       INTEGER REFERENCES documentation_chunks(id) ON DELETE CASCADE,
    target_url          TEXT NOT NULL,
    link_text           TEXT,
    relation_kind       TEXT NOT NULL DEFAULT 'references'
);

CREATE TABLE IF NOT EXISTS architecture_rule_sets (
    id                  TEXT PRIMARY KEY,
    workspace_id        TEXT REFERENCES workspaces(id) ON DELETE CASCADE,
    rule_set_key        TEXT NOT NULL,
    display_name        TEXT NOT NULL,
    description         TEXT NOT NULL DEFAULT '',
    source_path         TEXT,
    version             TEXT NOT NULL DEFAULT '1',
    is_enabled          INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0,1)),
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    UNIQUE(workspace_id, rule_set_key)
);

CREATE TABLE IF NOT EXISTS architecture_rules (
    id                  TEXT PRIMARY KEY,
    rule_set_id         TEXT NOT NULL REFERENCES architecture_rule_sets(id) ON DELETE CASCADE,
    rule_key            TEXT NOT NULL,
    title               TEXT NOT NULL,
    rule_text           TEXT NOT NULL,
    rationale           TEXT NOT NULL DEFAULT '',
    path_glob           TEXT,
    severity            TEXT NOT NULL DEFAULT 'warning' CHECK (severity IN ('info','warning','error','critical')),
    validation_kind     TEXT NOT NULL DEFAULT 'agent_review' CHECK (validation_kind IN ('agent_review','static_check','test','manual')),
    priority            INTEGER NOT NULL DEFAULT 100,
    is_enabled          INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0,1)),
    configuration_json  TEXT NOT NULL DEFAULT '{}',
    UNIQUE(rule_set_id, rule_key)
);

CREATE TABLE IF NOT EXISTS architecture_rule_evaluations (
    id                  TEXT PRIMARY KEY,
    rule_set_id         TEXT NOT NULL REFERENCES architecture_rule_sets(id) ON DELETE CASCADE,
    workspace_id        TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
    conversation_id     TEXT REFERENCES conversations(id) ON DELETE SET NULL,
    revision_identifier TEXT,
    evaluation_state    TEXT NOT NULL CHECK (evaluation_state IN ('queued','running','passed','warnings','failed','cancelled')),
    summary             TEXT NOT NULL DEFAULT '',
    started_at_utc      TEXT,
    completed_at_utc    TEXT
);

CREATE TABLE IF NOT EXISTS architecture_violations (
    id                  TEXT PRIMARY KEY,
    evaluation_id       TEXT NOT NULL REFERENCES architecture_rule_evaluations(id) ON DELETE CASCADE,
    rule_id             TEXT NOT NULL REFERENCES architecture_rules(id) ON DELETE CASCADE,
    file_path           TEXT,
    line_start          INTEGER,
    line_end            INTEGER,
    finding_message     TEXT NOT NULL,
    evidence_text       TEXT,
    finding_state       TEXT NOT NULL DEFAULT 'open' CHECK (finding_state IN ('open','accepted','fixed','ignored')),
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS semantic_index_runs (
    id                  TEXT PRIMARY KEY,
    workspace_id        TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    repository_id       TEXT REFERENCES repositories(id) ON DELETE SET NULL,
    index_state         TEXT NOT NULL CHECK (index_state IN ('queued','running','completed','partial','failed','cancelled')),
    files_seen          INTEGER NOT NULL DEFAULT 0,
    files_indexed       INTEGER NOT NULL DEFAULT 0,
    symbols_indexed     INTEGER NOT NULL DEFAULT 0,
    progress_percent    REAL NOT NULL DEFAULT 0 CHECK (progress_percent BETWEEN 0 AND 100),
    started_at_utc      TEXT,
    completed_at_utc    TEXT,
    error_summary       TEXT,
    metrics_json        TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS semantic_nodes (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id        TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    repository_id       TEXT REFERENCES repositories(id) ON DELETE CASCADE,
    index_run_id        TEXT REFERENCES semantic_index_runs(id) ON DELETE SET NULL,
    node_key            TEXT NOT NULL UNIQUE,
    node_kind           TEXT NOT NULL CHECK (node_kind IN ('file','module','namespace','type','function','method','property','symbol','test','document')),
    display_name        TEXT NOT NULL,
    qualified_name      TEXT,
    file_path           TEXT,
    language_code       TEXT,
    signature_text      TEXT,
    summary_text        TEXT NOT NULL DEFAULT '',
    start_line          INTEGER,
    end_line            INTEGER,
    content_hash        TEXT,
    metadata_json       TEXT NOT NULL DEFAULT '{}',
    indexed_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS semantic_edges (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    from_node_id        INTEGER NOT NULL REFERENCES semantic_nodes(id) ON DELETE CASCADE,
    to_node_id          INTEGER NOT NULL REFERENCES semantic_nodes(id) ON DELETE CASCADE,
    relation_kind       TEXT NOT NULL CHECK (relation_kind IN ('contains','imports','calls','implements','inherits','references','depends_on','tests','defines')),
    confidence          REAL NOT NULL DEFAULT 1.0 CHECK (confidence BETWEEN 0 AND 1),
    source_location     TEXT,
    metadata_json       TEXT NOT NULL DEFAULT '{}',
    UNIQUE(from_node_id, to_node_id, relation_kind)
);

CREATE TABLE IF NOT EXISTS semantic_aliases (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    node_id             INTEGER NOT NULL REFERENCES semantic_nodes(id) ON DELETE CASCADE,
    alias_text          TEXT NOT NULL,
    alias_kind          TEXT NOT NULL DEFAULT 'alternate_name',
    UNIQUE(node_id, alias_text)
);

CREATE TABLE IF NOT EXISTS semantic_embeddings (
    node_id             INTEGER PRIMARY KEY REFERENCES semantic_nodes(id) ON DELETE CASCADE,
    model_identifier    TEXT NOT NULL,
    vector_dimensions   INTEGER NOT NULL CHECK (vector_dimensions > 0),
    vector_encoding     TEXT NOT NULL DEFAULT 'float32-le',
    vector_blob         BLOB NOT NULL,
    generated_at_utc    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS semantic_queries (
    id                  TEXT PRIMARY KEY,
    workspace_id        TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
    agent_id            TEXT REFERENCES agents(id) ON DELETE SET NULL,
    query_text          TEXT NOT NULL,
    normalized_query    TEXT,
    retrieval_strategy  TEXT NOT NULL DEFAULT 'hybrid' CHECK (retrieval_strategy IN ('lexical','graph','vector','hybrid')),
    result_count        INTEGER NOT NULL DEFAULT 0,
    latency_ms          INTEGER,
    results_json        TEXT NOT NULL DEFAULT '[]',
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS web_search_sessions (
    id                  TEXT PRIMARY KEY,
    conversation_id     TEXT REFERENCES conversations(id) ON DELETE SET NULL,
    agent_id            TEXT REFERENCES agents(id) ON DELETE SET NULL,
    query_text          TEXT NOT NULL,
    search_provider     TEXT NOT NULL DEFAULT 'codex_tool',
    search_state        TEXT NOT NULL DEFAULT 'pending' CHECK (search_state IN ('pending','completed','failed')),
    started_at_utc      TEXT,
    completed_at_utc    TEXT,
    metadata_json       TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS web_search_results (
    id                  TEXT PRIMARY KEY,
    search_session_id   TEXT NOT NULL REFERENCES web_search_sessions(id) ON DELETE CASCADE,
    result_rank         INTEGER NOT NULL,
    title               TEXT NOT NULL,
    canonical_url       TEXT NOT NULL,
    domain              TEXT,
    snippet             TEXT,
    published_at_utc    TEXT,
    retrieved_at_utc    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    source_metadata_json TEXT NOT NULL DEFAULT '{}',
    UNIQUE(search_session_id, result_rank)
);

CREATE TABLE IF NOT EXISTS repository_changes (
    id                  TEXT PRIMARY KEY,
    repository_id       TEXT REFERENCES repositories(id) ON DELETE SET NULL,
    agent_id            TEXT REFERENCES agents(id) ON DELETE SET NULL,
    conversation_id     TEXT REFERENCES conversations(id) ON DELETE SET NULL,
    branch_name         TEXT,
    base_revision       TEXT,
    proposed_revision   TEXT,
    change_summary      TEXT NOT NULL,
    diff_relative_path  TEXT,
    change_state        TEXT NOT NULL DEFAULT 'proposed' CHECK (change_state IN ('proposed','reviewed','approved','rejected','published','failed')),
    reviewed_at_utc     TEXT,
    published_at_utc    TEXT,
    metadata_json       TEXT NOT NULL DEFAULT '{}',
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS repository_change_files (
    id                  TEXT PRIMARY KEY,
    change_id           TEXT NOT NULL REFERENCES repository_changes(id) ON DELETE CASCADE,
    file_path           TEXT NOT NULL,
    change_kind         TEXT NOT NULL CHECK (change_kind IN ('added','modified','deleted','renamed')),
    additions           INTEGER NOT NULL DEFAULT 0,
    deletions           INTEGER NOT NULL DEFAULT 0,
    patch_relative_path TEXT,
    UNIQUE(change_id, file_path)
);

CREATE TABLE IF NOT EXISTS notifications (
    id                  TEXT PRIMARY KEY,
    notification_kind   TEXT NOT NULL,
    title               TEXT NOT NULL,
    body_text           TEXT NOT NULL DEFAULT '',
    related_entity_type TEXT,
    related_entity_id   TEXT,
    is_read             INTEGER NOT NULL DEFAULT 0 CHECK (is_read IN (0,1)),
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    read_at_utc         TEXT
);

CREATE TABLE IF NOT EXISTS background_jobs (
    id                  TEXT PRIMARY KEY,
    job_kind            TEXT NOT NULL,
    job_state           TEXT NOT NULL CHECK (job_state IN ('queued','running','completed','failed','cancelled')),
    priority            INTEGER NOT NULL DEFAULT 100,
    payload_json        TEXT NOT NULL DEFAULT '{}',
    attempt_count       INTEGER NOT NULL DEFAULT 0,
    max_attempts        INTEGER NOT NULL DEFAULT 3,
    scheduled_at_utc    TEXT,
    started_at_utc      TEXT,
    completed_at_utc    TEXT,
    last_error          TEXT
);

CREATE TABLE IF NOT EXISTS sync_state (
    sync_key             TEXT PRIMARY KEY,
    provider             TEXT NOT NULL,
    cursor_value         TEXT,
    last_success_at_utc  TEXT,
    last_attempt_at_utc  TEXT,
    sync_state           TEXT NOT NULL DEFAULT 'idle' CHECK (sync_state IN ('idle','running','failed')),
    metadata_json        TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS audit_events (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    actor_kind          TEXT NOT NULL CHECK (actor_kind IN ('user','agent','codex','plugin','system')),
    actor_id            TEXT,
    event_kind          TEXT NOT NULL,
    target_kind         TEXT,
    target_id           TEXT,
    outcome             TEXT NOT NULL CHECK (outcome IN ('success','denied','failed','pending')),
    details_json        TEXT NOT NULL DEFAULT '{}',
    is_redacted         INTEGER NOT NULL DEFAULT 1 CHECK (is_redacted IN (0,1)),
    created_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

CREATE TABLE IF NOT EXISTS data_retention_policies (
    policy_key          TEXT PRIMARY KEY,
    entity_kind         TEXT NOT NULL,
    retention_days      INTEGER,
    delete_payloads     INTEGER NOT NULL DEFAULT 0 CHECK (delete_payloads IN (0,1)),
    is_enabled          INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0,1)),
    updated_at_utc      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);

-- Search indexes. FTS5 is lexical retrieval; semantic graph and optional vector retrieval
-- are separate backend responsibilities. Do not label FTS alone as semantic understanding.
CREATE VIRTUAL TABLE IF NOT EXISTS documentation_chunks_fts USING fts5(
    page_title, heading_path, content_text,
    content='documentation_chunks', content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);
CREATE TRIGGER IF NOT EXISTS documentation_chunks_ai AFTER INSERT ON documentation_chunks BEGIN
    INSERT INTO documentation_chunks_fts(rowid, page_title, heading_path, content_text)
    VALUES (new.id, new.page_title, new.heading_path, new.content_text);
END;
CREATE TRIGGER IF NOT EXISTS documentation_chunks_ad AFTER DELETE ON documentation_chunks BEGIN
    INSERT INTO documentation_chunks_fts(documentation_chunks_fts, rowid, page_title, heading_path, content_text)
    VALUES ('delete', old.id, old.page_title, old.heading_path, old.content_text);
END;
CREATE TRIGGER IF NOT EXISTS documentation_chunks_au AFTER UPDATE ON documentation_chunks BEGIN
    INSERT INTO documentation_chunks_fts(documentation_chunks_fts, rowid, page_title, heading_path, content_text)
    VALUES ('delete', old.id, old.page_title, old.heading_path, old.content_text);
    INSERT INTO documentation_chunks_fts(rowid, page_title, heading_path, content_text)
    VALUES (new.id, new.page_title, new.heading_path, new.content_text);
END;

CREATE VIRTUAL TABLE IF NOT EXISTS semantic_nodes_fts USING fts5(
    display_name, qualified_name, file_path, signature_text, summary_text,
    content='semantic_nodes', content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);
CREATE TRIGGER IF NOT EXISTS semantic_nodes_ai AFTER INSERT ON semantic_nodes BEGIN
    INSERT INTO semantic_nodes_fts(rowid, display_name, qualified_name, file_path, signature_text, summary_text)
    VALUES (new.id, new.display_name, new.qualified_name, new.file_path, new.signature_text, new.summary_text);
END;
CREATE TRIGGER IF NOT EXISTS semantic_nodes_ad AFTER DELETE ON semantic_nodes BEGIN
    INSERT INTO semantic_nodes_fts(semantic_nodes_fts, rowid, display_name, qualified_name, file_path, signature_text, summary_text)
    VALUES ('delete', old.id, old.display_name, old.qualified_name, old.file_path, old.signature_text, old.summary_text);
END;
CREATE TRIGGER IF NOT EXISTS semantic_nodes_au AFTER UPDATE ON semantic_nodes BEGIN
    INSERT INTO semantic_nodes_fts(semantic_nodes_fts, rowid, display_name, qualified_name, file_path, signature_text, summary_text)
    VALUES ('delete', old.id, old.display_name, old.qualified_name, old.file_path, old.signature_text, old.summary_text);
    INSERT INTO semantic_nodes_fts(rowid, display_name, qualified_name, file_path, signature_text, summary_text)
    VALUES (new.id, new.display_name, new.qualified_name, new.file_path, new.signature_text, new.summary_text);
END;

CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
    author_label, body_text,
    content='messages', content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);
CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
    INSERT INTO messages_fts(rowid, author_label, body_text)
    VALUES (new.id, new.author_label, new.body_text);
END;
CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, author_label, body_text)
    VALUES ('delete', old.id, old.author_label, old.body_text);
END;
CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, author_label, body_text)
    VALUES ('delete', old.id, old.author_label, old.body_text);
    INSERT INTO messages_fts(rowid, author_label, body_text)
    VALUES (new.id, new.author_label, new.body_text);
END;

-- Index visible text/code/diff parts separately so large structured messages
-- remain searchable without copying their content into messages.body_text.
CREATE VIRTUAL TABLE IF NOT EXISTS message_parts_fts USING fts5(
    part_type, text_content,
    content='message_parts', content_rowid='search_rowid',
    tokenize='unicode61 remove_diacritics 2'
);
CREATE TRIGGER IF NOT EXISTS message_parts_ai AFTER INSERT ON message_parts BEGIN
    INSERT INTO message_parts_fts(rowid, part_type, text_content)
    VALUES (new.search_rowid, new.part_type, new.text_content);
END;
CREATE TRIGGER IF NOT EXISTS message_parts_ad AFTER DELETE ON message_parts BEGIN
    INSERT INTO message_parts_fts(message_parts_fts, rowid, part_type, text_content)
    VALUES ('delete', old.search_rowid, old.part_type, old.text_content);
END;
CREATE TRIGGER IF NOT EXISTS message_parts_au AFTER UPDATE ON message_parts BEGIN
    INSERT INTO message_parts_fts(message_parts_fts, rowid, part_type, text_content)
    VALUES ('delete', old.search_rowid, old.part_type, old.text_content);
    INSERT INTO message_parts_fts(rowid, part_type, text_content)
    VALUES (new.search_rowid, new.part_type, new.text_content);
END;

-- Query-oriented indexes for large histories and repository metadata.
CREATE INDEX IF NOT EXISTS ix_conversations_updated ON conversations(updated_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_conversations_agent ON conversations(agent_id, updated_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_threads_conversation ON codex_threads(conversation_id, created_at_utc);
CREATE INDEX IF NOT EXISTS ix_turns_thread_status ON codex_turns(thread_record_id, turn_status, turn_number DESC);
CREATE INDEX IF NOT EXISTS ix_messages_conversation_order ON messages(conversation_id, sequence_number);
CREATE INDEX IF NOT EXISTS ix_messages_turn ON messages(turn_record_id, sequence_number);
CREATE INDEX IF NOT EXISTS ix_events_conversation_order ON conversation_events(conversation_id, event_sequence);
CREATE INDEX IF NOT EXISTS ix_approval_state ON approval_requests(approval_state, requested_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_tool_runs_state ON tool_runs(run_status, started_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_plugins_state ON plugins(availability, display_name);
CREATE INDEX IF NOT EXISTS ix_plugin_logs_plugin_time ON plugin_execution_logs(plugin_id, created_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_docs_source_freshness ON documentation_sources(is_enabled, freshness_state, last_checked_at_utc);
CREATE INDEX IF NOT EXISTS ix_docs_chunks_source ON documentation_chunks(source_id, snapshot_id, chunk_number);
CREATE INDEX IF NOT EXISTS ix_rules_set_priority ON architecture_rules(rule_set_id, is_enabled, priority);
CREATE INDEX IF NOT EXISTS ix_violations_evaluation ON architecture_violations(evaluation_id, finding_state);
CREATE INDEX IF NOT EXISTS ix_semantic_nodes_workspace ON semantic_nodes(workspace_id, node_kind, file_path);
CREATE INDEX IF NOT EXISTS ix_semantic_nodes_symbol ON semantic_nodes(qualified_name, language_code);
CREATE INDEX IF NOT EXISTS ix_semantic_edges_from ON semantic_edges(from_node_id, relation_kind);
CREATE INDEX IF NOT EXISTS ix_semantic_edges_to ON semantic_edges(to_node_id, relation_kind);
CREATE INDEX IF NOT EXISTS ix_semantic_aliases_text ON semantic_aliases(alias_text);
CREATE INDEX IF NOT EXISTS ix_web_results_session ON web_search_results(search_session_id, result_rank);
CREATE INDEX IF NOT EXISTS ix_repo_changes_state ON repository_changes(change_state, created_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_notifications_unread ON notifications(is_read, created_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_jobs_queue ON background_jobs(job_state, priority, scheduled_at_utc);
CREATE INDEX IF NOT EXISTS ix_audit_target ON audit_events(target_kind, target_id, created_at_utc DESC);

-- Foreign-key and workload indexes for joins, cascades and recent-item screens.
-- Keep indexes tied to real query paths; review with EXPLAIN QUERY PLAN as workloads grow.
CREATE INDEX IF NOT EXISTS ix_workspace_repositories_repository ON workspace_repositories(repository_id, workspace_id);
CREATE INDEX IF NOT EXISTS ix_agent_repository_repository ON agent_repository_bindings(repository_id, agent_id);
CREATE INDEX IF NOT EXISTS ix_agent_plugin_plugin ON agent_plugin_bindings(plugin_id, agent_id);
CREATE INDEX IF NOT EXISTS ix_conversations_workspace_updated ON conversations(workspace_id, updated_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_attachments_owner_time ON attachments(owner_kind, owner_id, created_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_events_turn_sequence ON conversation_events(turn_record_id, event_sequence);
CREATE INDEX IF NOT EXISTS ix_tool_runs_conversation_time ON tool_runs(conversation_id, started_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_tool_runs_turn ON tool_runs(turn_record_id, started_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_tool_runs_tool ON tool_runs(tool_id, started_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_approvals_conversation_time ON approval_requests(conversation_id, requested_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_approvals_turn_time ON approval_requests(turn_record_id, requested_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_approvals_tool_run ON approval_requests(tool_run_id);
CREATE INDEX IF NOT EXISTS ix_approval_decisions_request_time ON approval_decisions(approval_id, decided_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_plugin_installations_version ON plugin_installations(version_id);
CREATE INDEX IF NOT EXISTS ix_plugin_tools_tool ON plugin_tools(tool_id, plugin_id);
CREATE INDEX IF NOT EXISTS ix_plugin_logs_tool_run ON plugin_execution_logs(tool_run_id, created_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_doc_snapshots_source_time ON documentation_snapshots(source_id, retrieved_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_doc_chunks_snapshot_order ON documentation_chunks(snapshot_id, chunk_number);
CREATE INDEX IF NOT EXISTS ix_doc_links_chunk ON documentation_links(from_chunk_id, relation_kind);
CREATE INDEX IF NOT EXISTS ix_arch_eval_workspace_time ON architecture_rule_evaluations(workspace_id, started_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_arch_eval_conversation_time ON architecture_rule_evaluations(conversation_id, started_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_violations_rule_state ON architecture_violations(rule_id, finding_state);
CREATE INDEX IF NOT EXISTS ix_semantic_runs_repository_state ON semantic_index_runs(repository_id, index_state, started_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_semantic_nodes_repository_path ON semantic_nodes(repository_id, file_path);
CREATE INDEX IF NOT EXISTS ix_semantic_nodes_index_run ON semantic_nodes(index_run_id, node_kind);
CREATE INDEX IF NOT EXISTS ix_semantic_queries_agent_time ON semantic_queries(agent_id, created_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_web_sessions_conversation_time ON web_search_sessions(conversation_id, started_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_web_sessions_agent_time ON web_search_sessions(agent_id, started_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_repo_changes_repository_time ON repository_changes(repository_id, created_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_repo_changes_agent_time ON repository_changes(agent_id, created_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_repo_changes_conversation_time ON repository_changes(conversation_id, created_at_utc DESC);

-- Remaining foreign-key lookup indexes found during schema review.
CREATE INDEX IF NOT EXISTS ix_agents_mode ON agents(mode_key);
CREATE INDEX IF NOT EXISTS ix_arch_eval_rule_set ON architecture_rule_evaluations(rule_set_id, started_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_documentation_links_source ON documentation_links(source_id);
CREATE INDEX IF NOT EXISTS ix_semantic_runs_workspace_state ON semantic_index_runs(workspace_id, index_state, started_at_utc DESC);
CREATE INDEX IF NOT EXISTS ix_semantic_queries_workspace_time ON semantic_queries(workspace_id, created_at_utc DESC);

-- The migration runner records this migration after successful execution,
-- including a SHA-256 checksum of the exact SQL file. Do not hard-code a placeholder.

PRAGMA user_version = 1;
COMMIT;
PRAGMA optimize;
