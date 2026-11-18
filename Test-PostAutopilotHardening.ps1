#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules BitLocker, NetSecurity, Dism
<#
.SYNOPSIS
    Controle en lecture seule du NIP de demarrage BitLocker et du blocage SSH sortant.

.DESCRIPTION
    Lit les protecteurs BitLocker du volume examine, la presence du client OpenSSH
    et les regles de pare-feu sortantes actives qui bloquent ssh.exe ou le port
    distant 22.

    Le controle BitLocker est conforme si un protecteur TpmPin ou TpmPinStartupKey
    existe et que ProtectionStatus vaut On.

    La colonne Conforme du client OpenSSH reste vide volontairement : sa presence
    peut etre legitime selon vos usages.

    Le controle du pare-feu interroge le magasin ActiveStore, qui reflete les
    regles effectives au moment de l'appel. Un resultat negatif signifie seulement
    qu'aucune regle locale correspondant aux deux criteres n'est active.

    Aucun reglage n'est modifie. Un CSV est ecrit seulement si -CsvPath est fourni.
    Cet export respecte -WhatIf et -Confirm.

.PARAMETER MountPoint
    Volume a examiner. Par defaut, le lecteur systeme ($env:SystemDrive).

.PARAMETER CsvPath
    Chemin facultatif du fichier CSV dans lequel exporter le resultat.
    Sans ce parametre, aucun fichier n'est ecrit.

.EXAMPLE
    .\Test-PostAutopilotHardening.ps1

    Controle le lecteur systeme et retourne un objet par controle.

.EXAMPLE
    .\Test-PostAutopilotHardening.ps1 | Format-Table -AutoSize -Wrap

    Affiche le resultat sous forme de tableau.

.EXAMPLE
    .\Test-PostAutopilotHardening.ps1 -CsvPath C:\Temp\controle-poste.csv

    Controle le lecteur systeme et exporte le resultat en CSV.

.EXAMPLE
    .\Test-PostAutopilotHardening.ps1 -CsvPath C:\Temp\controle-poste.csv -WhatIf

    Affiche l'export qui serait realise sans ecrire de fichier.

.EXAMPLE
    .\Test-PostAutopilotHardening.ps1 | Where-Object { $_.Conforme -eq $false }

    Retourne seulement les controles non conformes.

.INPUTS
    Aucune.

.OUTPUTS
    System.Management.Automation.PSCustomObject
    Proprietes : Poste, Controle, Conforme, Valeur, Detail.

.NOTES
    Version : 1.0.0
    Auteur  : Cedric Perion
    Licence : MIT
    Testez d'abord ce script sur un poste pilote.

.LINK
    https://trivium365.com/blog/apres-autopilot-controler-nip-bitlocker-blocage-ssh/
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([pscustomobject])]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$MountPoint = $env:SystemDrive,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath
)

$results = [System.Collections.Generic.List[object]]::new()
$computerName = $env:COMPUTERNAME

# 1. BitLocker : un protecteur TpmPin ou TpmPinStartupKey indique un NIP de demarrage
Write-Verbose "Lecture des protecteurs BitLocker du volume $MountPoint"
$volume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
$protectorTypes = @($volume.KeyProtector | ForEach-Object { $_.KeyProtectorType.ToString() })
$hasPin = @($protectorTypes | Where-Object { $_ -in @('TpmPin', 'TpmPinStartupKey') }).Count -gt 0
$isProtected = "$($volume.ProtectionStatus)" -eq 'On'
$results.Add([pscustomobject]@{
        Poste    = $computerName
        Controle = 'BitLocker : NIP de demarrage'
        Conforme = ($hasPin -and $isProtected)
        Valeur   = if ($protectorTypes.Count -gt 0) { $protectorTypes -join ', ' } else { 'Aucun protecteur' }
        Detail   = "VolumeStatus=$($volume.VolumeStatus); ProtectionStatus=$($volume.ProtectionStatus)"
    })

# 2. Client OpenSSH : capacite Windows et presence du binaire
Write-Verbose 'Lecture de la capacite Windows OpenSSH.Client'
$sshPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\OpenSSH\ssh.exe'
$capability = Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'OpenSSH.Client*' } |
    Select-Object -First 1
$results.Add([pscustomobject]@{
        Poste    = $computerName
        Controle = 'Client OpenSSH present'
        Conforme = $null
        Valeur   = if ($capability) { $capability.State.ToString() } else { 'Capacite introuvable' }
        Detail   = "ssh.exe present : $(Test-Path -Path $sshPath)"
    })

# 3. Pare-feu : regles sortantes actives (magasin effectif) qui bloquent SSH
Write-Verbose 'Lecture des regles de pare-feu sortantes actives du magasin ActiveStore'
$blockRules = @(Get-NetFirewallRule -PolicyStore ActiveStore -Direction Outbound -Action Block `
        -Enabled True -ErrorAction SilentlyContinue)
$sshRules = @(
    foreach ($rule in $blockRules) {
        $appFilter = $rule | Get-NetFirewallApplicationFilter
        $portFilter = $rule | Get-NetFirewallPortFilter
        $matchesProgram = @(@($appFilter.Program) -match 'ssh\.exe$').Count -gt 0
        $matchesPort = @($portFilter.RemotePort) -contains '22'
        if ($matchesProgram -or $matchesPort) {
            $rule.DisplayName
        }
    }
)
$results.Add([pscustomobject]@{
        Poste    = $computerName
        Controle = 'Pare-feu : blocage SSH sortant'
        Conforme = ($sshRules.Count -gt 0)
        Valeur   = "$($sshRules.Count) regle(s)"
        Detail   = ($sshRules -join '; ')
    })

Write-Output $results

if ($PSBoundParameters.ContainsKey('CsvPath')) {
    if ($PSCmdlet.ShouldProcess($CsvPath, 'Exporter le resultat du controle en CSV')) {
        $results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Verbose "Resultat exporte vers $CsvPath"
    }
}
