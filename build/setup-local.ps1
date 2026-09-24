<#
.SYNOPSIS
    Creates DB02 on a SQL Server you already have, and runs the whole migration. No Docker.

.DESCRIPTION
    Finds a SQL Server instance that answers, creates DB02 if it is not there, runs
    db/00_run_all.sql, and optionally loads the development fixture so there is something
    to look at.

    Safe to run twice. Every migration script is idempotent, and an existing DB02 is
    migrated over rather than replaced unless you pass -Recreate.

    Works in Windows PowerShell 5.1 and in PowerShell 7.

.PARAMETER Server
    The instance to use. Left out, it tries, in order:

        .                        the local default instance
        .\SQLEXPRESS             SQL Server Express
        (localdb)\MSSQLLocalDB   LocalDB

    and uses the first that answers.

.PARAMETER WithDemoData
    Also run db/dev: 624 invented people, a development framework, and an open cycle with
    398 in the pool. Without it the application runs but has nobody in it.

    It creates and fills the dbo.* tables the application reads, so do not use it against a
    server that already holds real data in tables by those names.

.PARAMETER Recreate
    Drop DB02 first. Everything in it is lost, and you are asked to confirm.

.PARAMETER SqlLogin
    Connect as a SQL login instead of using Windows authentication. You are prompted for
    the password, which is never written to disk or echoed.

.EXAMPLE
    .\build\setup-local.ps1 -WithDemoData

.EXAMPLE
    .\build\setup-local.ps1 -Server '.\SQLEXPRESS' -Recreate -WithDemoData
#>
[CmdletBinding()]
param(
    [string] $Server = '',
    [switch] $WithDemoData,
    [switch] $Recreate,
    [string] $SqlLogin = ''
)

$ErrorActionPreference = 'Stop'

# Whatever happens below, a password this script was given does not outlive it.
$ClearPasswordOnExit = $false
trap { if ($ClearPasswordOnExit) { $env:SQLCMDPASSWORD = $null }; break }

$RepoRoot = Split-Path -Parent $PSScriptRoot
$DbFolder = Join-Path $RepoRoot 'db'

function Write-Step { param([string] $Text) Write-Host ''; Write-Host $Text -ForegroundColor Cyan }
function Write-Ok   { param([string] $Text) Write-Host "  $Text" -ForegroundColor Green }
function Write-Note { param([string] $Text) Write-Host "  $Text" -ForegroundColor DarkGray }
function Write-Warn { param([string] $Text) Write-Host "  $Text" -ForegroundColor Yellow }
function Write-Bad  { param([string] $Text) Write-Host $Text -ForegroundColor Red }

function Stop-Here {
    param([int] $Code = 1)
    if ($ClearPasswordOnExit) { $env:SQLCMDPASSWORD = $null }
    exit $Code
}

# ---------------------------------------------------------------------------------------
# sqlcmd
# ---------------------------------------------------------------------------------------

$found  = Get-Command sqlcmd -ErrorAction SilentlyContinue
$SqlCmd = if ($found) { $found.Source } else { $null }

if (-not $SqlCmd) {
    # It ships with SSMS and with the SQL Server client tools, and is not always on PATH.
    $patterns = @(
        (Join-Path $env:ProgramFiles 'Microsoft SQL Server\Client SDK\ODBC\*\Tools\Binn\sqlcmd.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft SQL Server\Client SDK\ODBC\*\Tools\Binn\sqlcmd.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft SQL Server\*\Tools\Binn\sqlcmd.exe')
    )

    foreach ($pattern in $patterns) {
        $hit = Get-Item $pattern -ErrorAction SilentlyContinue |
               Sort-Object FullName -Descending | Select-Object -First 1
        if ($hit) { $SqlCmd = $hit.FullName; break }
    }
}

if (-not $SqlCmd) {
    Write-Bad @'

sqlcmd was not found.

It comes with SQL Server Management Studio, or on its own:

    winget install Microsoft.Sqlcmd

If you have just installed it, open a new terminal so PATH is picked up.
'@
    Stop-Here
}

Write-Note "sqlcmd: $SqlCmd"

# ---------------------------------------------------------------------------------------
# How every call connects
# ---------------------------------------------------------------------------------------

if ($SqlLogin) {
    # The password goes into SQLCMDPASSWORD, which sqlcmd reads on its own, rather than
    # into -P. A command line is visible to every other process on the machine; an
    # environment variable set for this process and its children is not. It is cleared
    # again when the script ends.
    if (-not $env:SQLCMDPASSWORD) {
        $secure = Read-Host -AsSecureString "Password for $SqlLogin"
        $env:SQLCMDPASSWORD = [System.Net.NetworkCredential]::new('', $secure).Password
        $ClearPasswordOnExit = $true
    } else {
        Write-Note 'Using the password already in SQLCMDPASSWORD.'
        $ClearPasswordOnExit = $false
    }

    $AuthArgs = @('-U', $SqlLogin)
} else {
    $AuthArgs = @('-E')
    $ClearPasswordOnExit = $false
}

