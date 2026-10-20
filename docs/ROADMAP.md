# MNetBox — Milestones

> **2026-10-19 — Reprise sans Mac.** Cible de déploiement abaissée de iOS 27 à iOS 26.0 : les runners GitHub Actions n'ont que Xcode 26.x. Compilation et tests via la CI, installation par Sideloadly ; voir [DEV-SANS-MAC.md](DEV-SANS-MAC.md). Les mentions « iOS 27 » ci-dessous décrivent la période précédente.

Scope agreed on 2026-10-03: a native SwiftUI iPhone app for iOS 27, linked navigation and graphical rack elevations with native icons/illustrations. No favorites. Preserve the existing API client, observable feature models and Keychain storage. All implemented and planned read-only features use GET; API credentials are entered only in the app and never written to files or logs.

## Feuille de route à partir d'octobre 2026

Livraisons plus grosses : chaque version regroupe plusieurs fonctionnalités, avec tests unitaires, scénarios UI et une suite UI complète avant publication. Toute écriture garde le même contrat : relecture Avant/Après, ETag, confirmation explicite, une seule tentative, jamais d'action implicite. La validation sur le vrai serveur reste faite par l'utilisateur.

| Version | Thème | Contenu |
| --- | --- | --- |
| **0.16.0 (34)** | Suppression de câble | Livrée et validée sur le serveur réel le 2026-10-20. |
| **0.17.0 (35)** | Câblage complet | Câbles console ↔ serveur console, alimentation ↔ prise ; édition relue du libellé, statut, type, couleur, description et commentaires d'un câble. |
| **0.18.0** | Grosse mise à jour (ex-0.18 → 0.21) | Voir les lots ci-dessous, livrés ensemble. |

**0.18.0 — lots, construits et testés l'un après l'autre, publiés ensemble :**

- **A. Câblage terrain** : recâblage relu d'une extrémité (ancienne → nouvelle, sans déconnexion implicite) ; longueur et unité ; actions rapides depuis le port sélectionné (ouvrir, modifier, supprimer son câble) ; bascule « marqué connecté ».
- **B. IPAM pratique** : prochaine IP et prochain préfixe disponibles (endpoints NetBox natifs) avec relecture ; assignation directe d'une nouvelle IP à une interface ; consultation des plages d'IP.
- **C. Inventaire terrain** : scan QR / code-barres (caméra, permission explicite) pour ouvrir un équipement par nom, n° de série ou asset tag ; création d'équipement relue ; tags et champs personnalisés en lecture.
- **D. Comptes et maintenance** : suppression de tenant (jalon 31) ; photos plus anciennes paginées ; journal NetBox (consultation et ajout) ; recette comptes restreints (jalon 30, manuelle).

Ordre interne indicatif : A → B → C → D. Un IPA de prévisualisation peut être fourni entre deux lots ; seule la version complète fait l'objet d'une Release.

**Reprise du lot A — 2026-10-20 :** recâblage, longueur/unité, accès au câble et marque de connexion implémentés ; tests de modèle et transport synthétique ajoutés. Validation Xcode/CI en cours. Le lot B commence par la consultation paginée des plages IP (implémentée, validation CI en attente). La création d’une IP directement assignée depuis une fiche d’interface physique/VM est implémentée, validation CI en attente. Allocation disponible reste à réaliser, ainsi que les lots C et D ; aucune Release 0.18.0 publiée.

Les détails historiques des jalons 0 à 34 suivent.

### 34b/34c — Câblage complet (0.17.0 build 35, implémenté ; validation réelle en attente)

Création graphique étendue aux ports console, serveur console, alimentation et prises, avec la matrice native NetBox 4.7 : console ↔ serveur console ou port avant/arrière, alimentation ↔ prise uniquement, interfaces ↔ interfaces ou ports avant/arrière. Le panneau de destination ne propose que les familles compatibles avec la source. La fiche câble permet de modifier le libellé (100 caractères, sans caractères de contrôle), le statut (connecté, prévu, en retrait), le type, la couleur, la description et les commentaires, un champ à la fois, via l'éditeur relu existant (PATCH d'un seul champ avec If-Match, valeurs hors liste refusées localement).

## 0 — Project foundations

Implemented and simulator-tested: app/unit/UI targets, shared scheme, SwiftUI shell and visual primitives. iOS 27 deployment target. Remaining distribution work is tracked in milestone 7.

## 1 — Secure connection

Implemented and simulator-tested: HTTPS-only client, credential validation, Keychain, restoration/disconnection, pagination, cancellation, safe errors and ETag/If-Match header infrastructure. The user accepted v1/v2 production login. Negative production cases and locked physical-device Keychain acceptance remain to be checked.

## 2 — Dashboard

Implemented, simulator-tested and accepted against production totals: Sites, Racks, Devices, Virtual machines, Prefixes and IP addresses; concurrent bounded count requests, independent errors and refresh.

## 3 — Read-only lists and details

Implemented, simulator-tested and user-accepted on the real server for all six collections: server search, status/family filters, 50-object pages, explicit pagination, refresh/retry and detail fields. Restricted-account, offline and physical-device acceptance remains pending.

## 4 — Linked navigation and graphical racks

Implemented, simulator-tested and user-accepted on the real server on 2026-10-03:

