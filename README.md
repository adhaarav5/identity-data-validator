# Identity Data Validator

A small PowerShell script that checks identity data in a CSV file **before** it is loaded into an IAM or identity governance tool (for example, SailPoint).

Bad source data is one of the most common causes of failed correlation and wrong access. Catching it early saves time in DEV, UAT, and PROD.

> All data in this repository is fake and created for demonstration only.

## What it checks

| Rule | Severity | Why it matters |
|------|----------|----------------|
| Missing required values | Medium | Empty fields break correlation and provisioning rules |
| Invalid email format | Medium | Notifications and account matching can fail |
| Invalid status value | Medium | Lifecycle logic may not run correctly |
| Terminated user with enabled account | High | Security risk: a leaver still has access |
| Duplicate employee ID | High | Two people may be merged into one identity |
| Duplicate email | High | Accounts can be correlated to the wrong person |
| Manager not found / self-manager | Medium | Approval and certification routing can fail |

## How to run

Requires PowerShell 5.1 or later (Windows, macOS, or Linux).

```powershell
.\Test-IdentityData.ps1 -Path .\sample-identities.csv
```

Optional: choose where the report is saved.

```powershell
.\Test-IdentityData.ps1 -Path .\sample-identities.csv -ReportPath .\my-report.csv
```

The script prints the findings, saves them to a CSV report, and exits with code `1` if any High severity issue is found. This lets a pipeline stop a bad file from moving forward.

## Expected result for the sample file

The sample file has deliberate errors, so the script should report problems such as a terminated user with an enabled account, a duplicate employee ID, a duplicate email, an invalid email, an invalid status, a missing department, and a manager who does not exist.

## Ideas for next steps

- Add a rule for required department names from an approved list
- Add unit tests with Pester
- Run the script automatically with GitHub Actions
