# MNetBox

Client iPhone natif (SwiftUI) pour un serveur NetBox HTTPS. Version actuelle : **0.18.0 build 36**.
Cible iOS 26.0+, iPhone en portrait, interface français/anglais, aucune dépendance tierce.
Référence API : **NetBox 4.7.2**.

## Fonctionnalités

- **Connexion** : jetons NetBox v1 (`Token`) et v2 (`Bearer`), stockés dans le Keychain.
- **Dashboard** : six compteurs (sites, baies, équipements, VM, préfixes, IP).
- **Consultation** : inventaire, IPAM (dont plages d'IP), VLAN/groupes, MAC, câbles et contextes (VRF, tenants, rôles, régions…), recherche globale, **scan QR / code-barres**, journal NetBox, champs personnalisés, navigation entre objets liés.
- **Graphique** : élévations de baies, panneau de ports d'équipement, schémas et traces de câbles, images NetBox.
- **Écritures relues et confirmées** : champs texte et métadonnées, création IPAM/VLAN/contextes/interfaces, câbles réseau, console et alimentation (création, édition, recâblage, suppression), marque « connecté », **prochaine IP / prochain préfixe disponible**, IP assignée directement à une interface, **création d'équipement**, entrées de journal, suppressions contrôlées, ajout de photos.

Le détail des jalons est dans [docs/ROADMAP.md](docs/ROADMAP.md).

## Règles de sécurité (non négociables)

- Aucun jeton dans les fichiers, logs, fixtures ou la CI. Il se saisit uniquement dans l'app.
- HTTPS obligatoire, redirections refusées, session éphémère sans cache disque ni cookies.
- Les requêtes `PATCH`/`POST`/`DELETE` n'existent que dans `Core/Networking/APIClient.swift`.
- Chaque écriture suit le même modèle : snapshot frais avec ETag → relecture Avant/Après → confirmation explicite → une seule tentative avec `If-Match`, **jamais de nouvelle tentative automatique**.
- Les tests n'utilisent que des réponses synthétiques (`URLProtocol`, fixtures DEBUG) : aucune écriture automatisée sur NetBox.

Voir [SECURITY.md](SECURITY.md) et [docs/WRITES.md](docs/WRITES.md).

## Architecture

| Dossier | Rôle |
| --- | --- |
| `MNetBox/App` | Point d'entrée, restauration de connexion, fixtures DEBUG pour les tests UI |
| `MNetBox/Core/Networking` | `APIClient` (actor), requêtes confinées, pagination, erreurs, ETag, écritures typées |
| `MNetBox/Core/Security` | Stockage Keychain des identifiants |
| `MNetBox/Features/*` | Écrans par domaine : Connection, Shell, Dashboard, Inventory, IPAM, VLANs, MACs, Contexts, Racks, Interfaces, Images, Editing, Support |
| `MNetBox/DesignSystem` | Composants visuels, champs de détail, localisation |
| `MNetBox/Resources` | Catalogue de chaînes FR/EN, icône, manifeste de confidentialité |
| `MNetBoxTests` / `MNetBoxUITests` | Tests unitaires (229) et UI |
| `scripts/` | Génération du projet Xcode, contrôle des sources, icône |

## Développement

Pas de Mac : tout passe par GitHub Actions, puis installation par Sideloadly. Voir **[docs/DEV-SANS-MAC.md](docs/DEV-SANS-MAC.md)**.

En bref :

    node scripts/generate-project.mjs   # après ajout/déplacement d'un fichier .swift
    node scripts/check-source.mjs       # avant chaque commit

## Documentation

- [docs/ROADMAP.md](docs/ROADMAP.md) : définition et état des jalons
- [docs/WRITES.md](docs/WRITES.md) : comportement des écritures et recettes manuelles
- [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md), [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md), [docs/PRIVACY.md](docs/PRIVACY.md)