- Site → scoped Racks and Devices lists; rack → scoped Devices list.
- Rack/Device/VM → known parent Site, Rack or host Device when the API supplies a positive ID.
- Rack → native front/rear graphical elevation using GET /api/dcim/racks/{id}/elevation/.
- Clickable equipment in the elevation; half-unit positions, server ordering, full-depth occupancy as supplied by NetBox, and occupied spaces with restricted device visibility.
- Native SF Symbols and vector equipment/rack illustrations; no external image URLs or additional credential-bearing asset requests.
- All elevation pages are loaded before display; cycles, duplicate units, changing counts, incomplete responses and escaped next URLs fail safely.

Acceptance: compare both faces, unit numbering and mounted equipment with NetBox; follow Site → Rack → Device and parent links; check search/status filters and pagination stay scoped; try empty lists, permission errors, restricted occupied spaces and offline recovery. Reservations and unmounted/zero-U equipment are not represented by the elevation endpoint; use the related Devices list to inspect visible rack equipment.

## 5 — Interfaces and connections (implemented, read-only)

Device/VM interface lists and fresh details: hardware type (physical interfaces), enabled state, MTU, speed in kbps, primary/all MAC addresses, VLAN fields, assigned IP addresses and visible cable/peer relationships. Lists use bounded pages, search and enabled filters with a fixed parent ID. Cable details preserve all side-A/side-B terminations. Known interface types open by positive ID; other termination types remain readable labels. A full topology graph is outside this milestone. The user reported successful production testing on 2026-10-03; negative/physical-device cases remain pending.

Acceptance: compare representative physical/virtual interfaces, interfaces without cables or addresses, multi-termination links, restricted relations, pagination and failure recovery. No cable creation or interface editing.

## 6 — IPAM relationships and richer filtering (implemented, read-only)

Prefix → strictly contained prefixes and contained IP addresses with explicit VRF context; IP → its known assigned interface → Device/VM. Global VRF is explicitly requested as vrf_id=null; named VRFs retain their ID. Response VRF/assignment identity is checked before publishing context results. Additional filters cover VRF, tenant, prefix role and direct site scope; IP roles use the API choice values. Reference selection lists are searchable and paginated. Scope/search/filter values must survive next URLs. Network utilization is deferred until its definition is agreed and tested against NetBox; no percentage is inferred from visible counts. The user reported successful production testing on 2026-10-03; negative/physical-device cases remain pending.

Acceptance: IPv4/IPv6, overlapping addresses across VRFs, null VRF, empty networks, permission-filtered results and encoded CIDR pagination. Do not infer ownership solely from matching an address.

## 7 — Usability and distribution (implemented and simulator-tested; physical acceptance pending)

French/English catalog and system language selection, Dynamic Type detail layout, rack controls of at least 44 points, VoiceOver label/value support, light/dark appearance and original app icon. Release/signing/physical-iPhone checklist in RELEASE.md. Simulator and Release verification is recorded in README.md; physical-iPhone acceptance remains necessary. Human VoiceOver validation is deferred at the user’s request; existing accessibility labels are retained. Publishing/distribution requires a separate user request and configured developer account.

Acceptance: readable large text, accessible rack diagram and controls, secure storage while locked, restore/disconnect behavior on a physical phone, clean Release build, no test fixtures in Release and no secrets in release artifacts.

## 8 — Description writes (authorized; implemented and simulator-tested)

The user explicitly authorized production edits on 2026-10-03. Initial scope: descriptions on the six main collections only. Fresh GET pairs the object/version; typed detail PATCH sends only the changed description with If-Match. NetBox 4.7's weak timestamp ETag contract is supported. Target and Before/After are reviewed before explicit confirmation. Missing versions, permissions, conflicts and uncertain results fail safely; drafts remain in memory and no mutation retries automatically. See WRITES.md for exact behavior and production acceptance. The user confirmed successful production description edits with a write-enabled token on 2026-10-03.

Creation, deletion, assignment changes, interface/cable edits and bulk mutations are outside this milestone. Subsequent write milestones require their own agreed scope; no favorites are planned.


## 9 — Comments and DNS names (implemented and simulator-tested)

The Edit menu offers comments on all six main collections and DNS name on IP addresses. Each save reviews and sends exactly one selected field with a snapshot-bound If-Match. Comments preserve internal Markdown/newlines and have an app limit of 10,000 Unicode scalar code points; DNS names are validated against NetBox 4.7 syntax, normalized to lowercase and limited to 255 code points. Empty values clear the selected field. Addressing, assignments and relationships remain unchanged. The user confirmed real write testing on 2026-10-03; restricted-permission/conflict/offline and physical-device checks remain. See WRITES.md.

## 9b — Persistent bottom navigation (implemented, simulator-tested and user-accepted)

Requested after production write acceptance: Home, Inventory and IPAM tabs remain visible throughout linked browsing. Each section has its own navigation stack. Home returns directly to the dashboard; re-selecting a section returns to its root. Switching Inventory/IPAM retains the current detail/search/filter context. Editing stays in a modal review flow.

## 9c — Global search (implemented, simulator-tested and user-accepted)

