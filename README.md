# PostAutopilotHardeningCheck

Contrôle en lecture seule d'un poste Windows : présence d'un NIP de démarrage BitLocker, présence du client OpenSSH et règles locales du pare-feu Windows qui bloquent SSH en sortie.

## À quoi sert l'outil

Beaucoup d'entreprises veulent un NIP de démarrage BitLocker. Ce NIP nuit toutefois à Autopilot : on compte donc sur les usagers pour le configurer une fois le poste préparé. Quand la configuration finale dépend d'une action de l'usager, la stratégie déployée ne suffit plus à décrire l'état réel du parc. Un poste chiffré avec le TPM seul peut sembler correct dans un rapport sommaire alors que le NIP attendu n'a jamais été ajouté.

Le script `Test-PostAutopilotHardening.ps1` lit l'état réel du poste pour mesurer cet écart. Il vérifie aussi si une règle locale du pare-feu Windows bloque SSH en sortie.

## Pourquoi maintenant

La newsletter Intune d'Andrew Taylor publiée le 16 octobre 2026 signale deux guides sur ces sujets : un script de Jorge Suarez pour aider les usagers à configurer le NIP après Autopilot et le guide de Jörgen Nilsson intitulé Block SSH using Windows Firewall. Elle rappelle que les applications qui s'exécutent dans cmd sont particulièrement difficiles à bloquer parce qu'elles sont signées par Microsoft. Elle qualifie aussi SSH de risque à ne pas laisser ouvert.

Cet outil ne présente pas une nouveauté Microsoft. Il sert à confirmer que ces réglages sont réellement appliqués sur un poste avant de conclure qu'ils le sont.

## Ce que l'outil vérifie

- BitLocker : NIP de démarrage. Le script lit les protecteurs du volume avec `Get-BitLockerVolume`. Le contrôle est conforme si un protecteur `TpmPin` ou `TpmPinStartupKey` existe et que `ProtectionStatus` vaut `On`.
- Client OpenSSH présent. Le script lit la capacité Windows `OpenSSH.Client` avec `Get-WindowsCapability -Online` et vérifie la présence de `ssh.exe` dans `%SystemRoot%\System32\OpenSSH`. La colonne Conforme reste vide volontairement : la présence du client peut être légitime selon vos usages.
- Pare-feu : blocage SSH sortant. Le script cherche dans le magasin `ActiveStore` les règles sortantes actives dont l'action est `Block` et qui visent le programme `ssh.exe` ou le port distant 22. Les filtres sont lus avec `Get-NetFirewallApplicationFilter` et `Get-NetFirewallPortFilter`.

L'outil ne modifie aucun réglage. Le seul fichier écrit est un CSV, uniquement si vous fournissez le paramètre `-CsvPath`. Cet export respecte `-WhatIf` et `-Confirm`. Aucune action ne touche un locataire Microsoft 365 : l'outil n'a donc pas de paramètre `-Apply`.

## Prérequis

- Windows PowerShell 5.1 sur un poste Windows où les modules BitLocker, NetSecurity et Dism sont disponibles. Ces modules Microsoft sont présents dans Windows.
- Une session élevée en administrateur local : `Get-BitLockerVolume` et `Get-WindowsCapability -Online` l'exigent.
- Aucun module Microsoft Graph, aucune permission Microsoft Graph ni aucun rôle Intune : le contrôle est entièrement local.

## Installation

1. Téléchargez le fichier `Test-PostAutopilotHardening.ps1` de ce dépôt sur un poste pilote.
2. Lisez le script avant de l'exécuter.
3. Ouvrez une console Windows PowerShell en tant qu'administrateur dans le dossier du script.

## Paramètres

