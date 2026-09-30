<#
.SYNOPSIS
    Checks identity data in a CSV file before it is loaded into an IAM tool.

.DESCRIPTION
    Reads a CSV file of identities and looks for common data problems that
    cause aggregation, correlation, and provisioning errors:
      - Missing required values
      - Invalid email format
      - Duplicate employee IDs or emails
      - Invalid status values
      - Terminated users whose accounts are still enabled
      - Managers who do not exist in the file, or who are their own manager

    Results are printed to the console and saved to a CSV report.
    The script exits with code 1 if any High severity finding exists,
    so it can also stop a pipeline.

.PARAMETER Path
    Path to the identity CSV file.

.PARAMETER ReportPath
    Where to save the findings report. Default: .\validation-report.csv

.EXAMPLE
    .\Test-IdentityData.ps1 -Path .\sample-identities.csv
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$ReportPath = ".\validation-report.csv"
)

$requiredFields = @('employeeId', 'firstName', 'lastName', 'email',
                    'department', 'manager', 'status', 'accountEnabled')
$validStatuses  = @('Active', 'Terminated', 'Leave')
$emailPattern   = '^[^@\s]+@[^@\s]+\.[^@\s]+$'

$findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param($EmployeeId, [string]$Rule, [string]$Severity, [string]$Message)
    $findings.Add([pscustomobject]@{
        EmployeeId = $EmployeeId
        Rule       = $Rule
        Severity   = $Severity
        Message    = $Message
    })
}

# --- Load the file ---------------------------------------------------------
if (-not (Test-Path -Path $Path)) {
    throw "File not found: $Path"
}

$rows = @(Import-Csv -Path $Path)
if ($rows.Count -eq 0) {
    throw "The file has no data rows: $Path"
}

# --- Check that all required columns exist ---------------------------------
$columns = $rows[0].PSObject.Properties.Name
$missingColumns = $requiredFields | Where-Object { $_ -notin $columns }
if ($missingColumns) {
    throw "Missing required columns: $($missingColumns -join ', ')"
}

# --- Row-level checks ------------------------------------------------------
$allIds = $rows.employeeId | Where-Object { $_ }

foreach ($row in $rows) {
    $id = $row.employeeId

    # Rule 1: required values must not be empty
    foreach ($field in $requiredFields) {
        if ([string]::IsNullOrWhiteSpace($row.$field)) {
            Add-Finding $id 'MissingValue' 'Medium' "Field '$field' is empty."
        }
    }

    # Rule 2: email format
    if ($row.email -and $row.email -notmatch $emailPattern) {
        Add-Finding $id 'InvalidEmail' 'Medium' "Email '$($row.email)' is not valid."
    }

    # Rule 3: status must be a known value
    if ($row.status -and $row.status -notin $validStatuses) {
        Add-Finding $id 'InvalidStatus' 'Medium' "Status '$($row.status)' is not one of: $($validStatuses -join ', ')."
    }

    # Rule 4: terminated users must not have an enabled account
    if ($row.status -eq 'Terminated' -and $row.accountEnabled -eq 'true') {
        Add-Finding $id 'TerminatedStillEnabled' 'High' 'User is Terminated but the account is still enabled.'
    }

    # Rule 5: manager checks
    if ($row.manager) {
        if ($row.manager -eq $id) {
            Add-Finding $id 'SelfManager' 'Medium' 'User is listed as their own manager.'
        }
        elseif ($row.manager -notin $allIds) {
            Add-Finding $id 'ManagerNotFound' 'Medium' "Manager '$($row.manager)' does not exist in the file."
        }
    }
}

# --- Duplicate checks ------------------------------------------------------
$rows | Where-Object { $_.employeeId } | Group-Object employeeId |
    Where-Object Count -gt 1 | ForEach-Object {
        Add-Finding $_.Name 'DuplicateEmployeeId' 'High' "Employee ID appears $($_.Count) times."
    }

$rows | Where-Object { $_.email } | Group-Object { $_.email.ToLower() } |
    Where-Object Count -gt 1 | ForEach-Object {
        $owners = ($_.Group.employeeId) -join ', '
        Add-Finding $owners 'DuplicateEmail' 'High' "Email '$($_.Name)' is shared by: $owners."
    }

# --- Report ----------------------------------------------------------------
Write-Host ""
Write-Host "Identity data validation" -ForegroundColor Cyan
Write-Host "Rows checked : $($rows.Count)"
Write-Host "Findings     : $($findings.Count)"

if ($findings.Count -gt 0) {
    $findings | Sort-Object Severity, EmployeeId | Format-Table -AutoSize
    $findings | Export-Csv -Path $ReportPath -NoTypeInformation
    Write-Host "Report saved to: $ReportPath"
}
else {
    Write-Host "No problems found." -ForegroundColor Green
}

# Fail (exit code 1) when a High severity issue exists
if ($findings | Where-Object Severity -eq 'High') {
    Write-Host "High severity issues found." -ForegroundColor Red
    exit 1
}
exit 0