A fourth bottom tab with a magnifying glass searches Sites, Racks, Devices, VMs, Prefixes and IP addresses using each collection's existing NetBox `q` filter. Results are grouped by collection, with independent counts, pagination and safe errors/retry. Empty input sends no search requests; input is trimmed and debounced, and replaced queries cancel old views/requests. Results open existing detail/edit flows. Switching tabs retains the search detail; re-selecting Search returns to an empty search root. No saved search history, favorites or additional write operations. The user confirmed real search acceptance on 2026-10-04.

## 10 — IPAM creation (implemented and simulator-tested; real creation acceptance pending)

Typed forms for new IPv4/IPv6 prefixes and IP addresses, status, explicit Global/named VRF and tenant/None, description/comments and IP-only DNS name. Prefix host bits are rejected rather than silently cleared. A visible duplicate check is scoped to the selected VRF (IPs compare host identity regardless of mask), repeated before one POST. The immutable normalized proposal is reviewed before confirmation. Returned identity/context/values are verified; permission, validation, uncertain and mismatched results retain drafts without a second attempt in the same editor. New objects can open by their returned positive ID; closing refreshes the originating list without clearing filters. Creation appears in global lists, not contained/assigned-object contexts. No bulk allocation, available-IP allocation endpoint, assignment, interface/cable write or automatic retry. Real-server creation acceptance remains pending; see WRITES.md.

## 11a — Device and VM names/statuses (implemented, simulator-tested and user-accepted)

Authorized on 2026-10-04, aligned to NetBox 4.7.2. Existing device/VM Edit menus offer one-field name or status changes with fresh GET/ETag, Before/After review and deliberate confirmation. Names have a 64-code-point limit; an empty Device name explicitly sends null, VM names are required, and line breaks/control characters are rejected. Standard statuses are collection-specific (VM includes Paused, Device includes Inventory); custom current statuses are preserved/readable without becoming an arbitrary write choice. Reply identity/value must match. Failures retain drafts and require reload/review; no automatic mutation retry. Parent details refresh after dismissal. No addressing, rack position or relationship fields are sent.

## 11b — Interface activation and MTU (implemented, simulator-tested and user-accepted)

Bundled with 11c at the user's request on 2026-10-04. Physical and VM interface details offer enabled-state and MTU edits, with one-field typed PATCH, fresh ETag, immutable Before/After review and confirmation. The fresh object and reply must retain the exact positive parent identity. Enabled sends a JSON boolean; MTU sends an integer in 1...65536 or explicit null. Draft validation rejects non-ASCII digits, decimals, signs and overflow. Empty MTU clears the NetBox field. Changes describe the interface in NetBox; hardware/guest configuration, cable, MAC, VLAN and IP assignment are not written. No automatic retry after failure/uncertainty.

## 11c — Inventory relationship writes (implemented, simulator-tested and user-accepted)

Device/VM tenant, role and platform editing uses scoped searchable/paginated GET selectors and exactly one numeric ID or null per PATCH. Device role is required; VM role, tenant and platform may be cleared. VM roles are filtered by vm_role=true, which persists in pagination and is checked in returned picker rows. The selected reference is freshly read before review and rechecked before mutation; wrong IDs, missing references and incompatible VM roles block writes. ETag protects the target object; NetBox remains authoritative for permissions, reference constraints and concurrent reference changes. No site/rack/position, host/cluster, primary-IP or other assignment changes are added. Errors retain drafts and require explicit reload/review.

## 12 — IPAM editing, primary IPs and interface creation (implemented, simulator-tested and user-accepted)

Authorized on 2026-10-04. Prefix/IP status and tenant changes reuse the snapshot-bound review editor. IP assignment writes only the atomic assigned_object_type/assigned_object_id pair (physical or VM interface), or two nulls to detach. A searchable parent selector scopes interface choices; fresh interface reads verify parent identity. Device/VM primary IPv4/IPv6 choices are scoped to directly assigned interfaces on that exact parent and the matching family, checked again before PATCH. Clearing a primary IP sends one null. No address, prefix mask, VRF or implicit relationship cleanup is sent. NetBox may refuse detaching a primary IP; clear its primary designation deliberately first.

Physical/VM interface creation is scoped to an existing parent. Fields: name (1–64 Unicode scalars), enabled, optional MTU (1...65536), description, and physical-only type. Initial physical types are virtual, 1000base-t, 10gbase-x-sfpp, lag and other; other types are created in NetBox. Parent and visible exact-name duplicates are checked at review and again before one POST. One creation attempt per editor; uncertain/mismatched replies retain the draft and provide a scoped existing-object list. No automatic retry, cable/VLAN/MAC write or VM/host operating command.

An external synchronization may own some fields. ETags detect a changed target; they cannot prevent a later synchronization from overwriting fields owned by that script. Verify persistence after its next run. No synchronization code is modified here.

## 13 — Controlled deletion (implemented, simulator-tested and user-accepted)

Authorized on 2026-10-04 for IPs, prefixes and physical/VM interfaces. Exact server/object/ID/VRF or parent review, typed ID confirmation, paired ETag and visible dependency checks repeated immediately before DELETE. IPs must be unassigned and have no visible primary, OOB, FHRP or NAT relationships; prefixes must have no visible children, IPs or ranges; interfaces must be free of the inspected IP/MAC/cable/VLAN/VRF/parent/bridge/LAG/module/wireless/FHRP/L2VPN dependencies. Missing metadata and permission failures block confirmation. No automatic detachment or bulk deletion. One attempt per editor, only empty HTTP 204 confirms deletion, GET-only outcome checks after uncertainty. Closing a successful editor pops the detail and refreshes its originating IPAM/interface list. Other search/context lists may need refresh. Hidden dependencies and related-object races remain subject to NetBox permissions/constraints. External synchronization may recreate an object.

