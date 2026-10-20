<#
.SYNOPSIS
    Sets the domain password and lockout baseline, and adds a stricter fine-grained policy for the IT group.

.DESCRIPTION
    Sets the default domain password policy (length, complexity, history, age and account lockout), then creates a
    PSO (Password Settings Object) with stricter rules and attaches it to the IT security group. Prints both
    policies so you can read what is in force.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01.

    RULES THIS SCRIPT FOLLOWS
    - The baseline applies to everyone. The PSO applies only to the named group and overrides the baseline for its members.
    - A PSO is attached to a user or a global security group, never to an OU.
    - It checks whether the PSO exists first, so running it again does not fail or create a duplicate.
    - It prints the policies afterward so you can read them.

    KNOWLEDGE
    - Baseline in the lab: minimum length 12, complexity on, history 24 passwords, maximum age 90 days, minimum age
      1 day, lock out after 5 bad attempts, lockout lasts 30 minutes, observation window 30 minutes.
    - The PSO for IT admins: minimum length 16, history 24, maximum age 60 days, minimum age 1 day, lock out after
      3 bad attempts, 30 minute lockout and window, reversible encryption off.
    - Precedence is the tie-breaker when several PSOs apply to one user. The lowest number wins.
    - The observation window is how long failed attempts are counted. Lockout duration is how long the account stays locked.
    - Lockout threshold of 5 means the 5th bad attempt locks the account. Unlock with Unlock-ADAccount.
    - Reversible encryption stores passwords in a recoverable form and weakens security. Keep it off.
    - Modern guidance (NIST) favors long passphrases and no forced periodic changes, but many audits still require
      the age rules, so the lab uses them.

    PITFALLS
    - A PSO shows no effect on someone who is not in the group it is attached to. Check with
      Get-ADUserResultantPasswordPolicy -Identity <user>.
    - A very low lockout threshold lets an attacker lock out every account on purpose.
    - Changing the baseline does not change passwords already set. It applies at the next password change.

    EXPECTED OUTPUT
    The baseline policy list followed by the PSO list, with the values above.
#>

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
# --- Baseline (everyone) ---
$minLength        = 12                              # CHANGE: minimum password length.
$complexity       = $true                           # CHANGE: require complexity.
$historyCount     = 24                              # CHANGE: passwords remembered.
$maxAge           = New-TimeSpan -Days 90           # CHANGE: maximum password age.
$minAge           = New-TimeSpan -Days 1            # CHANGE: minimum password age.
$lockoutThreshold = 5                               # CHANGE: bad attempts before lockout.
$lockoutDuration  = New-TimeSpan -Minutes 30        # CHANGE: how long an account stays locked.
$lockoutWindow    = New-TimeSpan -Minutes 30        # CHANGE: how long bad attempts are counted.

# --- Stricter policy for a privileged group (PSO) ---
$psoName          = "PSO-IT-Admins"                 # CHANGE: name of the PSO.
$psoGroup         = "SG-IT"                         # CHANGE: global security group the PSO applies to.
$psoPrecedence    = 10                              # CHANGE: lowest number wins when several PSOs apply.
$psoMinLength     = 16                              # CHANGE
$psoHistory       = 24                              # CHANGE
$psoMaxAge        = New-TimeSpan -Days 60           # CHANGE
$psoMinAge        = New-TimeSpan -Days 1            # CHANGE
$psoLockoutThreshold = 3                            # CHANGE
$psoLockoutDuration  = New-TimeSpan -Minutes 30     # CHANGE
$psoLockoutWindow    = New-TimeSpan -Minutes 30     # CHANGE
# ============================================================================================

Import-Module ActiveDirectory

$domain = (Get-ADDomain).DNSRoot

Set-ADDefaultDomainPasswordPolicy -Identity $domain `
    -ComplexityEnabled $complexity `
    -MinPasswordLength $minLength `
    -PasswordHistoryCount $historyCount `
    -MaxPasswordAge $maxAge `
    -MinPasswordAge $minAge `
    -LockoutThreshold $lockoutThreshold `
    -LockoutDuration $lockoutDuration `
    -LockoutObservationWindow $lockoutWindow

if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$psoName'")) {
    New-ADFineGrainedPasswordPolicy -Name $psoName `
        -Precedence $psoPrecedence `
        -ComplexityEnabled $true `
        -MinPasswordLength $psoMinLength `
        -PasswordHistoryCount $psoHistory `
        -MaxPasswordAge $psoMaxAge `
        -MinPasswordAge $psoMinAge `
        -LockoutThreshold $psoLockoutThreshold `
        -LockoutDuration $psoLockoutDuration `
        -LockoutObservationWindow $psoLockoutWindow `
        -ReversibleEncryptionEnabled $false

    Add-ADFineGrainedPasswordPolicySubject -Identity $psoName -Subjects $psoGroup
}

"=== Baseline domain policy ==="
Get-ADDefaultDomainPasswordPolicy | Format-List ComplexityEnabled, MinPasswordLength, PasswordHistoryCount, MaxPasswordAge, MinPasswordAge, LockoutThreshold, LockoutDuration, LockoutObservationWindow | Out-String

"=== Fine-grained policy ==="
Get-ADFineGrainedPasswordPolicy -Identity $psoName | Format-List Name, Precedence, MinPasswordLength, PasswordHistoryCount, MaxPasswordAge, MinPasswordAge, LockoutThreshold, LockoutDuration, LockoutObservationWindow, ReversibleEncryptionEnabled | Out-String
"Applies to:"
Get-ADFineGrainedPasswordPolicySubject -Identity $psoName | Select-Object -ExpandProperty Name

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@13-password-policy.ps1" --query "value[0].message" -o tsv
# ANOTHER ENVIRONMENT: on a domain controller, open PowerShell as a Domain Admin, edit the CONFIGURATION block to
# match your security policy, then run:
#   .\13-password-policy.ps1
# TO CHECK ONE PERSON: Get-ADUserResultantPasswordPolicy -Identity kpark
