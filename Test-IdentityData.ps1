# Checks an identity CSV for common data problems before loading it into an IAM tool.
# Usage: .\Test-IdentityData.ps1 -Path .\sample-identities.csv

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$ReportPath = ".\validation-report.csv"
)

$requiredFields = @('employeeId', 'firstName', 'lastName', 'email',
                    'department', 'manager', 'status', 'accountEnabled')
$validStatuses = @('Active', 'Terminated', 'Leave')
$emailPattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'

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

if (-not (Test-Path -Path $Path)) {
    throw "File not found: $Path"
}

$rows = @(Import-Csv -Path $Path)
if ($rows.Count -eq 0) {
    throw "The file has no data rows: $Path"
}

$columns = $rows[0].PSObject.Properties.Name
$missingColumns = $requiredFields | Where-Object { $_ -notin $columns }
if ($missingColumns) {
    throw "Missing required columns: $($missingColumns -join ', ')"
}

$allIds = $rows.employeeId | Where-Object { $_ }

foreach ($row in $rows) {
    $id = $row.employeeId

    foreach ($field in $requiredFields) {
        if ([string]::IsNullOrWhiteSpace($row.$field)) {
            Add-Finding $id 'MissingValue' 'Medium' "Field '$field' is empty."
        }
    }

    if ($row.email -and $row.email -notmatch $emailPattern) {
        Add-Finding $id 'InvalidEmail' 'Medium' "Email '$($row.email)' is not valid."
    }

    if ($row.status -and $row.status -notin $validStatuses) {
        Add-Finding $id 'InvalidStatus' 'Medium' "Status '$($row.status)' is not allowed."
    }

    # a leaver who can still log in is the most serious problem
    if ($row.status -eq 'Terminated' -and $row.accountEnabled -eq 'true') {
        Add-Finding $id 'TerminatedStillEnabled' 'High' 'User is terminated but the account is still enabled.'
    }

    if ($row.manager) {
        if ($row.manager -eq $id) {
            Add-Finding $id 'SelfManager' 'Medium' 'User is their own manager.'
        }
        elseif ($row.manager -notin $allIds) {
            Add-Finding $id 'ManagerNotFound' 'Medium' "Manager '$($row.manager)' is not in the file."
        }
    }
}

$rows | Where-Object { $_.employeeId } | Group-Object employeeId |
    Where-Object Count -gt 1 | ForEach-Object {
        Add-Finding $_.Name 'DuplicateEmployeeId' 'High' "Employee ID appears $($_.Count) times."
    }

$rows | Where-Object { $_.email } | Group-Object { $_.email.ToLower() } |
    Where-Object Count -gt 1 | ForEach-Object {
        $owners = ($_.Group.employeeId) -join ', '
        Add-Finding $owners 'DuplicateEmail' 'High' "Email '$($_.Name)' is shared by: $owners."
    }

Write-Host "Rows checked: $($rows.Count)"
Write-Host "Findings:     $($findings.Count)"

if ($findings.Count -gt 0) {
    $findings | Sort-Object Severity, EmployeeId | Format-Table -AutoSize
    $findings | Export-Csv -Path $ReportPath -NoTypeInformation
    Write-Host "Report saved to $ReportPath"
}
else {
    Write-Host "No problems found."
}

# non-zero exit code lets a pipeline stop on serious problems
if ($findings | Where-Object Severity -eq 'High') {
    exit 1
}
exit 0