The user accepted normal production deletion testing on 2026-10-04. Negative permissions/conflict/offline cases and synchronization recreation remain useful checks.

## 14 — Interface text/type editing and app version (implemented, simulator-tested and user-accepted)

Authorized on 2026-10-04 after milestone 13 acceptance. Physical/VM interface names and descriptions, plus physical-only type, use the existing typed single-field editor with exact parent identity, fresh GET/ETag, Before/After review and deliberate confirmation. Names are required and limited to 64 Unicode scalars; descriptions to 200, with empty clearing. The initial type choices are shared with creation: Virtual, 1000BASE-T, 10GBASE-X SFP+, LAG and Other. Other current types remain readable; selecting a supported type is required for a type mutation. One selected field per PATCH; NetBox validates uniqueness and type/dependency constraints. No automatic retry or relationship cleanup.

Dashboard shows the actual installed bundle version and build near its connection status. This lot is version 0.2.0, build 14. The generator preserves the sole existing version/build and Team. The user accepted interface edits on 2026-10-04; persistence after external synchronization remains to verify.

## 15 — Interface VLAN configuration and direct field editing (implemented, simulator-tested and user-accepted)

Authorized on 2026-10-04. Physical/VM interface VLAN mode, untagged VLAN and tagged VLANs form one atomic, typed PATCH with paired If-Match, exact interface/parent identity and immutable Before/After review. Modes: routed (no VLANs), access, tagged and tagged-all. Changing mode preserves selections; incompatible VLANs must be removed explicitly before review. Selectors are searchable/paginated, separated into the parent's site and Global; a parent with no site offers Global only. Fresh parent-site and VLAN reads repeat before mutation. Unsupported modes, QinQ, translation policies or missing metadata block this editor. NetBox remains authoritative for custom validation and related-object races. No MAC/cable/host commands, VLAN-object creation/deletion or topology cleanup.

Editable rows on Inventory, IPAM and Interface details show a pencil and open their existing review editor directly. The Edit menu remains available. Empty descriptions/comments can also be edited. Address, mask, VRF and other unsupported fields stay read-only. Version 0.3.0, build 15.

IP assignment correction: before removing or changing the parent, read the original assigned interface and its parent primary/OOB designations. A designation blocks review/PATCH with a useful message; moving between interfaces on the same parent is permitted. Clear a primary designation deliberately on its Device/VM first; OOB is managed in NetBox. Known server validation failures are translated to static messages, without exposing response bodies or implicitly clearing another object.

Production acceptance: verify detachment after intentional primary clearing, field-tap/Cancel/review, physical site/global VLAN choices and VM Global-only choices when no site is set, before/after clearing, incompatible/unsupported configurations, permissions/conflicts and persistence after external synchronization. No automated production mutations.

## 16 — VLAN browsing and linked IPAM navigation (implemented, simulator-tested and user-accepted)

Authorized on 2026-10-04. Searchable, paginated VLAN and VLAN-group lists/details in IPAM and global search. VLAN filters: status, direct site (including explicit no direct site), group (including ungrouped), tenant and role. Fixed site/group navigation cannot change context during pagination. VLAN identity uses the object ID; the VID can recur across groups. Groups display inclusive VID ranges, server utilization and all returned scope labels. Only recognized site/rack scope identities open existing inventory details; cluster/region/location/plugin scopes remain readable.

VLAN details link to prefixes and explicitly assigned physical/VM interfaces, site, group and QinQ S-VLAN. Prefixes, interfaces and site details link back into VLAN browsing. Linked prefix/interface pages verify the positive VLAN relationship. Tagged-all interfaces are not implicitly included; the screen explains this limitation. Unknown choice labels remain readable. VLAN and group objects are read-only; existing reviewed interface editors retain their prior scope. No production writes during automated validation. Version 0.4.0, build 16. Compatibility baseline is NetBox 4.7.2; broader version compatibility is not claimed. Validation: 118 unit tests and nine distinct targeted UI scenarios pass after correcting one synthetic utilization representation and one new UI selector. Debug, unsigned Release archive and signed iPhone builds pass. Installed on the physical iPhone over localNetwork transport; remote launch was refused because it was locked. Manual real-data VLAN/group browsing, restricted accounts and other NetBox installations remain to verify.

The user accepted milestones 15–16 and confirmed the primary-IP constraint on 2026-10-04. Negative permission/conflict/offline tests and external synchronization persistence remain useful real-world checks.

## 17 — Distribution preparation and compatibility (implemented; public distribution pending)

Version 0.5.0 build 18. Fresh connection starts with an empty server URL; saved Keychain restoration is preserved. Offline/connected information pages show installed app/iOS versions, the NetBox version read from status, and the 4.7.2 reference. Other versions are visibly unverified. Optional diagnostics have a visible preview and a strict whitelist of technical versions: no URL, token, account, object IDs or inventory. Native sharing is user initiated. Privacy manifest and draft privacy/distribution metadata are included; public contact/policy URLs, developer distribution account, broader compatibility matrix and App Store declarations remain to finalize. No publication/upload is performed. See COMPATIBILITY.md, PRIVACY.md and DISTRIBUTION.md.

