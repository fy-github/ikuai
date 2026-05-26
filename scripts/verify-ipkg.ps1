param(
  [string]$PackagePath = "",
  [string]$PackageSource = "package\nullclaw"
)

$ErrorActionPreference = "Stop"

function Fail($Message) {
  Write-Error $Message
  exit 1
}

function Require-File($Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Fail "Missing required file: $Path"
  }
}

function Require-Directory($Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Fail "Missing required directory: $Path"
  }
}

$requiredFiles = @(
  "manifest.json",
  "app\docker-compose.yaml",
  "app\option.json",
  "app\.env",
  "app\environment",
  "app\config\chat.html",
  "app\config\chat-bridge.sh",
  "app\config\nginx.conf",
  "app\config\model-proxy.conf.template",
  "app\config\configure-and-start.sh",
  "app\data\nullclaw-data\config.json",
  "readme",
  "changelog",
  "log\install.log",
  "log\run.log",
  "ui\ico\app.png"
)

$requiredDirectories = @(
  "app\cache",
  "app\config",
  "app\data",
  "app\data\nullclaw-data",
  "log",
  "ui\ico"
)

foreach ($file in $requiredFiles) {
  Require-File (Join-Path $PackageSource $file)
}

foreach ($dir in $requiredDirectories) {
  Require-Directory (Join-Path $PackageSource $dir)
}

$manifestPath = Join-Path $PackageSource "manifest.json"
$optionPath = Join-Path $PackageSource "app\option.json"
$composePath = Join-Path $PackageSource "app\docker-compose.yaml"
$envPath = Join-Path $PackageSource "app\.env"
$containerEnvPath = Join-Path $PackageSource "app\environment"
$configPath = Join-Path $PackageSource "app\data\nullclaw-data\config.json"
$nginxPath = Join-Path $PackageSource "app\config\nginx.conf"
$modelProxyPath = Join-Path $PackageSource "app\config\model-proxy.conf.template"
$chatPath = Join-Path $PackageSource "app\config\chat.html"
$chatBridgePath = Join-Path $PackageSource "app\config\chat-bridge.sh"
$startupPath = Join-Path $PackageSource "app\config\configure-and-start.sh"
$runtimeStatePaths = @(
  "app\data\nullclaw-data\daemon_state.json",
  "app\data\nullclaw-data\state",
  "app\data\nullclaw-data\workspace"
)

foreach ($runtimePath in $runtimeStatePaths) {
  if (Test-Path -LiteralPath (Join-Path $PackageSource $runtimePath)) {
    Fail "package source must not include runtime-generated state: $runtimePath"
  }
}

$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
$options = Get-Content -Raw -Encoding UTF8 -LiteralPath $optionPath | ConvertFrom-Json
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configPath | ConvertFrom-Json
$compose = Get-Content -Raw -Encoding UTF8 -LiteralPath $composePath
$env = Get-Content -Raw -Encoding UTF8 -LiteralPath $envPath
$containerEnv = Get-Content -Raw -Encoding UTF8 -LiteralPath $containerEnvPath
$nginx = Get-Content -Raw -Encoding UTF8 -LiteralPath $nginxPath
$modelProxy = Get-Content -Raw -Encoding UTF8 -LiteralPath $modelProxyPath
$chat = Get-Content -Raw -Encoding UTF8 -LiteralPath $chatPath
$chatBridge = Get-Content -Raw -Encoding UTF8 -LiteralPath $chatBridgePath
$startup = Get-Content -Raw -Encoding UTF8 -LiteralPath $startupPath

if ($manifest.name -ne "nullclaw") {
  Fail "manifest.name must be nullclaw"
}

if ($manifest.version -match "latest") {
  Fail "manifest.version must not use latest"
}

if ($manifest.version -notmatch "^\d+\.\d+\.\d+$") {
  Fail "manifest.version must use xx.xx.xx numeric format, for example 1.0.0"
}

if ($manifest.image -match "latest") {
  Fail "manifest.image must not use latest"
}

if ($compose -notmatch [regex]::Escape("image: $($manifest.image)")) {
  Fail "compose image must match manifest.image"
}

if ($compose -match "(?m)^\s*build\s*:") {
  Fail "compose must not use build"
}

if ($compose -match "(?m)^\s*tmpfs\s*:") {
  Fail "compose must not use tmpfs"
}

if ($compose -match "(?m)^\s*devices\s*:") {
  Fail "compose must not use devices"
}

