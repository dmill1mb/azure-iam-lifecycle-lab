<#
.SYNOPSIS
    Onboards new employees from a list: creates each account in the right OU, sets a random password, and adds the user to the department group.

.DESCRIPTION
    Reads a CSV list of new starters, skips anyone whose account already exists, and for everyone else
    creates the account in OU=<department>,OU=Staff, records the ticket number in the Description, forces a password
    change at first sign-in, and adds the user to SG-<department>. Prints a result table. Passwords are
    never shown.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01, after 10-create-structure.ps1.

    RULES THIS SCRIPT FOLLOWS
    - Every account is traceable: the Description carries the ticket number that requested it.
    - Each person gets a different random password. It is never printed, logged or saved to a file.
    - Users must change the password at first logon, so only the person knows it.
    - Access comes from the department group. Nobody gets a direct permission.
    - It skips an account that exists, so running it twice does not break anything or reset anyone's password.

    KNOWLEDGE
    - This is the "joiner" step of joiner, mover, leaver. Mover and leaver have their own scripts.
    - The CSV is a here-string inside the script so the lab is self-contained. In a real environment feed this
      from an HR export: Import-Csv .\new-starters.csv (see the CHANGE comment below).
    - sAMAccountName is the legacy sign-in name and is limited to 20 characters. The UPN
      (User Principal Name) is user@domain.
    - A random password is generated so no shared or guessable starter password exists. The user is then
      forced to choose their own. Hand out the first password through the helpdesk process, or use a reset link flow.

    PITFALLS
    - If the department OU or the SG- group does not exist the script fails for that user. Run 10 first.
    - The generated password must satisfy the domain password policy. It always starts with Aa1! and is 16 characters, which
      meets the lab policy of 12 and complexity.
    - A duplicate username is skipped, not updated. Use the mover script to change an existing user.

    EXPECTED OUTPUT
    A table with one row per person and a result of Created or Skipped. On the first run, 20 Created.
#>

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$domain      = Get-ADDomain
$domainDN    = $domain.DistinguishedName
$upnSuffix   = $domain.DNSRoot                  # CHANGE: leave as is, or set a different UPN suffix.
$staffOU     = "Staff"                          # CHANGE: the top OU that holds the department OUs.
$groupPrefix = "SG-"                            # CHANGE: your group naming prefix.
$passwordLength = 12                            # CHANGE: random part of the generated password.

# CHANGE: replace this list with your starters. For a file use: $people = Import-Csv "C:\path\new-starters.csv"
$csv = @"
FirstName,LastName,Username,Department,Title,Ticket
Maya,Johnson,mjohnson,Finance,Accountant,INC-1001
Daniel,Reyes,dreyes,Finance,Financial Analyst,INC-1002
Priya,Nair,pnair,Finance,Payroll Specialist,INC-1003
Omar,Haddad,ohaddad,Finance,AP Clerk,INC-1004
Grace,Lin,glin,Finance,Controller,INC-1005
Tasha,Brooks,tbrooks,HR,HR Generalist,INC-1006
Luis,Ortega,lortega,HR,Recruiter,INC-1007
Hannah,Weiss,hweiss,HR,Benefits Analyst,INC-1008
Marcus,Bell,mbell,HR,HR Manager,INC-1009
Aisha,Khan,akhan,HR,HR Coordinator,INC-1010
Ethan,Cole,ecole,IT,Help Desk Technician,INC-1011
Nina,Petrova,npetrova,IT,Systems Administrator,INC-1012
Jamal,Carter,jcarter,IT,Network Engineer,INC-1013
Sofia,Alvarez,salvarez,IT,Security Analyst,INC-1014
Kevin,Park,kpark,IT,IT Manager,INC-1015
Rhonda,Greer,rgreer,Operations,Operations Coordinator,INC-1016
Victor,Salazar,vsalazar,Operations,Dispatcher,INC-1017
Dana,Whitfield,dwhitfield,Operations,Facilities Lead,INC-1018
Leo,Fischer,lfischer,Operations,Operations Analyst,INC-1019
Tiana,Moore,tmoore,Operations,Operations Manager,INC-1020
"@
$people = $csv | ConvertFrom-Csv
# ============================================================================================

Import-Module ActiveDirectory

$passwordChars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#%^&*'.ToCharArray()
$results = @()

foreach ($person in $people) {
    if (Get-ADUser -Filter "SamAccountName -eq '$($person.Username)'") {
        $results += [pscustomobject]@{ Username = $person.Username; Department = $person.Department; Result = "Skipped (exists)" }
        continue
    }

    $randomPart = -join (1..$passwordLength | ForEach-Object { $passwordChars | Get-Random })
    $securePassword = ConvertTo-SecureString ("Aa1!" + $randomPart) -AsPlainText -Force

    New-ADUser `
        -Name "$($person.FirstName) $($person.LastName)" `
        -GivenName $person.FirstName `
        -Surname $person.LastName `
        -SamAccountName $person.Username `
        -UserPrincipalName "$($person.Username)@$upnSuffix" `
        -Department $person.Department `
        -Title $person.Title `
        -Description "Joiner ticket $($person.Ticket)" `
        -Path "OU=$($person.Department),OU=$staffOU,$domainDN" `
        -AccountPassword $securePassword `
        -Enabled $true `
        -ChangePasswordAtLogon $true

    Add-ADGroupMember -Identity "$groupPrefix$($person.Department)" -Members $person.Username

    $results += [pscustomobject]@{ Username = $person.Username; Department = $person.Department; Result = "Created" }
}

$results | Format-Table -AutoSize | Out-String

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@11-onboard-users.ps1" --query "value[0].message" -o tsv
# ANOTHER ENVIRONMENT: on a domain controller (or a server with RSAT), open PowerShell as a Domain Admin,
# replace the CSV in the CONFIGURATION block with your HR export, then run:
#   .\11-onboard-users.ps1
# TO VERIFY: Get-ADUser -Filter * -SearchBase "OU=Staff,$((Get-ADDomain).DistinguishedName)" | Measure-Object
