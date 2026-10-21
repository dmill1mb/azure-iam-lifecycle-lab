<#
.SYNOPSIS
    Runs five LDAP (Lightweight Directory Access Protocol) searches against the directory to show how filters work.

.DESCRIPTION
    Defines a small function that sends an LDAP filter to the domain using the .NET directory searcher, then runs
    five filters: users in one department, users in either of two departments, users with a title containing
    Manager, members of one group, and disabled accounts. Prints the matches and a count for each.

.NOTES
    LAB: Lab 4, identity and access management (domain iamlab.local). Runs on DC01, after 11-onboard-users.ps1.

    RULES THIS SCRIPT FOLLOWS
    - It only reads. It changes nothing in the directory.
    - Each search prints its own filter, so the output explains itself.

    KNOWLEDGE
    - LDAP is the protocol applications use to query the directory. It uses port 389 (636 for LDAP over TLS).
      A SIEM, a VPN and many applications use the same filters you see here.
    - Filter grammar: ( ) groups, & means AND, | means OR, ! means NOT, * is a wildcard.
    - memberOf takes the group's full DN (distinguished name), not its short name. That is why this script builds it.
    - Disabled accounts are found with the bitwise matching rule 1.2.840.113556.1.4.803 against userAccountControl.
      The value 2 is the "account disabled" bit. The long number is the rule that tests a single bit.
    - Expected counts after a fresh onboarding: 5 Finance users, 10 HR or IT users, 3 managers, 5 members of SG-Finance,
      and 2 disabled (Guest and krbtgt, which Windows disables by default). The disabled count rises after 18-leaver-offboarding.ps1 is run for real.
    - memberOf only lists direct memberships, not nested groups.

    PITFALLS
    - A typo in a filter returns zero results and no error. Check spelling and the parentheses first.
    - Searching on department needs the Department field set. 11-onboard-users.ps1 sets it.
    - The wildcard in a title search is case-insensitive.

    EXPECTED OUTPUT
    Five sections, each with the filter, the matching people and a count.
#>

# ===================== CONFIGURATION: CHANGE THESE FOR YOUR ENVIRONMENT =====================
$domainDN  = (Get-ADDomain).DistinguishedName      # CHANGE: leave as is to search the current domain.
$groupsOU  = "Groups"                              # CHANGE: the OU that holds your groups.
$groupName = "SG-Finance"                          # CHANGE: the group used in the membership search.
$deptA     = "Finance"                             # CHANGE: department for searches 1 and 2.
$deptB     = "HR"                                  # CHANGE: second department for search 2.
$deptC     = "IT"                                  # CHANGE: third department for search 2.
$titleWord = "Manager"                             # CHANGE: word searched for in titles.
# ============================================================================================

function Invoke-LdapSearch {
    param([string]$Title, [string]$Filter)

    $searcher = [ADSISearcher]$Filter
    $searcher.SearchRoot = [ADSI]"LDAP://$domainDN"
    $searcher.PageSize = 1000
    [void]$searcher.PropertiesToLoad.Add("name")
    [void]$searcher.PropertiesToLoad.Add("samaccountname")
    [void]$searcher.PropertiesToLoad.Add("title")
    $found = $searcher.FindAll()

    "=== $Title ==="
    "Filter: $Filter"
    $rows = foreach ($item in $found) {
        [pscustomobject]@{
            Name     = "$($item.Properties['name'])"
            Username = "$($item.Properties['samaccountname'])"
            Title    = "$($item.Properties['title'])"
        }
    }
    $rows | Format-Table -AutoSize | Out-String -Width 200
    "Count: $(@($rows).Count)"
    ""
}

$groupDN = "CN=$groupName,OU=$groupsOU,$domainDN"

Invoke-LdapSearch "1. Users in $deptA" "(&(objectCategory=person)(objectClass=user)(department=$deptA))"
Invoke-LdapSearch "2. Users in $deptB or $deptC" "(&(objectCategory=person)(objectClass=user)(|(department=$deptB)(department=$deptC)))"
Invoke-LdapSearch "3. Titles containing $titleWord" "(&(objectCategory=person)(objectClass=user)(title=*$titleWord*))"
Invoke-LdapSearch "4. Members of $groupName" "(&(objectCategory=person)(objectClass=user)(memberOf=$groupDN))"
Invoke-LdapSearch "5. Disabled accounts" "(&(objectCategory=person)(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=2))"

# ===================== HOW TO RUN =====================
# LAB (Azure virtual machine, from your laptop, inside the scripts folder):
#   az login
#   az vm run-command invoke -g rg-iamlab -n DC01 --command-id RunPowerShellScript --scripts "@12-ldap-queries.ps1" --query "value[0].message" -o tsv
# ANOTHER ENVIRONMENT: on a domain-joined machine or a domain controller, open PowerShell, edit the CONFIGURATION
# block (department names, group name), then run:
#   .\12-ldap-queries.ps1