if ($compose -match "(?m)^\s*pid\s*:\s*host\s*$") {
  Fail "compose must not use pid: host"
}

if ($compose -match "(?m)^\s*network_mode\s*:\s*host\s*$") {
  Fail "compose must not use network_mode: host"
}

if ($compose -notmatch "doc_app_default") {
  Fail "compose must use doc_app_default network"
}

if ($compose -notmatch "(?m)^name:\s*nullclaw-\$\{NAME_NONCE\}\s*$") {
  Fail "compose must set a NAME_NONCE-scoped project name to avoid colliding with other iKuai app compose projects"
}

if ($compose -notmatch "name:\s*doc_app_default") {
  Fail "compose network must set name: doc_app_default"
}

if ($compose -notmatch "\$\{HOST_IP\}:\$\{APP_PORT_WEB\}:8080/tcp") {
  Fail "compose must expose APP_PORT_WEB to the nginx frontend on container port 8080/tcp"
}

if ($compose -notmatch "http://localhost:3000/health") {
  Fail "compose must include Nullclaw healthcheck endpoint"
}

if ($compose -notmatch "http://127\.0\.0\.1:8080/health") {
  Fail "compose must healthcheck the nginx frontend through 127.0.0.1:8080"
}

if ($compose -notmatch "nginx:1\.27\.5-alpine") {
  Fail "compose must include the pinned nginx frontend image"
}

if ($compose -notmatch "\./config/nginx\.conf:/etc/nginx/conf\.d/default\.conf:ro") {
  Fail "compose must mount the package-local nginx frontend config"
}

if ($compose -notmatch "\./config/chat\.html:/usr/share/nginx/html/chat\.html:ro") {
  Fail "compose must mount the package-local LAN chat page"
}

if ($compose -notmatch "\./config/chat-bridge\.sh:/usr/local/bin/chat-bridge\.sh:ro") {
  Fail "compose must mount the package-local chat bridge script"
}

if ($compose -notmatch "\./config/configure-and-start\.sh:/usr/local/bin/configure-and-start\.sh:ro") {
  Fail "compose must mount the package-local Nullclaw configuration startup script"
}

if ($compose -notmatch "model-proxy") {
  Fail "compose must include the trusted private model proxy sidecar"
}

if ($compose -notmatch "model-proxy\.conf\.template") {
  Fail "compose must mount the model proxy nginx template"
}

if ($compose -notmatch "(?m)^\s*user\s*:\s*['""]?0:0['""]?\s*$") {
  Fail "compose must run Nullclaw as root user 0:0 so Linux bind-mounted app data is writable on iKuai"
}

if ($compose -notmatch "(?m)^\s*-\s+/usr/local/bin/configure-and-start\.sh\s*$") {
  Fail "compose must run the Nullclaw configuration startup script"
}

if ($startup -notmatch "exec nullclaw gateway --port 3000 --host ::") {
  Fail "startup script must explicitly start Nullclaw gateway on port 3000 and host ::"
}

if ($startup -notmatch "json_nullable_string") {
  Fail "startup script must write optional URL strings as JSON null when they are empty"
}

if ($startup -notmatch "set -f") {
  Fail "startup script must disable shell glob expansion while serializing comma-delimited string arrays"
}

foreach ($requiredProxyToken in @(
  "rewrite_trusted_private_base_url",
  "getent hosts",
  "nslookup",
  "getent hosts model-proxy",
  ":8081"
)) {
  if ($startup -notmatch [regex]::Escape($requiredProxyToken)) {
    Fail "startup script must support trusted private model address rewrite: $requiredProxyToken"
  }
}

if (-not $modelProxy.Contains('location /v1/')) {
  Fail "model proxy must explicitly proxy the /v1/ prefix used by Nullclaw provider calls"
}

if (-not $modelProxy.Contains('proxy_pass ${NULLCLAW_PROVIDER_BASE_URL}/;')) {
  Fail "model proxy must forward /v1/ requests to the configured upstream base_url"
}

foreach ($requiredBridgeToken in @(
  "chat-bridge.sh",
  "cp /usr/local/bin/chat-bridge.sh /tmp/nullclaw-chat-bridge.sh",
  "nohup /usr/bin/nc -lk -p 32124 -e /tmp/nullclaw-chat-bridge.sh"
)) {
  if ($startup -notmatch [regex]::Escape($requiredBridgeToken)) {
    Fail "startup script must start the local synchronous chat bridge: $requiredBridgeToken"
  }
}