## 18 — Wider inventory and IPAM contexts (implemented; real-data acceptance pending)

Read-only, searchable, paginated VRF, tenant, IPAM-role, cluster, location, region, site-group, rack-group and cluster-group directories/details, also in global search. Linked inventory/IPAM lists retain their exact context and positive IDs, including reused names and overlapping prefixes. Region/site-group/location inventory includes descendants with bounded ancestry verification; prefix scope is exact. VLAN groups open all recognized supported scope destinations. Unknown/plugin scopes stay readable. Category-local permission errors leave other categories usable. Existing reviewed writes are preserved; no new object writes.

Dashboard redesign in the same lot: six colored cards, prominent counts, native symbols, numeric transitions respecting Reduce Motion, retained totals during refresh, individual errors and last-check time. Cards adapt to one column at accessibility text sizes and system appearance. No fabricated history or utilization charts are inferred from counts.

Validation for lot 17–18: 131 unit tests and 14 distinct targeted UI scenarios pass; final Debug, unsigned Release archive and signed iPhone builds pass. Release excludes DEBUG fixtures and includes the privacy manifest. Installed wirelessly without launching the locked phone. Real-data acceptance and public distribution remain pending; see RELEASE.md.

## 19a — VLAN creation and field editing (implemented and user-accepted)

Version 0.6.0 build 19, authorized on 2026-10-04. Global VLAN lists offer reviewed creation with VID 1–4094, required name (64 Unicode scalars), active/reserved/deprecated status, nullable site/group/tenant/IPAM role, description and comments. Fresh selected-reference reads, group VID ranges and supported site/group checks run before review and again before one POST. Visible group VID/name duplicates are blocked; ungrouped advisory duplicate checks use the selected direct site. NetBox remains authoritative for uniqueness, custom validation, group membership and related-object races. Failed/uncertain creation retains the draft and permits no second attempt in the same form. Returned positive identity, exact fields and null references are verified.

VLAN details offer direct name/status/description/comments/tenant/IPAM-role editing through existing one-field reviewed PATCH flows with paired ETag. Existing VID, site and group remain read-only after creation; group creation/editing, QinQ, translations and VLAN deletion require subsequent scope. Context lists retain their original filters and do not offer unrestricted creation. No switch commands are sent.

## 19b — MAC administration (implemented and user-accepted)

Searchable/paginated MAC directory in Inventory and global search, assigned-MAC lists from physical/VM interfaces, fresh details and links back to interfaces. Reused addresses retain distinct object IDs. New MAC creation is scoped to an exact interface/parent and checks visible duplicates on that interface; 48-bit colon, hyphen, Cisco dotted or compact values normalize to uppercase colon format. Description/comments are editable through existing text editors. Primary MAC selection/clearing sends only primary_mac_address ID/null, verified as assigned to that exact interface. Assignment changes send both type and ID together or both null; only physical and VM interfaces are offered. Fresh original-interface designation checks block moving/detaching a primary MAC. Clearing the primary designation is an explicit separate edit; no implicit detachment, deletion or hardware change. ETags, Before/After review, one-attempt/reload behavior and static error messages are preserved. Server constraints govern related-object races. Unsupported/plugin assignment types stay readable, not editable. No MAC deletion or address replacement in this lot.

Lot 19 validation: 143 unit tests and eight distinct targeted UI scenarios pass after fixture/selector synchronization corrections. Final Debug, unsigned Release and signed iPhone builds pass; the user accepted normal production testing on 2026-10-04. See RELEASE.md for result bundles.

## 20 — VLAN groups and controlled layer-2 deletion (implemented and user-accepted)

Version 0.7.0 build 20: reviewed VLAN-group creation with name/slug, non-overlapping VID ranges (1–4094), optional tenant and explicit Global or one of eight supported scope types. Positive scope/tenant references are freshly resolved; bounded exact-name/slug duplicate checks distinguish object IDs and scopes. Name (100 Unicode scalars), description and comments are directly editable from group details through the existing one-field ETag editor. Existing slug, tenant, ranges and scope remain read-only.

VLAN deletion requires complete fresh dependency metadata and visible prefix, physical/VM interface and QinQ-customer checks, blocking QinQ roles/relationships and L2VPN termination. MAC deletion requires an unassigned, nonprimary object and visible primary-reference checks on both interface collections. Review and decimal object-ID confirmation, fresh repeated checks, paired If-Match and one DELETE attempt; only empty HTTP 204 confirms success. Closing success pops the detail and refreshes the originating list/search. No group deletion, bulk or implicit dependency cleanup; hidden/plugin dependencies and concurrent reference changes remain subject to server permissions/constraints.

Validation: 152 unit tests and four distinct targeted UI scenarios pass. Simulator Debug, unsigned Release archive and signed iPhone builds pass. Installed on the habitual simulator and paired iPhone without a remote phone launch. Group ranges/scope moves and existing VLAN VID/site/group moves need dedicated future validation.

## 21 — Prefix relationships (implemented and user-accepted)

