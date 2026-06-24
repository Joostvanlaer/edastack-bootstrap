# Edastack colleague bootstrap (Windows) — one command from a fresh Windows PC to a running
# Claude Code session in your own copy of the stack. The Windows twin of colleague-bootstrap.sh.
# Public + DATA-FREE: only install/clone logic, no confidential data. This file is the canonical
# source; it is mirrored to the public `edastack-bootstrap` repo as install.ps1 (see the
# onboarding doc for how it's published).
#
# The colleague pastes ONE line into PowerShell (run from a FILE, not piped, so the GitHub
# sign-in reads the keyboard, not the script):
#
#   irm https://raw.githubusercontent.com/Joostvanlaer/edastack-bootstrap/main/install.ps1 -OutFile $env:TEMP\edastack.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\edastack.ps1 <your-repo-name>
#
# e.g. ... edastack.ps1 joostap   → sets up edastack-joostap
#
# NO ADMIN, NO UAC. Everything goes into your user profile:
#   - Git for Windows  → PortableGit, extracted to ~\.local\PortableGit (no installer, no registry)
#   - GitHub CLI (gh)  → release zip, gh.exe copied to ~\.local\bin
#   - Claude Code      → its own user-level installer (auto-updates)
# The only interactive step is the one-time GitHub browser sign-in.
#
# Idempotent: safe to re-run; it skips whatever is already done.

param(
  [Parameter(Mandatory = $true, HelpMessage = "Your repo name suffix, e.g. joostap -> edastack-joostap")]
  [string]$Name
)

$ErrorActionPreference = "Stop"

$Owner   = "Joostvanlaer"
$Repo    = "edastack-$Name"
$Dir     = Join-Path $HOME $Repo
$Local   = Join-Path $HOME ".local"
$Bin     = Join-Path $Local "bin"
$GitDir  = Join-Path $Local "PortableGit"

function Say($msg) { Write-Host "`n==> $msg" -ForegroundColor Green }
function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

New-Item -ItemType Directory -Force -Path $Bin | Out-Null

# Make this session see our user-level tool dirs first, so re-runs and the steps below
# resolve the freshly-installed binaries without needing a new terminal.
$env:Path = "$Bin;$(Join-Path $GitDir 'cmd');$(Join-Path $GitDir 'bin');" + $env:Path

# Detect CPU architecture for the right download (most PCs are x64; Windows-on-ARM is handled).
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "64-bit" }
$ghArch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "amd64" }