# sqlcmd 18 and later encrypt by default, and a local instance usually has a self-signed
# certificate, so -C is needed to trust it. Older builds do not know the flag. Which one
# this is gets settled once, by asking it.
$help = (& $SqlCmd '-?' 2>&1 | Out-String)
# The help prints it as "[-C Trust Server Certificate]", so the bracket is optional.
$TrustArgs = if ($help -match '(?m)^\s*\[?-C\b') { @('-C') } else { @() }

<#
    Runs sqlcmd and returns its exit code, and only its exit code. Output goes to the
    console as it happens, which matters for the migration: its receipt is the thing you
    read to know whether it worked.
#>
function Invoke-Sql {
    param(
        [Parameter(Mandatory)][string] $Instance,
        [string] $Database = '',
        [string] $Query = '',
        [string] $File = '',
        [switch] $Quiet
    )

    $sqlArgs = @('-S', $Instance) + $AuthArgs + $TrustArgs + @('-b')
    if ($Database) { $sqlArgs += @('-d', $Database) }
    if ($File)     { $sqlArgs += @('-I', '-i', $File) }
    else           { $sqlArgs += @('-Q', $Query) }

    if ($Quiet) { & $SqlCmd @sqlArgs 2>&1 | Out-Null }
    else        { & $SqlCmd @sqlArgs 2>&1 | Out-Host }

    return $LASTEXITCODE
}

<#
    A single value, trimmed. Used for the small questions — does DB02 exist, what version
    is this — where the answer is one cell.
#>
function Get-SqlScalar {
    param(
        [Parameter(Mandatory)][string] $Instance,
        [string] $Database = '',
        [Parameter(Mandatory)][string] $Query
    )

    $sqlArgs = @('-S', $Instance) + $AuthArgs + $TrustArgs + @('-b', '-h', '-1', '-W')
    if ($Database) { $sqlArgs += @('-d', $Database) }
    $sqlArgs += @('-Q', "SET NOCOUNT ON; $Query")

    $out = & $SqlCmd @sqlArgs 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }

    $line = @($out) | Where-Object { "$_".Trim() } | Select-Object -First 1
    if ($null -eq $line) { return $null }
    return "$line".Trim()
}

# ---------------------------------------------------------------------------------------
# Find an instance
# ---------------------------------------------------------------------------------------

Write-Step 'Looking for a SQL Server you can reach'

if ($Server) {
    if ((Invoke-Sql -Instance $Server -Query 'SELECT 1' -Quiet) -ne 0) {
        Write-Bad "`n$Server did not answer."
        Write-Bad 'Check the name, that the service is running, and that you can sign in.'
        Stop-Here
    }
    Write-Ok "$Server answered"
}
else {
    $tried = @('.', '.\SQLEXPRESS', '(localdb)\MSSQLLocalDB')

    foreach ($candidate in $tried) {
        # LocalDB is stopped between uses and has to be started before it will answer.
        if ($candidate -like '(localdb)*' -and (Get-Command sqllocaldb -ErrorAction SilentlyContinue)) {
            & sqllocaldb start MSSQLLocalDB 2>&1 | Out-Null
        }

        Write-Note "trying $candidate"
        if ((Invoke-Sql -Instance $candidate -Query 'SELECT 1' -Quiet) -eq 0) {
            $Server = $candidate
            Write-Ok "$candidate answered"
            break
        }
    }

    if (-not $Server) {
        Write-Bad @"

No SQL Server answered on any of: $($tried -join ', ')

Install one. Any of these is enough and none of them needs Docker:

  SQL Server Developer Edition   free, full featured, closest to production
      https://www.microsoft.com/sql-server/sql-server-downloads

  SQL Server Express             free, smaller, plenty for this
      winget install Microsoft.SQLServer.2022.Express

  SQL Server Express LocalDB     the lightest: no service, starts on demand
      Included with the Visual Studio "Data storage and processing" workload,
      or with the Express installer's LocalDB option.

Then run this again, or name the instance yourself:

  .\build\setup-local.ps1 -Server 'myserver\INSTANCE'
"@
        Stop-Here
    }
}

$edition = Get-SqlScalar -Instance $Server -Query @"
SELECT CONVERT(nvarchar(200), SERVERPROPERTY('Edition'))
     + N' ' + CONVERT(nvarchar(20), SERVERPROPERTY('ProductVersion'))
"@
if ($edition) { Write-Note $edition }

# ---------------------------------------------------------------------------------------
# The database
# ---------------------------------------------------------------------------------------

Write-Step 'DB02'

$exists = Get-SqlScalar -Instance $Server -Query "SELECT COUNT(*) FROM sys.databases WHERE name = 'DB02'"