- `-MountPoint` : volume à examiner. Par défaut, le lecteur système (`$env:SystemDrive`).
- `-CsvPath` : chemin facultatif pour exporter le résultat en CSV (encodage UTF8, sans ligne d'information de type).
- `-WhatIf` et `-Confirm` : s'appliquent uniquement à l'export CSV.
- `-Verbose` : affiche les étapes du contrôle.

## Exemples d'utilisation

```powershell
# Contrôle du lecteur système
.\Test-PostAutopilotHardening.ps1

# Affichage en tableau
.\Test-PostAutopilotHardening.ps1 | Format-Table -AutoSize -Wrap

# Contrôle d'un autre volume
.\Test-PostAutopilotHardening.ps1 -MountPoint D:

# Export du résultat en CSV
.\Test-PostAutopilotHardening.ps1 -CsvPath C:\Temp\controle-poste.csv

# Simulation de l'export sans écrire de fichier
.\Test-PostAutopilotHardening.ps1 -CsvPath C:\Temp\controle-poste.csv -WhatIf

# Seulement les contrôles non conformes
.\Test-PostAutopilotHardening.ps1 | Where-Object { $_.Conforme -eq $false }
```

Chaque contrôle produit un objet PowerShell avec les propriétés Poste, Controle, Conforme, Valeur et Detail. La propriété Poste facilite le regroupement de fichiers CSV recueillis sur plusieurs postes.

## Exemple de sortie

La sortie suivante est fictive. Elle montre seulement la forme du résultat attendu.

```text
Poste    : POSTE-FICTIF-01
Controle : BitLocker : NIP de demarrage
Conforme : False
Valeur   : Tpm, RecoveryPassword
Detail   : VolumeStatus=FullyEncrypted; ProtectionStatus=On

Poste    : POSTE-FICTIF-01
Controle : Client OpenSSH present
Conforme :
Valeur   : Installed
Detail   : ssh.exe present : True

Poste    : POSTE-FICTIF-01
Controle : Pare-feu : blocage SSH sortant
Conforme : False
Valeur   : 0 regle(s)
Detail   :
```

## Interpréter le résultat

- BitLocker non conforme avec un protecteur `Tpm` seul : le poste est chiffré mais le NIP attendu n'a pas été ajouté.
- Pare-feu non conforme : aucune règle locale correspondant aux deux critères n'est active sur le poste. Une organisation peut bloquer SSH autrement, par exemple sur un pare-feu réseau.
- Pour SSH, la décision est d'abord une question d'usage. Déterminez qui en a besoin avant de bloquer le binaire. Utilisez ensuite le script pour confirmer que la règle choisie est bien active sur les postes visés.

## Limites connues

- Le contrôle est local et ponctuel. Il ne remplace pas un rapport Intune sur l'ensemble du parc.
- Le magasin `ActiveStore` reflète les règles effectives au moment de l'appel. Une stratégie qui n'est pas encore appliquée n'y figure pas.
- La détection SSH se limite au programme `ssh.exe` et au port distant 22. Une règle basée sur un autre chemin, un autre port ou un pare-feu réseau ne sera pas détectée.
- Le protocole des règles qui visent le port distant 22 n'est pas vérifié.
- La colonne Conforme du client OpenSSH reste vide volontairement.
- L'outil ne configure pas le NIP de démarrage. Pour accompagner les usagers, la newsletter renvoie vers le script de Jorge Suarez cité plus bas. Lisez le billet original avant de l'adapter à votre environnement.
- Le script de l'article n'a pas été exécuté sur un parc par son auteur. Testez cet outil d'abord sur un poste pilote.

## Article et sources

- Article : [Après Autopilot : contrôler le NIP de démarrage BitLocker et le blocage SSH sur vos postes](https://trivium365.com/blog/apres-autopilot-controler-nip-bitlocker-blocage-ssh/)
- Source primaire : [Intune Newsletter du 16 octobre 2026](https://andrewstaylor.com/2026/10/16/intune-newsletter-16th-october-2026/) (Andrew Taylor)
- Script de Jorge Suarez : [BitLocker startup PIN after Autopilot](https://www.jorgeasaur.us/bitlocker-startup-pin-after-autopilot)

Sources Microsoft citées dans l'article, utiles pour le calendrier de vos postes mais sans lien direct avec cet outil :

- [Prepare for Windows Update certificate rotation in 2027](https://techcommunity.microsoft.com/t5/windows-it-pro-blog/prepare-for-windows-update-certificate-rotation-in-2027/ba-p/4562463) (blogue Windows IT Pro)
- [Preparing for end of support for CNAME auto discovery in Windows MDM only enrollment](https://techcommunity.microsoft.com/blog/IntuneCustomerSuccess/preparing-for-end-of-support-for-cname-auto-discovery-in-windows-mdm-only-enroll/4564973) (équipe de support Intune)

## Licence

Licence MIT. Voir le fichier LICENSE.


## Démonstration en vidéo

https://www.youtube.com/watch?v=QdpSZMHhdL8