# 1. Git for Windows — PortableGit (no installer, no admin). Gives both `git` and the `bash.exe`
#    that Claude Code uses to run the project's scripts.
if (-not (Have "git")) {
  Say "Installing Git for Windows (portable, no admin)…"
  $rel = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest"
  $asset = $rel.assets | Where-Object { $_.name -like "PortableGit-*-$arch.7z.exe" } | Select-Object -First 1
  if (-not $asset) { throw "Could not find a PortableGit download for $arch — check your connection." }
  $sfx = Join-Path $env:TEMP $asset.name
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $sfx
  New-Item -ItemType Directory -Force -Path $GitDir | Out-Null
  # The PortableGit download is a 7-Zip self-extracting archive: silent extract to $GitDir.
  Start-Process -FilePath $sfx -ArgumentList "-y", "-gm2", "-nr", "-o`"$GitDir`"" -Wait
  Remove-Item $sfx -Force -ErrorAction SilentlyContinue
}

# 2. Claude Code — native user-level installer (no Node, auto-updates).
if (-not (Have "claude")) {
  Say "Installing Claude Code…"
  Invoke-RestMethod "https://claude.ai/install.ps1" | Invoke-Expression
}

# 3. GitHub CLI — official release zip into ~\.local\bin (no admin, no winget needed).
if (-not (Have "gh")) {
  Say "Installing the GitHub CLI…"
  $ghRel = Invoke-RestMethod "https://api.github.com/repos/cli/cli/releases/latest"
  $ghAsset = $ghRel.assets | Where-Object { $_.name -like "gh_*_windows_$ghArch.zip" } | Select-Object -First 1
  if (-not $ghAsset) { throw "Could not find a GitHub CLI download for $ghArch — check your connection." }
  $zip = Join-Path $env:TEMP $ghAsset.name
  $tmp = Join-Path $env:TEMP "gh_extract"
  Invoke-WebRequest -Uri $ghAsset.browser_download_url -OutFile $zip
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $ghExe = Get-ChildItem -Path $tmp -Recurse -Filter "gh.exe" | Select-Object -First 1
  Copy-Item $ghExe.FullName (Join-Path $Bin "gh.exe") -Force
  Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# 3b. Python (no admin) — only the optional Outlook/dealflow connectors need it, but we install
#     it now so that path is just as smooth on Windows as on Mac. Skip if Python 3 is present.
$pyVer = "3.13.5"   # known-good pin; bump when python.org publishes a newer 3.x release
if (-not (Have "python") -and -not (Have "py")) {
  Say "Installing Python $pyVer (user-level, no admin)…"
  $pyArch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "amd64" }
  $pyExe = Join-Path $env:TEMP "python-$pyVer-$pyArch.exe"
  Invoke-WebRequest -Uri "https://www.python.org/ftp/python/$pyVer/python-$pyVer-$pyArch.exe" -OutFile $pyExe
  # Quiet PER-USER install: no admin/UAC, adds itself to the user PATH, includes pip + the py launcher.
  Start-Process -FilePath $pyExe -ArgumentList "/quiet", "InstallAllUsers=0", "PrependPath=1", "Include_pip=1", "Include_launcher=1" -Wait
  Remove-Item $pyExe -Force -ErrorAction SilentlyContinue
  # Make this session see it too (the installer only updated the persistent user PATH).
  $pyTag = "Python" + (($pyVer -split '\.')[0..1] -join '')          # 3.13.5 -> Python313
  $pyHome = Join-Path $env:LOCALAPPDATA "Programs\Python\$pyTag"
  if (Test-Path $pyHome) { $env:Path = "$pyHome;$(Join-Path $pyHome 'Scripts');" + $env:Path }
}

# 4. Persist our tool dirs on the USER PATH for future terminals (no admin — user scope only).
$want = @($Bin, (Join-Path $GitDir "cmd"), (Join-Path $GitDir "bin"))
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$parts = if ($userPath) { $userPath -split ";" } else { @() }
$changed = $false
foreach ($p in $want) {
  if ($parts -notcontains $p) { $parts = @($p) + $parts; $changed = $true }
}
if ($changed) {
  [Environment]::SetEnvironmentVariable("Path", ($parts -join ";"), "User")
}

# Belt-and-suspenders: point Claude Code at the portable bash explicitly. PATH (above) is the
# primary mechanism; this env var is a backup in case detection-by-PATH ever misses.
$bashExe = Join-Path $GitDir "bin\bash.exe"
if (Test-Path $bashExe) {
  [Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", $bashExe, "User")
  $env:CLAUDE_CODE_GIT_BASH_PATH = $bashExe
}

# 5. GitHub sign-in — the one interactive step. Skip if already signed in.
& gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
  Say "Sign in to GitHub — a browser opens; sign in as YOUR own account:"
  & gh auth login --hostname github.com --git-protocol https --web
}
& gh auth setup-git 2>$null

# 6. Clone your copy (skip if it's already there).
if (-not (Test-Path (Join-Path $Dir ".git"))) {
  Say "Cloning $Repo…"
  & git clone "https://github.com/$Owner/$Repo.git" $Dir
}
Set-Location $Dir

# 7. Skills link — on Windows the git-tracked symlink (.claude/skills -> ../skills) clones as a
#    plain text file, and real symlinks need admin. A directory JUNCTION needs no admin and the
#    OS treats it as a real folder, so Claude Code's skill discovery sees the skills normally.
$claudeDir = Join-Path $Dir ".claude"
$skillsLink = Join-Path $claudeDir "skills"
New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
$isJunction = (Test-Path $skillsLink) -and ((Get-Item $skillsLink -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
if (-not $isJunction) {
  Say "Linking the skills folder…"
  if (Test-Path $skillsLink) { Remove-Item $skillsLink -Recurse -Force }
  New-Item -ItemType Junction -Path $skillsLink -Target (Join-Path $Dir "skills") | Out-Null
}

# 8. Pull the latest shared tools and commit them, so the pull's safety guard never blocks you.
#    (Runs through the portable bash we just put on PATH.)
Say "Updating tools to the latest…"
& bash meta/tools/pull-engine.sh
& git add -A
& git commit -q -m "update tools to latest (bootstrap)" 2>$null

# 9. Open Claude Code straight into the guided onboarding.
Say "All set — opening Claude Code. Try: `"give me the Monday brief`""
& claude "run colleague onboarding"