Bundled delivery 21–23, version 0.8.0 build 23. Prefix details directly edit VLAN and IPAM-role ID/null, or one atomic scope_type/scope_id pair. Scopes: Global, Region, Site group, Site and Location, matching NetBox 4.7.2's location scope contract. Searchable reference selectors use fixed paths and fresh positive identity checks. Before/After review, paired ETag, exact reply values/identity and preserved CIDR/VRF/other metadata remain mandatory. Unknown/plugin scopes remain readable and are not editable here. Failure/uncertainty keeps the draft and requires reload/review; no mutation retry or dependent-object cleanup.

## 22 — Guarded address and VRF editing (implemented and user-accepted)

Separate reviewed one-field prefix/address or VRF ID/null changes on prefixes/IPs. CIDRs normalize numerically, network host bits and /0 masks are rejected, family stays unchanged. A prefix must have no visible contained prefixes, IPs or ranges; an IP must be unassigned, free of NAT/primary/OOB/FHRP dependencies. Full fresh metadata and existing dependency checks run at review and again before PATCH. Destination checks distinguish exact prefixes from legitimate enclosing parents, exclude the edited object's ID and compare duplicate IP hosts independently of masks within the exact Global/named VRF. An expanded/moved prefix cannot absorb existing children/IPs/ranges. No renumbering or movement of other objects. The app blocks visible duplicate CIDRs even when a server permits them; hidden/plugin references and concurrent related-object changes remain subject to server validation. Assigned/primary IP renumbering, family conversion and bulk migration require future scope.

## 23 — Cable directory and graphical connections (implemented and user-accepted)

Refines the earlier proposed topology milestone into GET-only cable browsing: Inventory directory, device-scoped lists and global search; search, status and unterminated filters, explicit pagination and preserved query/context. Fresh details display a native A ↔ B diagram with all visible terminations, device labels, clickable known interface identities, metadata/comments/tenant/bundle and existing side lists. Multiple terminations are retained without inventing pairings. Unknown/patch-panel/plugin types stay readable. Accessibility text sizes stack the sides vertically. Missing termination arrays or mismatched IDs fail safely; category-local errors leave other collections usable. The graph represents one cable, not an end-to-end trace. No cable/port mutation or physical configuration command.

Lot 21–23 validation and deployment are recorded in RELEASE.md. Manual acceptance follows WRITES.md and COMPATIBILITY.md. Public distribution still requires milestone 17's account/privacy/contact work.

## 24 — VLAN identity and group evolution (implemented and user-accepted)

Version 0.9.0 build 24. VLAN details and Edit menus offer reviewed single-field VID, site and group changes. Full fresh metadata, paired ETag, positive references, group VID ranges and direct Site/Site-group compatibility are mandatory. Only VLANs without visible prefix, interface, QinQ or L2VPN dependencies can change these identity fields. Visible VID/name duplicates are checked in the destination group, or direct site for ungrouped VLANs, across bounded pages, excluding only the exact target ID.

Group details offer slug, tenant, VID ranges and atomic scope_type/scope_id changes. Slugs remain required ASCII letters/digits/hyphen/underscore, at most 100 characters. Scope-aware exact name/slug checks preserve all filters across pagination. Tenant and all eight supported scope references are freshly resolved. Range changes load every visible member with count/ID/group checks and reject excluding any member VID. Scope changes require an empty group, a deliberately conservative restriction. Unknown/plugin scopes remain readable; their scope cannot be edited. No automatic member movement, renumbering, dependency cleanup, bulk requests or switch configuration changes.

Before/After review and explicit confirmation, target/version/metadata recheck, repeated reference/dependency checks and exact reply field/identity verification reuse the existing architecture. Failed/uncertain mutations retain drafts and require deliberate reload/review; no automatic retry. Visible optimistic checks cannot lock related objects or prove absence of hidden/plugin dependencies; NetBox remains authoritative. Milestones 21–23 were accepted by the user before this delivery. Validation: 172 unit tests and four distinct targeted UI scenarios pass; Debug, unsigned Release and signed iPhone builds pass. Installed on the habitual simulator and paired iPhone, without remote phone launch or physical automated tests. See RELEASE.md and WRITES.md.

## 25a — Context creation and metadata (implemented; real-data acceptance pending)

Version 0.10.0 build 25. Global VRF, tenant and IPAM-role directories offer reviewed creation. VRFs: required name, nullable RD/tenant, enforce_unique, description/comments; route targets start empty. Tenants: name/slug, nullable tenant group, description/comments. IPAM roles: name/slug, portable integer weight (0–32767), description/comments. Required names/slugs have a 100-code-point limit; RD follows NetBox's 21-character text limit and may be cleared on creation. Fresh fixed-path references and bounded exact duplicate checks are repeated before one POST. Tenant uniqueness uses the exact group ID/null. The app conservatively blocks a reused visible VRF name even though NetBox allows it; nonempty RDs are checked separately. Failed/uncertain creation permits one attempt and retains the draft for inspection.

Direct field editing and an Edit menu support name/description/comments on all three, VRF tenant, tenant slug/group and role slug/weight. Each PATCH has one typed field, a fresh paired ETag, Before/After review, repeated reference/uniqueness checks and preserved modeled routing/context metadata. Existing RD, uniqueness and route-target changes are excluded; no network configuration is sent. Replies must match positive identity and proposal. Failure/uncertainty requires explicit reload/review and never retries automatically. Milestone 24 was accepted by the user before this lot.

