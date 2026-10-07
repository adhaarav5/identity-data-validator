# Identity Data Validator

A small PowerShell script that checks identity data **before** it reaches an IAM tool.

## The problem

Identity automation (Joiner-Mover-Leaver workflows, SCIM provisioning, dynamic Entra ID
group rules) trusts the data it is given. One bad row can cause:

- a failed provisioning run (badly formatted email or UPN)
- the wrong access (wrong department or manager)
- a security gap (a leaver whose account is still enabled)

This script acts as a **pre-provisioning guardrail**. It reads an HR or directory export (CSV),
runs a set of checks, and stops the pipeline if the data is not safe to load.

It is read-only: it never creates, changes or disables accounts.

## What it checks

| Rule | Severity | What it catches |
|------|----------|-----------------|
| TerminatedStillEnabled | High | Leaver whose account is still enabled |
| DuplicateEmployeeId | High | Same employee ID on more than one row |
| DuplicateEmail | High | Two people sharing one email address |
| MissingValue | Medium (Low for manager) | Empty required field |
| InvalidEmail | Medium | Email that is not in a valid format |
| InvalidStatus | Medium | Status other than Active, Terminated, Leave |
| InvalidAccountEnabled | Medium | accountEnabled that is not true or false |
| ActiveButDisabled | Medium | Active employee with a disabled account |
| SelfManager | Medium | Person listed as their own manager |
| ManagerNotFound | Medium | Manager ID that does not exist in the file |
| ManagerTerminated | Medium | Active employee whose manager has left |
| ExtraSpaces | Low | Spaces at the start or end of a value |

## Usage

```powershell
.\Test-IdentityData.ps1 -Path .\samples\identities-with-problems.csv
```

Optional: choose where the report is saved.

```powershell
.\Test-IdentityData.ps1 -Path .\data.csv -ReportPath .\reports\result.csv
```

### Input format

The CSV needs these columns: `employeeId, firstName, lastName, email, department, manager, status, accountEnabled`

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | No High severity findings. Safe to continue. |
| 1 | At least one High severity finding. Stop the pipeline. |

Medium and Low findings are reported but do not stop the pipeline.

## Example output

Running against `samples/identities-with-problems.csv`:

```
Rows checked : 10
Findings     : 12  (High: 3, Medium: 7, Low: 2)
```

The full list is saved to `validation-report.csv`.

## Using it in a pipeline

Because it returns an exit code, any CI/CD tool can use it as a gate. Example GitHub Actions step:

```yaml
- name: Validate identity data
  shell: pwsh
  run: ./Test-IdentityData.ps1 -Path ./data/hr-export.csv
```

If the script exits with 1, the job fails and the data is never loaded.

## Limits

- It checks a CSV file only. It does not connect to Entra ID, Okta or any live system.
- It validates structure and consistency, not whether the data is true.
- The rules (allowed statuses, email pattern) are at the top of the script and are easy to change.

## Ideas for next steps

- Allowed department list or department-code format check
- UPN format and UPN uniqueness check
- Detect users inactive for a long time but still enabled
- Pester tests and a GitHub Actions workflow that runs them on every push
