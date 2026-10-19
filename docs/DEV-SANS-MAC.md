# Développer MNetBox sans Mac

Depuis octobre 2026, le projet n'a plus de Mac. La chaîne est entièrement gratuite :

    code (Linux) → GitHub Actions macOS (build + tests + IPA) → Sideloadly (PC Windows) → iPhone

## 1. Modifier le code

- Ajout, suppression ou déplacement d'un fichier `.swift` : `node scripts/generate-project.mjs`.
- Avant chaque commit : `node scripts/check-source.mjs`.
- Le projet Xcode est généré : ne pas l'éditer à la main.

## 2. Compiler et tester (GitHub Actions)

Workflow `.github/workflows/ci.yml` :

- **À chaque push** : `check-source.mjs` sur Linux (quelques secondes).
- **À la demande** (Actions → CI → *Run workflow*) : job macOS avec trois options.
  - *Run unit tests* : tests unitaires sur le simulateur iPhone le plus récent.
  - *Run UI tests* : tests UI (longs, à lancer ponctuellement).
  - *Build unsigned IPA* : IPA Release non signé, en artefact `MNetBox-unsigned-ipa`.
- Logs et `.xcresult` : artefact `results` (conservé 7 jours).

**Quota.** Le dépôt est privé : 2 000 minutes gratuites par mois, et une minute macOS en compte 10. Un run tests unitaires + IPA dure environ 16 minutes, soit **une douzaine de runs par mois**. Ne lancer le job macOS que pour une version à tester.

**Xcode.** Les runners ont Xcode 26.x (SDK iOS 26.5), d'où la cible iOS 26.0. Le job sélectionne le Xcode le plus récent installé. Quand Xcode 27 sera disponible, la cible pourra remonter (`IPHONEOS_DEPLOYMENT_TARGET` dans `scripts/generate-project.mjs` et `scripts/check-source.mjs`).

## 3. Installer sur l'iPhone (Sideloadly)

Prérequis, une seule fois, sur le PC Windows :

- iTunes et iCloud **téléchargés sur le site d'Apple** (pas ceux du Microsoft Store) ;
- Sideloadly (sideloadly.io).

Sur l'iPhone, une seule fois :

- Réglages → Confidentialité et sécurité → **Mode développeur** activé ;
- après la première installation : Réglages → Général → VPN et gestion de l'appareil → faire confiance à son Apple ID.

À chaque version :

1. Télécharger l'artefact `MNetBox-unsigned-ipa` du run et le dézipper.
2. iPhone branché en USB, glisser l'IPA dans Sideloadly, saisir l'Apple ID, puis **Start**.

**Limites de l'Apple ID gratuit** : la signature expire au bout de **7 jours** (activer l'actualisation automatique de Sideloadly en Wi-Fi), et 3 apps au maximum. Si l'identité de signature change, le Keychain n'est plus lisible et il faut ressaisir la connexion NetBox.

## 4. Ce qui n'est plus possible

- Débogage interactif, Previews SwiftUI, tests UI en direct : on s'appuie sur la CI et sur les captures dans les `.xcresult`.
- Publication TestFlight/App Store : nécessite l'Apple Developer Program (payant).