## 25b — Guarded context deletion (VRF/IPAM-role implemented; tenant proposed)

VLAN-group deletion is implemented separately in 0.10.1 build 26 at the user's request: full group metadata/ETag, complete confined member enumeration, repeated pre-delete checks and exact ID confirmation; only empty groups can be deleted. The user accepted real-server VLAN-group deletion on 2026-10-05. Build 30 implements guarded VRF and IPAM-role deletion. Fresh full modeled metadata, explicit nonnegative native counters and ETag are required. VRFs check prefixes, IP addresses, ranges, physical and VM interfaces, and block any import/export route target. Roles check prefixes, VLANs, IP ranges and ASNs (the ASN relation exists in 4.7.2). Each fixed filtered dependency page validates positive IDs and exact returned VRF/role references, count/shape and confined next link. Repeat all checks before one DELETE with If-Match after exact ID confirmation. Counters with any dependency block even when filtered collections hide it. No application detachment, cascade request or retry. Related-object races and hidden/plugin relationships remain governed by NetBox; visible checks cannot prove global absence. Tenant deletion remains proposed pending its much broader native dependency contract.

### Visual details and automatic NetBox images — accompanying 25a

Context details use native colored headers and metric cards only for counts returned by the API. Inventory details add native equipment/site/rack/VM headers. Existing linked navigation is preserved. Site/rack/device/VM details automatically read the first four image attachments, confined to the exact object type/ID; devices also read front/rear pictures from their exact positive device-type ID. Tap opens a larger thumbnail. The gallery explains empty, partial, protected and unavailable images; missing pictures retain native visuals. Additional attachments remain available in NetBox.

Only HTTPS media under the configured application's /media/ path and the same origin is fetched. API tokens remain on API requests and are never attached to media; cookies, redirects, external/signed-query URLs, SVG/HTML and unbounded raster data are unsupported. At most 8 MiB per image, 40 million source pixels and 1200-pixel thumbnails; first frame only for animated files. Images stay in memory with ephemeral transport and cancellation; no tracking, web image search, public catalog lookup, upload or persistent cache. Private media requiring browser login can remain unavailable.

## 26a — Physical cable tracing and authenticated images (implemented; build 29 correction user-accepted)

Version 0.11.0 build 27 adds Interface → Cable trace for physical interfaces. The native sequence preserves near/far endpoint arrays, patch-panel internal steps, cable status and links to cables/interfaces/devices. JSON comes from the fixed interface trace endpoint; empty/partial/split paths are explained without claiming complete reachability or IP/VM topology. Exact same-origin native endpoint identity, 64-step/32-endpoint limits and repeated cable rejection protect rendering.

Protected native media now receives the existing v1/v2 token only within the two native same-origin image directories. Separate ephemeral/no-cookie/no-redirect transport and raster bounds remain. This supersedes the build-25 credentialless-media limitation; nothing is uploaded or obtained from public catalogs.

## 26b — Passive port details (implemented; real-data acceptance pending)

Version 0.12.0 build 28 adds front/rear port sheets reached from cable trace, showing type, positions, descriptions, parent device/cable and explicit bidirectional position mappings. Details validate exact IDs/parent and port kind. GET only; unknown/plugin port families and cable/port writes remain separate.

## 27 — Reviewed image attachments (implemented; photo upload user-tested, refinements in 28a)

From site/rack/device/VM details, choose one photo using PhotosPicker, enter its name/description, review the exact fresh target and normalized JPEG preview, then confirm one multipart POST. Oriented image pixels are downsampled to <=2048 pixels and re-encoded without source EXIF/GPS; local source capped at 20 MiB/100M pixels, final upload <=8 MiB. Immutable review, fresh parent checks, exact positive reply and one attempt/no retry retain the draft on uncertainty. Closing refreshes the gallery; newest four attachments are shown so the new addition is visible. Original Photos asset remains unchanged. No photo capture, bulk upload, replacement/deletion or device-type front/rear mutation.

## 28a — Image management and native trace compatibility (implemented; user-accepted on 2026-10-05)

Version 0.12.1 build 29. Attached photos on sites/racks/devices/VMs expose Delete image. Reuse the guarded deletion flow: exact parent type/ID, full fresh attachment metadata, valid ETag, exact decimal ID confirmation, repeated parent/attachment checks and one DELETE with If-Match. Only empty 204 confirms deletion; uncertain outcomes are retained and never automatically retried. Device-type front/rear images are shared and have no delete action here.

PhotosPicker requests current encoding. PNG sources and pixels with alpha are re-encoded as PNG, preserving transparency; opaque photos otherwise use JPEG. Fixed filename extension and MIME match the prepared pixels. Metadata stripping, orientation, 2048-pixel/8-MiB bounds remain. Preview and gallery show a native checkerboard to distinguish transparent edges. This supersedes milestone 27's JPEG-only/no-deletion limitation.

Trace decoding now follows the 4.7.2 trace contract rather than full cable details: raw status string, ignored raw length-unit field, empty [] internal links as well as null. Exact native circuit-termination/site/provider-network URLs can produce labels without a device; device ports still require a positive device. Arbitrary/external endpoints remain rejected. Existing cable and passive-port navigation is preserved. This corrects the reported eth0 decoding failure; The user accepted the build-29 tests on 2026-10-05.

## 28b — Broader native port compatibility (implemented; real-data acceptance pending)

