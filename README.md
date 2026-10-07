# Identity Data Validator

A PowerShell script that checks identity data before it is loaded into an IAM tool.

## Why I made this

Identity automation depends on good data. Joiner, Mover, Leaver (JML) workflows, SCIM provisioning and dynamic group rules all trust the data they receive. One bad row can cause a failed provisioning run, wrong access, or a leaver who can still log in.

This script checks a CSV export (for example from an HR system) and reports problems before the data goes into the IAM tool. It only reads the file. It does not change or create any account.

## What it checks

High problems (the pipeline stops):

* Terminated user whose account is still enabled
* Same employee ID used more than once
* Same email used by more than one person

Medium problems:

* Empty required field
* Email in the wrong format
* Status that is not Active, Terminated or Leave
* accountEnabled that is not true or false
* Active user with a disabled account
* User listed as their own manager
* Manager ID that is not in the file
* Active user whose manager is terminated

Low problems:

* Empty manager field (normal for top managers)
* Extra spaces at the start or end of a value

## How to use it

Run this in PowerShell:

```powershell
.\Test-IdentityData.ps1 -Path .\samples\identities-with-problems.csv
```

To choose where the report is saved:

```powershell
.\Test-IdentityData.ps1 -Path .\data.csv -ReportPath .\result.csv
```

## CSV format

The file must have these columns:

```
employeeId, firstName, lastName, email, department, manager, status, accountEnabled
```

## Result

The script prints the problems on screen and saves them in a report file (validation-report.csv by default). High problems are listed first.

Example with the problem sample file:

```
Rows checked: 10
Findings: 12 (High: 3, Medium: 7, Low: 2)
```

## Exit codes

* 0 means no High problems. It is safe to continue.
* 1 means at least one High problem. Stop the pipeline.

Medium and Low problems are reported but do not stop the pipeline.

## Use in a pipeline

Because of the exit code, a pipeline can stop when the data is bad. Example for GitHub Actions:

```yaml
- name: Validate identity data
  shell: pwsh
  run: ./Test-IdentityData.ps1 -Path ./data/hr-export.csv
```

If the script returns 1, the job fails and the bad data is not loaded.

## Sample files

The samples folder has two files to try:

* identities-with-problems.csv has mistakes on purpose, so you can see the checks work
* identities-clean.csv has good data. It still shows one Low finding because the top manager has no manager, but the exit code is 0

## Limits

* It only checks a CSV file. It does not connect to Entra ID, Okta or any live system.
* It checks if the data is correct in format and consistent. It cannot know if the data is true.
* The rules are at the top of the script, so they are easy to change.

## Ideas for later

* Check department names against an allowed list
* Check UPN format and make sure UPNs are unique
* Find users who have been inactive for a long time but are still enabled
* Add automatic tests and a GitHub Actions workflow
