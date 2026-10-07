# Checks an identity CSV file for data problems before it is loaded into an IAM tool.
# It only reads the file. It does not change any account.
# Usage: .\Test-IdentityData.ps1 -Path .\samples\identities-with-problems.csv
# Exit code 1 means a High problem was found. Exit code 0 means it is safe to continue.

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$ReportPath = ".\validation-report.csv"
)

# columns that must be in the CSV
$requiredFields = @('employeeId', 'firstName', 'lastName', 'email',
                    'department', 'manager', 'status', 'accountEnabled')

# allowed values
$validStatuses = @('Active', 'Terminated', 'Leave')
$validEnabledValues = @('true', 'false')

# simple email format: text@text.text
$emailPattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'

# used to show High problems first
$severityRank = @{ 'High' = 1; 'Medium' = 2; 'Low' = 3 }

# list where we save every problem we find
$findings = [System.Collections.Generic.List[object]]::new()

function Add-Finding {
    param(
        [string]$EmployeeId,
        [string]$Rule,
        [string]$Severity,
        [string]$Message
    )

    $findings.Add([pscustomobject]@{
        EmployeeId = $EmployeeId
        Rule       = $Rule
        Severity   = $Severity
        Message    = $Message
    })
}

# stop if the file is not there
if (-not (Test-Path -Path $Path)) {
    throw "File not found: $Path"
}

# read the CSV (@() makes sure we always get a list)
$rows = @(Import-Csv -Path $Path)

if ($rows.Count -eq 0) {
    throw "The file has no data rows: $Path"
}

# stop if any required column is missing
$columns = $rows[0].PSObject.Properties.Name
$missingColumns = $requiredFields | Where-Object { $_ -notin $columns }

if ($missingColumns) {
    throw "Missing required columns: $($missingColumns -join ', ')"
}

# lookup table: employee ID gives the person's row (needed for manager checks)
$employeesById = @{}
foreach ($row in $rows) {
    $cleanId = ([string]$row.employeeId).Trim()
    if ($cleanId) {
        $employeesById[$cleanId] = $row
    }
}

# row 1 is the header, so the first person is row 2
$rowNumber = 1

foreach ($row in $rows) {
    $rowNumber++

    # trim removes spaces at the start and end
    $id      = ([string]$row.employeeId).Trim()
    $email   = ([string]$row.email).Trim()
    $manager = ([string]$row.manager).Trim()
    $status  = ([string]$row.status).Trim()
    $enabled = ([string]$row.accountEnabled).Trim().ToLower()

    # if the ID is empty, use the row number in the report
    $label = if ($id) { $id } else { "row $rowNumber" }

    # empty fields and extra spaces
    foreach ($field in $requiredFields) {
        $value = [string]$row.$field

        if ([string]::IsNullOrWhiteSpace($value)) {
            # top managers may have no manager, so this one is only Low
            $severity = if ($field -eq 'manager') { 'Low' } else { 'Medium' }
            Add-Finding $label 'MissingValue' $severity "Field '$field' is empty."
        }
        elseif ($value -ne $value.Trim()) {
            Add-Finding $label 'ExtraSpaces' 'Low' "Field '$field' has spaces at the start or end."
        }
    }

    # email format
    if ($email -and $email -notmatch $emailPattern) {
        Add-Finding $label 'InvalidEmail' 'Medium' "Email '$email' is not valid."
    }

    # status must be one of the allowed values
    if ($status -and $status -notin $validStatuses) {
        Add-Finding $label 'InvalidStatus' 'Medium' "Status '$status' is not allowed. Use: $($validStatuses -join ', ')."
    }

    # accountEnabled must be true or false
    if ($enabled -and $enabled -notin $validEnabledValues) {
        Add-Finding $label 'InvalidAccountEnabled' 'Medium' "accountEnabled '$($row.accountEnabled)' must be true or false."
    }

    # a leaver who can still log in is the most serious problem
    if ($status -eq 'Terminated' -and $enabled -eq 'true') {
        Add-Finding $label 'TerminatedStillEnabled' 'High' 'User is terminated but the account is still enabled.'
    }

    # an active user should not have a disabled account
    if ($status -eq 'Active' -and $enabled -eq 'false') {
        Add-Finding $label 'ActiveButDisabled' 'Medium' 'User is Active but the account is disabled.'
    }

    # manager checks
    if ($manager) {
        if ($manager -eq $id) {
            Add-Finding $label 'SelfManager' 'Medium' 'User is their own manager.'
        }
        elseif (-not $employeesById.ContainsKey($manager)) {
            Add-Finding $label 'ManagerNotFound' 'Medium' "Manager '$manager' is not in the file."
        }
        elseif ($employeesById[$manager].status -eq 'Terminated' -and $status -ne 'Terminated') {
            Add-Finding $label 'ManagerTerminated' 'Medium' "Manager '$manager' is terminated."
        }
    }
}

# duplicate employee IDs
$rows | Where-Object { $_.employeeId } |
    Group-Object { ([string]$_.employeeId).Trim() } |
    Where-Object Count -gt 1 |
    ForEach-Object {
        Add-Finding $_.Name 'DuplicateEmployeeId' 'High' "Employee ID appears $($_.Count) times."
    }

# duplicate emails (lowercase first, so Anna@x.com and anna@x.com match)
$rows | Where-Object { $_.email } |
    Group-Object { ([string]$_.email).Trim().ToLower() } |
    Where-Object Count -gt 1 |
    ForEach-Object {
        $owners = ($_.Group.employeeId) -join ', '
        Add-Finding $owners 'DuplicateEmail' 'High' "Email '$($_.Name)' is shared by: $owners."
    }

# count problems by severity
$highCount   = @($findings | Where-Object Severity -eq 'High').Count
$mediumCount = @($findings | Where-Object Severity -eq 'Medium').Count
$lowCount    = @($findings | Where-Object Severity -eq 'Low').Count

Write-Host "Rows checked: $($rows.Count)"
Write-Host "Findings: $($findings.Count) (High: $highCount, Medium: $mediumCount, Low: $lowCount)"

if ($findings.Count -gt 0) {
    # High first, then Medium, then Low
    $sorted = $findings | Sort-Object @{ Expression = { $severityRank[$_.Severity] } }, EmployeeId

    $sorted | Format-Table -AutoSize | Out-Host
    $sorted | Export-Csv -Path $ReportPath -NoTypeInformation
    Write-Host "Report saved to $ReportPath"
}
else {
    Write-Host "No problems found."
}

# exit code 1 lets a pipeline stop when a serious problem is found
if ($highCount -gt 0) {
    exit 1
}

exit 0