Build 30 adds read-only console, console-server, power-port and power-outlet detail views and native trace from these four PathEndpointMixin endpoints. Type/label/description, console speed, declared power draw, feed leg/status and associated power-port link appear when returned. Device and cable links retain positive exact parent checks. Trace navigation opens these details; native power-feed endpoints without devices are displayed as labels. Front/rear ports use their existing position-mapping details: NetBox exposes paths rather than trace on these pass-through families, so no incorrect trace request is added.

## 29 — Device port directory (implemented; real-data acceptance pending)

Device → Ports exposes six native families with icons, search, 50-item pagination, counts, refresh/empty/error states, and detail navigation. Every returned port must belong to the exact device. Collection, device filter, search, ordering and limit are preserved across confined pagination. A synthetic 51-port scenario verifies Load more. Read only; no connector, cable, power, module or port configuration mutation.

## 30 — Distribution and restricted-account validation (planned)

Bundle the next compatibility pass around real restricted-account permissions, plugin/unknown data and device coverage, followed by packaging/document review. Personal Team installation continues; TestFlight/App Store requires a suitable developer account and explicit publication request. No publication is claimed by local deployment.

## 31 — Tenant dependency contract and extended media browsing (planned)

Guarded tenant deletion requires the complete native dependency families, including objects outside current browsing; this remains separate. Extend attachment browsing beyond the four newest previews with explicit scoped pagination before enabling management of older photos.

## IPAM ordering correction — 2026-10-04

Removed explicit ID ordering from IP-address collection requests so NetBox 4.7.2's numeric host/family ordering with ID tie-breaker applies, independent of masks. Prefix requests use prefix,id ordering. Subsequent pages must preserve the same ordering policy, filters and context. No client-side sorting of partial pages and no production mutation.


## 32 — Graphical device port panel (implemented and user-accepted)

Version 0.14.1 build 32 refines Device → Port panel (also reachable from Device → Ports) into a compact two-row horizontal panel inspired by common switch front panels. It renders only exact-device collection records, without padding missing numbers or generating device-type template slots. Scoped discovery hides empty families and reports failures separately. One actual family at a time: interfaces, front/rear, console/server-console, power ports/outlets.

A tap selects the actual record, outlines the connector and shows its full name, documented state, declared type and cable identity below. Open port details uses the existing typed detail and reviewed editors. Compact labels display the existing name's trailing digits, or its name when no trailing digits exist; full names remain in accessibility labels and selection details. No operational telemetry, CPU, PoE wattage or traffic is invented.

Colors describe NetBox metadata only: disabled administratively, a declared cable, explicit null cable, or unknown when the field is absent. Loaded counters, local state filtering and Load more explain partial pages. Search/pagination retain exact device ID, fixed collection, name/id ordering and 50-item limit. Natural numeric ordering applies to loaded names, not unloaded pages or manufacturer coordinates. Returning from details refreshes metadata. Automated tests are synthetic; real-device acceptance remains necessary. This view is GET-only.

## 33 — Graphical cable creation (implemented; real-write acceptance pending)

Version 0.15.0 build 33 removes the former Device → Ports directory/list views. The graphical Port panel retains native port details and tracing. From a documented free physical network interface or front/rear port, Connect a cable opens a visual A ↔ B proposal. Destination equipment uses existing searchable/paged references; its actual data ports use the graphical panel. Selected names, cable color, optional label (100 scalars), explicit common type or unspecified, and Connected/Planned status are reviewed before confirmation.

Each side contains one typed positive termination. Exact same port is forbidden; IDs reused across distinct model types remain distinct. Fresh positive devices and full endpoint identity/name/parent, explicit cable/null, _occupied and mark_connected are checked at review and repeated before one fixed dcim/cables POST. Virtual/LAG/bridge/wireless/channel interfaces are excluded; channel subinterfaces also fail fresh validation. Strict HTTP 201, exact positive cable identity, both typed sides and proposed metadata are required. Server validation remains authoritative for concurrent endpoint changes. Failed or uncertain saves retain the proposal, disable retries in that form and require checking NetBox before restarting. No endpoint detachment, overwrite, guessed pairing, automatic physical-device test or production mutation by automation.

## 34 — Cable lifecycle and broader wiring (34a implemented; rest planned)

Extend graphical creation to console/server-console and power-port/outlet/feed only with native compatibility rules and readable role-specific choices. Add reviewed cable deletion and, separately, reviewed rewiring with fresh complete termination/ETag contracts; no implicit disconnection. Improve cable visualization from actual peer metadata. Milestones 30 and 31 remain open for restricted accounts, distribution, tenant dependencies and older-photo browsing.

### 34a — Reviewed cable deletion (implemented 2026-10-19; real-write acceptance pending)

Cable detail → trash opens the shared deletion flow for `dcim/cables/{id}/`. The review shows server, cable title, ID and every visible A/B end (owner · port). Label, type, status, color and sorted typed terminations are bound to the review together with the ETag; any change before confirmation is a conflict. Exact decimal ID confirmation, one DELETE with If-Match, empty 204 only, no automatic retry. Only the cable record is deleted: NetBox clears endpoint occupancy and recomputes paths; no port or device configuration is changed. Returning refreshes the originating list, interface or port detail. Rewiring and console/power creation remain planned.
