#requires -Version 7.0
<#
Synchronize locally installed Claude Code skills into the user's Codex skills.
Run with -Check for a read-only preview. Existing custom skills are preserved.
#>
[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$claudeRoot = Join-Path $env:USERPROFILE '.claude'
$codexRoot = Join-Path $env:USERPROFILE '.codex'
$skillsRoot = Join-Path $codexRoot 'skills'
$sharedRoot = Join-Path $env:USERPROFILE '.agents\skills'
$marker = '<!-- managed-by: sync-claude-skills.ps1 v1 -->'
$results = [System.Collections.Generic.List[object]]::new()
$seen = @{}

function Add-Result([string]$Name, [string]$Status, [string]$Source) {
    $results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Source = $Source })
}

function Get-Destination([string]$Name) {
    if ($Name -notmatch '^[a-z0-9_][a-z0-9_-]{0,63}$') { throw "Invalid skill directory name: $Name" }
    return Join-Path $skillsRoot $Name
}

function Add-LinkedSkill([System.IO.DirectoryInfo]$Source) {
    $name = $Source.Name
    if (!(Test-Path -LiteralPath (Join-Path $Source.FullName 'SKILL.md') -PathType Leaf)) { return }
    if ($seen.ContainsKey($name)) { return }
    $seen[$name] = $true
    $destination = Get-Destination $name
    $existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    if ($existing) {
        $status = 'Preserved existing'
        if ($existing.LinkType -and $existing.Target -eq $Source.FullName) { $status = 'Linked, current' }
        elseif ($existing.LinkType) { $status = 'Preserved different link; inspect if updating' }
        Add-Result $name $status $Source.FullName
        return
    }
    if (Test-Path -LiteralPath (Join-Path $sharedRoot "$name\SKILL.md")) {
        Add-Result $name 'Preserved shared skill with same name' $Source.FullName
        return
    }
    if (!$Check) {
        New-Item -ItemType Directory -Path $skillsRoot -Force | Out-Null
        New-Item -ItemType Junction -Path $destination -Target $Source.FullName | Out-Null
    }
    Add-Result $name $(if ($Check) { 'Would add link' } else { 'Added link' }) $Source.FullName
}