foreach ($requiredChatBridgeToken in @(
  "NULLCLAW_CONFIG_PATH=/nullclaw-data/config.json",
  "nullclaw agent -m",
  "X-Chat-Token",
  "401 Unauthorized",
  "send_text"
)) {
  if ($chatBridge -notmatch [regex]::Escape($requiredChatBridgeToken)) {
    Fail "chat bridge script must implement synchronous local chat handling: $requiredChatBridgeToken"
  }
}


if ($startup -match '"search_base_url": "\$\(json_escape "\$\{NULLCLAW_SEARCH_BASE_URL') {
  Fail "startup script must not write an empty http_request.search_base_url string because Nullclaw validates it as an URL"
}

if ($startup -match '"relay_url": "\$\(json_escape "\$\{NULLCLAW_WEB_RELAY_URL:-\}"') {
  Fail "startup script must not write an empty channels.web relay_url string because Nullclaw validates relay fields when present"
}

if ($startup -match '"relay_token": "\$\(json_escape "\$\{NULLCLAW_WEB_RELAY_TOKEN:-\}"') {
  Fail "startup script must not write an empty channels.web relay_token string because Nullclaw validates relay fields when present"
}

foreach ($requiredStartupToken in @(
  "NULLCLAW_PROVIDER_API_KEY",
  "NULLCLAW_PROVIDER_BASE_URL",
  "NULLCLAW_MODEL",
  "NULLCLAW_WEBHOOK_SECRET",
  "NULLCLAW_TELEGRAM_BOT_TOKEN",
  "NULLCLAW_WHATSAPP_ACCESS_TOKEN",
  "NULLCLAW_WHATSAPP_WEB_BRIDGE_URL",
  "NULLCLAW_SLACK_BOT_TOKEN",
  "NULLCLAW_LARK_APP_ID",
  "NULLCLAW_WECHAT_CALLBACK_TOKEN",
  "NULLCLAW_WECOM_WEBHOOK_URL",
  "NULLCLAW_LINE_ACCESS_TOKEN",
  "NULLCLAW_QQ_BOT_TOKEN",
  "NULLCLAW_TEAMS_CLIENT_ID",
  "NULLCLAW_WEB_AUTH_TOKEN",
  "NULLCLAW_A2A_ENABLED",
  "NULLCLAW_CRON_ENABLED"
)) {
  if ($startup -notmatch [regex]::Escape($requiredStartupToken)) {
    Fail "startup script must expose config variable: $requiredStartupToken"
  }
}

if ($config.gateway.port -ne 3000) {
  Fail "config gateway.port must be 3000"
}

if ($config.gateway.host -ne "::") {
  Fail "config gateway.host must be ::"
}

if ($config.gateway.allow_public_bind -ne $true) {
  Fail "config gateway.allow_public_bind must be true for container port publishing"
}

if ($nginx -notmatch "location = /") {
  Fail "nginx config must handle the root path"
}

if ($nginx -notmatch "location = /chat") {
  Fail "nginx config must expose the LAN chat page at /chat"
}

if ($nginx -notmatch "location = /api/chat") {
  Fail "nginx config must expose the synchronous LAN chat API at /api/chat"
}

if ($nginx -notmatch "http://nullclaw:32124/chat") {
  Fail "nginx config must proxy /api/chat to the local chat bridge on port 32124"
}

if ($nginx -notmatch "location = /api/chat/health") {
  Fail "nginx config must expose the chat bridge health endpoint"
}

if ($nginx -notmatch "proxy_pass http://nullclaw:3000") {
  Fail "nginx config must proxy non-root requests to the nullclaw service"
}

if ($nginx -notmatch "Nullclaw") {
  Fail "nginx root page must identify Nullclaw"
}

if (-not $config.agents.defaults.model.primary) {
  Fail "config must define agents.defaults.model.primary"
}

foreach ($requiredChatToken in @(
  "/health",
  "/api/chat",
  "X-Chat-Token",
  "X-Sender-Id",
  "X-Session-Id",
  'appendMessage("assistant", raw',
  "localStorage"
)) {
  if ($chat -notmatch [regex]::Escape($requiredChatToken)) {
    Fail "chat page must implement the LAN HTTP chat token: $requiredChatToken"
  }
}

if ($chat -notmatch "Nullclaw") {
  Fail "chat page must identify Nullclaw"
}

