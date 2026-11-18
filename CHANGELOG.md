# Journal des modifications

Ce fichier suit le principe de la gestion sémantique de version.

## 1.0.0 (2026-11-03)

Première version publique.

- Contrôle du NIP de démarrage BitLocker : protecteur TpmPin ou TpmPinStartupKey avec ProtectionStatus à On.
- Inventaire du client OpenSSH : état de la capacité Windows OpenSSH.Client et présence de ssh.exe.
- Recherche des règles de pare-feu sortantes actives (magasin ActiveStore) qui bloquent ssh.exe ou le port distant 22.
- Sortie en objets PowerShell avec la propriété Poste.
- Export CSV facultatif avec le paramètre -CsvPath, compatible avec -WhatIf et -Confirm.