if ($exists -eq '1' -and $Recreate) {
    Write-Warn 'DB02 exists and -Recreate was given.'
    $answer = Read-Host '  Drop it? Everything in it is lost. Type DB02 to confirm'

    if ($answer -cne 'DB02') {
        Write-Warn 'Left alone. Nothing was changed.'
        Stop-Here
    }

    $drop = Invoke-Sql -Instance $Server -Quiet -Query @'
ALTER DATABASE DB02 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE DB02;
'@
    if ($drop -ne 0) { Write-Bad "`nDB02 could not be dropped."; Stop-Here }

    Write-Ok 'dropped'
    $exists = '0'
}

if ($exists -eq '1') {
    Write-Ok 'already there — the migration is idempotent, so it runs over it'
}
else {
    if ((Invoke-Sql -Instance $Server -Query 'CREATE DATABASE DB02' -Quiet) -ne 0) {
        Write-Bad "`nDB02 could not be created. The login needs permission to create a database."
        Stop-Here
    }
    Write-Ok 'created'
}

# ---------------------------------------------------------------------------------------
# The migration
# ---------------------------------------------------------------------------------------

Write-Step 'Running db\00_run_all.sql'
Write-Note 'The receipt at the end is the check: every configuration and reference'
Write-Note 'count must be non-zero.'
Write-Host ''

if (-not (Test-Path (Join-Path $DbFolder '00_run_all.sql'))) {
    Write-Bad "  db\00_run_all.sql was not found under $RepoRoot."
    Write-Bad '  Run this script from inside the repository.'
    Stop-Here
}

# 00_run_all.sql pulls in 01-14 with :r, and those paths are relative to it.
Push-Location $DbFolder
try {
    $code = Invoke-Sql -Instance $Server -Database 'DB02' -File '00_run_all.sql'
}
finally {
    Pop-Location
}

if ($code -ne 0) {
    Write-Bad "`nThe migration failed. Nothing further was run."
    Stop-Here
}

Write-Ok 'schema and reference data applied'

# ---------------------------------------------------------------------------------------
# The development fixture
# ---------------------------------------------------------------------------------------

if ($WithDemoData) {
    Write-Step 'Loading the development fixture'
    Write-Warn 'This creates and fills the dbo.* tables the application reads. Do not do'
    Write-Warn 'this on a server holding real data in tables by those names.'
    Write-Host ''

    Push-Location $DbFolder
    try {
        # Join-Path rather than a literal backslash: PowerShell 7 runs on Linux and macOS
        # too, and sqlcmd there will not open a path written the Windows way.
        $fixture = @(
            (Join-Path 'dev' '01_mock_sources.sql'),
            (Join-Path 'dev' '02_demo_content.sql')
        )

        foreach ($script in $fixture) {
            Write-Note "running $script"
            if ((Invoke-Sql -Instance $Server -Database 'DB02' -File $script) -ne 0) {
                Write-Bad "`n$script failed."
                Stop-Here
            }
        }
    }
    finally {
        Pop-Location
    }

    Write-Ok 'roster loaded, framework built, cycle opened'
}

# ---------------------------------------------------------------------------------------
# What to do next
# ---------------------------------------------------------------------------------------

Write-Step 'Done'

# appsettings.Development.json points at the local default instance. Anything else has to
# be said, and an environment variable says it without editing a file that is in git.
if ($Server -ne '.') {
    $auth = if ($SqlLogin) { "User ID=$SqlLogin;Password=<yours>" } else { 'Integrated Security=True' }
    Write-Host ''
    Write-Warn "The application defaults to the local default instance. Yours is $Server,"
    Write-Warn 'so set this in the same terminal before running it:'
    Write-Host ''
    Write-Host "    `$env:ConnectionStrings__Db02 = `"Data Source=$Server;Initial Catalog=DB02;$auth;Encrypt=False;TrustServerCertificate=True;Application Name=Maseera`"" -ForegroundColor Yellow
}

Write-Host ''
Write-Host '  Run it:' -ForegroundColor Green
Write-Host ''
Write-Host '      dotnet run --project src\Maseera.Web' -ForegroundColor Green
Write-Host ''
Write-Host '  Then open http://localhost:5180 and check /Admin/Health is green.' -ForegroundColor Green

# Whether there is anything to look at is a question about the database, not about which
# switches this run happened to be given: a second run without -WithDemoData must not
# claim the roster is empty when the first run filled it.
$people = Get-SqlScalar -Instance $Server -Database 'DB02' -Query 'SELECT COUNT(*) FROM sel.Employee'

if ($people -eq '0' -or $null -eq $people) {
    Write-Host ''
    Write-Note 'There is nobody in the database yet. For something to look at:'
    Write-Note '    .\build\setup-local.ps1 -WithDemoData'
}
else {
    Write-Host ''
    Write-Note "$people people on the roster."
}

if ($ClearPasswordOnExit) { $env:SQLCMDPASSWORD = $null }