$volumeLines = ($compose -split "`n") | Where-Object { $_ -match "^\s*-\s+.*:/.*" -and $_ -notmatch "\$\{HOST_IP\}" }
foreach ($line in $volumeLines) {
  $source = (($line -replace "^\s*-\s+", "") -split ":", 2)[0].Trim()
  if ($source -notmatch "^\./") {
    Fail "volume source must be package-local relative path: $line"
  }
  if ($source -match "\$|\.\.|%2e%2e|/\.|\\\.") {
    Fail "volume source contains forbidden path syntax: $line"
  }
}

foreach ($required in @("CPUS_LIMIT=0", "MEMORY_LIMIT=0", "HOST_IP=0.0.0.0", "RESTART=always", "APP_PORT_WEB=23000")) {
  if ($env -notmatch [regex]::Escape($required)) {
    Fail ".env missing required value: $required"
  }
}

foreach ($requiredContainerEnv in @(
  "NULLCLAW_GATEWAY_TOKENS=ikuai8.com"
)) {
  if ($containerEnv -notmatch [regex]::Escape($requiredContainerEnv)) {
    Fail "environment missing required LAN chat default: $requiredContainerEnv"
  }
}

$webAuthDefaultLine = ($containerEnv -split "`r?`n") | Where-Object { $_ -match "^NULLCLAW_WEB_AUTH_TOKEN=" } | Select-Object -First 1
if (-not $webAuthDefaultLine) {
  Fail "environment must define NULLCLAW_WEB_AUTH_TOKEN"
}
if (($webAuthDefaultLine -split "=", 2)[1].Length -ne 0) {
  Fail "NULLCLAW_WEB_AUTH_TOKEN default should stay empty because LAN chat now uses gateway bearer auth"
}
$gatewayTokenLine = ($containerEnv -split "`r?`n") | Where-Object { $_ -match "^NULLCLAW_GATEWAY_TOKENS=" } | Select-Object -First 1
if (-not $gatewayTokenLine) {
  Fail "environment must define NULLCLAW_GATEWAY_TOKENS for the LAN chat page"
}
$gatewayDefaultToken = ($gatewayTokenLine -split "=", 2)[1]
if ($gatewayDefaultToken -notmatch "^[A-Za-z0-9_\.]{4,128}$") {
  Fail "NULLCLAW_GATEWAY_TOKENS default must use safe token characters"
}
if ($chat -notmatch [regex]::Escape("const DEFAULT_TOKEN = `"$gatewayDefaultToken`";")) {
  Fail "chat page default token must match app/environment NULLCLAW_GATEWAY_TOKENS"
}

if (-not ($options -is [array])) {
  Fail "option.json must be a JSON array"
}

$webPortOption = $options | Where-Object { $_.attrname -eq "APP_PORT_WEB" } | Select-Object -First 1
if (-not $webPortOption) {
  Fail "option.json must define APP_PORT_WEB"
}

if ($webPortOption.scope -ne "config") {
  Fail "APP_PORT_WEB must use scope=config"
}

if ($webPortOption.type -ne "integer") {
  Fail "APP_PORT_WEB must use type=integer"
}

$expectedWebPortZhLabel = "Web " + [string]([char]0x8BBF) + [string]([char]0x95EE) + [string]([char]0x7AEF) + [string]([char]0x53E3)
if ($webPortOption.label.zh -ne $expectedWebPortZhLabel) {
  Fail "APP_PORT_WEB zh label must be valid UTF-8 Chinese text"
}

if ($webPortOption.min -ne 1 -or $webPortOption.max -ne 65535) {
  Fail "APP_PORT_WEB must use min=1 and max=65535"
}

foreach ($requiredOption in @(
  "NULLCLAW_PROVIDER",
  "NULLCLAW_MODEL",
  "NULLCLAW_PROVIDER_BASE_URL",
  "NULLCLAW_PROVIDER_API_KEY",
  "NULLCLAW_WEBHOOK_SECRET",
  "NULLCLAW_TELEGRAM_BOT_TOKEN",
  "NULLCLAW_WHATSAPP_ACCESS_TOKEN",
  "NULLCLAW_WHATSAPP_WEB_BRIDGE_URL",
  "NULLCLAW_SLACK_BOT_TOKEN",
  "NULLCLAW_LARK_APP_ID",
  "NULLCLAW_WECHAT_CALLBACK_TOKEN",
  "NULLCLAW_WECOM_WEBHOOK_URL",
  "NULLCLAW_LINE_ACCESS_TOKEN",
  "NULLCLAW_QQ_BOT_TOKEN",
  "NULLCLAW_TEAMS_CLIENT_ID",
  "NULLCLAW_WEB_AUTH_TOKEN"
)) {
  $option = $options | Where-Object { $_.attrname -eq $requiredOption } | Select-Object -First 1
  if (-not $option) {
    Fail "option.json must expose $requiredOption"
  }
  if ($option.scope -ne "environment") {
    Fail "$requiredOption must use scope=environment"
  }
}

foreach ($passwordOption in @(
  "NULLCLAW_PROVIDER_API_KEY",
  "OPENROUTER_API_KEY",
  "OPENAI_API_KEY",
  "NULLCLAW_GATEWAY_TOKENS",
  "NULLCLAW_WEBHOOK_SECRET",
  "NULLCLAW_TELEGRAM_BOT_TOKEN",
  "NULLCLAW_WHATSAPP_ACCESS_TOKEN",
  "NULLCLAW_WHATSAPP_VERIFY_TOKEN",
  "NULLCLAW_WHATSAPP_WEB_PLUGIN_TOKEN",
  "NULLCLAW_SLACK_BOT_TOKEN",
  "NULLCLAW_SLACK_SIGNING_SECRET",
  "NULLCLAW_LARK_APP_SECRET",
  "NULLCLAW_TEAMS_CLIENT_SECRET",
  "NULLCLAW_WEB_AUTH_TOKEN"
)) {
  $option = $options | Where-Object { $_.attrname -eq $passwordOption } | Select-Object -First 1
  if ($option -and $option.type -ne "password") {
    Fail "$passwordOption must use type=password"
  }
}

$environmentVariableNames = ($containerEnv -split "`r?`n") |
  Where-Object { $_ -match "^[A-Z0-9_]+=" } |
  ForEach-Object { ($_ -split "=", 2)[0] }

foreach ($environmentVariableName in $environmentVariableNames) {
  $option = $options | Where-Object { $_.attrname -eq $environmentVariableName } | Select-Object -First 1
  if (-not $option) {
    Fail "option.json must expose environment variable $environmentVariableName"
  }
  if ($option.scope -ne "environment") {
    Fail "$environmentVariableName must use scope=environment"
  }
}

if ($PackagePath) {
  Require-File $PackagePath
  $entries = & tar.exe -tf $PackagePath
  if ($LASTEXITCODE -ne 0) {
    Fail "tar could not list package: $PackagePath"
  }

  foreach ($entry in @(
    "nullclaw/manifest.json",
    "nullclaw/app/docker-compose.yaml",
    "nullclaw/app/option.json",
    "nullclaw/app/config/chat.html",
    "nullclaw/app/config/nginx.conf",
    "nullclaw/app/config/configure-and-start.sh",
    "nullclaw/app/data/nullclaw-data/config.json",
    "nullclaw/app/.env",
    "nullclaw/app/environment",
    "nullclaw/readme",
    "nullclaw/changelog",
    "nullclaw/log/install.log",
    "nullclaw/log/run.log",
    "nullclaw/ui/ico/app.png"
  )) {
    if ($entries -notcontains $entry) {
      Fail "package missing entry: $entry"
    }
  }

  $badEntries = $entries | Where-Object { $_ -match "__MACOSX|/\._|^\.tmp|/\.git/" }
  if ($badEntries) {
    Fail "package contains forbidden entries: $($badEntries -join ', ')"
  }

  $runtimeEntries = $entries | Where-Object {
    $_ -match "^nullclaw/app/data/nullclaw-data/(daemon_state\.json|state/|workspace/)"
  }
  if ($runtimeEntries) {
    Fail "package contains runtime-generated state: $($runtimeEntries -join ', ')"
  }

  $expectedSourceVersion = [regex]::Escape(((([string]$manifest.image) -replace "^.*:", "") -replace "^v", ""))
  $expectedReleaseVersion = [regex]::Escape("v$($manifest.version)")
  $packageName = Split-Path -Leaf $PackagePath
  $expectedPattern = "^nullclaw-$expectedSourceVersion-\d{14}-$expectedReleaseVersion\.ipkg$"
  if ($packageName -notmatch $expectedPattern) {
    Fail "package filename must match nullclaw-<source.version>-<yyyyMMddHHmmss>-v<manifest.version>.ipkg"
  }
}

Write-Host "PASS: nullclaw package source verified"
if ($PackagePath) {
  Write-Host "PASS: package archive verified: $PackagePath"
}