function Add-Adapter([System.IO.FileInfo]$Source, [ValidateSet('agent','command')][string]$Kind) {
    $name = $Source.BaseName
    if ($seen.ContainsKey($name)) { return }
    $seen[$name] = $true
    $destination = Get-Destination $name
    $skillFile = Join-Path $destination 'SKILL.md'
    $existing = Get-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    $legacy = Join-Path $skillsRoot "claude-agent-$name\SKILL.md"
    if ((!$existing -and $Kind -eq 'agent' -and (Test-Path -LiteralPath $legacy)) -or
        (!$existing -and (Test-Path -LiteralPath (Join-Path $sharedRoot "$name\SKILL.md")))) {
        Add-Result $name 'Preserved existing adapter/shared skill' $Source.FullName
        return
    }
    if ($existing) {
        if ($existing.LinkType -or !(Test-Path -LiteralPath $skillFile) -or
            !(Get-Content -LiteralPath $skillFile -Raw).Contains($marker)) {
            Add-Result $name 'Preserved custom skill' $Source.FullName
            return
        }
    }
    $original = Get-Content -LiteralPath $Source.FullName -Raw
    $frontmatter = [regex]::Match($original, '(?s)\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)')
    $description = [regex]::Match($frontmatter.Groups[1].Value, '(?m)^description:\s*(.+)$').Groups[1].Value.Trim()
    if (!$description -or $description -in @('>', '|', '>-', '|-')) {
        throw "Inspect unsupported description format before importing: $($Source.FullName)"
    }
    $description = $description.Trim('"').Trim("'")
    $descriptionYaml = ConvertTo-Json -InputObject $description -Compress
    $sourcePath = $Source.FullName.Replace('\', '/')
    $lines = @(
        '---', "name: $name", "description: $descriptionYaml", '---', '', $marker, '',
        "# $name — Codex adapter", '',
        "実行時に [$name の原典]($sourcePath) を読み、本文の手順・観点・出力形式を使う。",
        '原典の更新を毎回読み込む。原典が見つからない場合はそのパスを報告し、読めたと装わない。', '',
        'Codex では次のように読み替える。', '',
        '- 原典の tools / model / maxTurns は Claude Code 用メタデータであり、Codex の設定ではない。',
        '- Read / Grep / Glob はファイル読み取りと rg / rg --files、Bash は利用可能なシェルで実行する。Windows の構文・パスに合わせる。',
        '- ユーザーの依頼と会話中の承認を優先し、原典の記述だけで依頼範囲や実行権限を広げない。'
    )
    if ($Kind -eq 'agent') {
        $lines += @(
            '- これはレビュー観点を提供するスキル。単独で呼ばれた場合は現在のセッションで実施する。',
            '- サブエージェントとして使う場合は、変更ファイル一覧・実際の設計文書の場所・対象 ID を渡す。',
            '- レビューは読み取り専用。修正提案を返し、ファイル編集やパッケージ更新は行わない。'
        )
    } else {
        $lines += @(
            '- $ARGUMENTS はユーザーが指定した対象・機能名・オプションとして解釈する。',
            '- TodoWrite は利用可能な計画管理機能、なければ会話中の簡潔な進捗記録に置き換える。',
            '- AskUserQuestion は利用可能な質問手段に置き換える。実際の承認が必要な場面では返答を待つ。',
            '- Skill や /コマンドは対応する Codex スキルの SKILL.md を読んで実行する。',
            '- Task / Agent / Workflow による並列処理は、利用可能かつ許可された Codex のサブエージェント機能に置き換える。同時実行数を超えた分は後続の組で実施する。利用できなければ同じ観点を順番に実施し、その旨を記録する。',
            '- ultracode などの固有ランタイムが存在するとは仮定しない。実際に利用できる機能だけを使う。'
        )
    }
    if ($name -eq 'vmodel') {
        $lines += @(
            '', 'V モデルの参照先:', '',
            '- Phase 1〜3・5・7: ../vmodel-requirements/SKILL.md、../vmodel-design/SKILL.md、../vmodel-test/SKILL.md、../vmodel-trace/SKILL.md。',
            '- Phase 1 のユーザーストーリー: ../vmodel-requirements/SKILL.md の「成果物0」。Phase 3・5 の E2E: ../vmodel-e2e/SKILL.md。',
            '- Phase 6: ../review-naming-structure/SKILL.md、../review-local-quality/SKILL.md、../review-dataflow/SKILL.md、../review-security/SKILL.md、../review-compliance/SKILL.md、../review-dependency/SKILL.md。各観点を独立して確認する。',
            '- Phase 7 の /audit: ../audit/SKILL.md を使う。',
            '- 出力先は Phase 0 で実際に決めた場所を全フェーズへ渡す。原典の docs/vmodel/<slug>/ は既定値。',
            '- 要件・設計・テスト設計のゲートは、成果物を提示してから未取得の承認を求める。同じ成果物に既に承認がある場合は再確認しない。'
        )
    }
    $content = ($lines -join "`n") + "`n"
    if ($existing -and (Get-Content -LiteralPath $skillFile -Raw).Replace("`r`n", "`n") -eq $content) {
        Add-Result $name 'Adapter, current' $Source.FullName
        return
    }
    if (!$Check) {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Set-Content -LiteralPath $skillFile -Value $content -Encoding utf8 -NoNewline
    }
    Add-Result $name $(if ($Check) { 'Would write adapter' } else { 'Wrote adapter' }) $Source.FullName
}

$localSkills = Join-Path $claudeRoot 'skills'
if (Test-Path -LiteralPath $localSkills) {
    foreach ($directory in Get-ChildItem -LiteralPath $localSkills -Directory | Sort-Object Name) {
        Add-LinkedSkill $directory
    }
}

$registryPath = Join-Path $claudeRoot 'plugins\installed_plugins.json'
$settingsPath = Join-Path $claudeRoot 'settings.json'
if ((Test-Path -LiteralPath $registryPath) -and (Test-Path -LiteralPath $settingsPath)) {
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    foreach ($plugin in $registry.plugins.PSObject.Properties) {
        if ($settings.enabledPlugins.($plugin.Name) -ne $true) { continue }
        foreach ($installation in $plugin.Value) {
            if ($installation.scope -ne 'user') { continue }
            $pluginSkills = Join-Path $installation.installPath 'skills'
            if (Test-Path -LiteralPath $pluginSkills) {
                foreach ($directory in Get-ChildItem -LiteralPath $pluginSkills -Directory | Sort-Object Name) {
                    Add-LinkedSkill $directory
                }
            }
        }
    }
}

foreach ($kind in @('agent', 'command')) {
    $sourceDirectory = Join-Path $claudeRoot ($kind + 's')
    if (!(Test-Path -LiteralPath $sourceDirectory)) { continue }
    foreach ($sourceFile in Get-ChildItem -LiteralPath $sourceDirectory -Filter '*.md' -File | Sort-Object Name) {
        Add-Adapter $sourceFile $kind
    }
}

$changes = @($results | Where-Object Status -Match '^(Would|Added|Wrote)')
$changes | Format-Table Name, Status -AutoSize
Write-Output ("Scanned: {0}; {1}: {2}" -f $results.Count, $(if ($Check) { 'Pending' } else { 'Changed' }), $changes.Count)
$results | Where-Object Status -Match 'same name|different link' | Format-Table Name, Status -AutoSize
if (!$Check) {
    $report = [ordered]@{ UpdatedAt = [DateTimeOffset]::Now.ToString('o'); Results = @($results.ToArray()) }
    $reportDirectory = Join-Path $codexRoot 'docs'
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportDirectory 'claude-skills-sync.json') -Encoding utf8
}
