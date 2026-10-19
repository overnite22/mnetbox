# Milestone 8 — Description editing

## VLAN-group deletion — 0.10.1 build 26

IPAM → VLAN groups → group detail → trash. Review server/name/slug/scope and exact positive object ID, then type that decimal ID to confirm. The group must be empty: its full API metadata/count, ETag and every visible member page are checked at review and again before one DELETE with If-Match. Mismatched counts, wrong member groups, malformed pagination, inaccessible checks or changed modeled metadata block deletion. Nothing is detached or migrated; only empty HTTP 204 confirms success. Cancel leaves the group unchanged. Closing confirmed success returns to and refreshes the originating list/search while retaining filters. Uncertain outcomes retain one attempt and offer GET-only inspection, never a retry.

Manual acceptance: create/select a deliberately disposable empty group, cancel once, then delete by exact ID and compare absence/list refresh with NetBox. Verify a populated group is blocked and its members unchanged. Check restricted delete permissions and conflicts; inspect NetBox before starting another deletion after a lost response. External synchronization may recreate managed objects. Automated tests never delete production groups. Other context deletion remains proposed.

The native VLAN→group protected relationship and `group_id` filter were verified against [NetBox 4.7.2 models](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/models/vlans.py) and [filtersets](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/filtersets.py). Hidden/plugin dependencies and related-object races remain subject to server validation.

The user explicitly authorized production writes on 2026-10-03, after reporting VM backups. The first implementation edits descriptions on Sites, Racks, Devices, Virtual machines, Prefixes and IP addresses. It does not create/delete objects or edit addressing, assignments, relationships, interfaces, cables, tags or other properties.

Open a fresh detail and tap Edit → Edit description. The editor makes a new GET for that exact typed collection/positive ID and pairs the returned description with its ETag. It shows the HTTPS server, object label/ID and a 200-code-point description field. Review change shows Before/After; Confirm change is the only mutation trigger. Cancel before confirmation performs no mutation. Leading/trailing whitespace is trimmed in both the Before/After review proposal and transmitted value, matching the usual REST framework CharField behavior ([DRF fields](https://www.django-rest-framework.org/api-guide/fields/#charfield)). An empty value deliberately clears the description.

The client sends a JSON PATCH containing only `description` and the exact snapshot ETag in `If-Match`. NetBox 4.7.2 uses weak timestamp ETags and checks the version again under a row lock; this is a NetBox-specific contract, distinct from general HTTP strong comparison. Sources: [4.7.2 REST API documentation](https://github.com/netbox-community/netbox/blob/v4.7.2/docs/integrations/rest-api.md) and [4.7.2 ETag/update implementation](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/netbox/api/viewsets/__init__.py). A missing/malformed ETag blocks editing. An unrelated GET cannot replace the editor's version.

401/403 errors retain the draft; the server enforces both token write enablement and user/object change permissions. A 409/412 conflict requires explicit reload and another review/confirmation. Every failed/uncertain save requires reload and retains the draft. No mutation is automatically retried: a lost response may mean the change already happened. Read the reloaded Before value before confirming again. Cancellation after dispatch also cannot establish that the server rolled back. The editor prevents dismissal during an active save; terminating the app may still leave an uncertain result.

Success requires a matching object ID and returned description, then displays Description saved. Closing the editor refreshes its parent detail. Previously opened collection rows can remain stale until their next refresh. Drafts and error response bodies are not persisted or logged; the user token remains in Keychain.

## Production acceptance — descriptions accepted; negative cases pending

No real production write has been performed by the automated suite. It intercepts requests locally with synthetic data and credentials.

1. Select a specific object whose description can be temporarily changed and note the original description in NetBox. Avoid screenshots containing tokens.
2. Use a write-enabled token with the relevant change permission, entered only in the app. A read-only token can still browse, but saving will be refused.
3. Open that object's detail → Edit → Edit description. Check the server and object ID, change the description, review Before/After, then confirm once.
4. Compare the saved value and NetBox change log. Restore the original through the same editor and verify it again.
5. Test Cancel/no-op, an explicit empty value if appropriate, 403 with a read-only token, and an actual conflict: open the editor, change the object's description from NetBox, then confirm the stale draft in the app. Expect a conflict, reload, and review the new Before value.
6. Test network interruption during saving; reload and check the server before any further confirmation.

Further milestones should be agreed separately: other textual fields, typed forms with validated relations, creation, then deletion with dependency handling. Bulk writes and automatic retries are outside this scope.

## Milestone 9 — Comments and IP DNS name

The same editor now offers **Edit comments** on Sites, Racks, Devices, Virtual machines, Prefixes and IP addresses, plus **Edit DNS name** on IP addresses only. The chosen field is paired with a fresh object/ETag. Each PATCH contains exactly one whitelisted key; an unavailable field blocks editing. Descriptions remain limited to 200 Unicode scalar code points. Comments have a client limit of 10,000 code points (NetBox itself uses an unbounded text field), preserve internal newlines/Markdown and trim only surrounding whitespace. DNS names are limited to 255 code points and converted to lowercase, matching [NetBox 4.7.2 IP model](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/models/ip.py). Validation follows [NetBox 4.7.2 DNSValidator](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/validators.py), including an initial wildcard and underscores. Unicode domains need their ASCII/punycode form. Editing DNS name updates the NetBox record, not a DNS server.

The user confirmed successful production description editing on 2026-10-03. The user also confirmed real write testing after milestone 9. The following procedure remains useful for regression and negative-case verification:

1. Choose an object, note its current comments in NetBox, then use Edit → Edit comments. Include a short multiline Markdown example and check Before/After before confirming.
2. Verify comments and unchanged description in NetBox, then restore the original comments using the editor. Repeat on another collection as needed.
3. Choose an IP address, note its original DNS name, then use Edit → Edit DNS name. Try uppercase input and check that the preview and saved value are lowercase. Verify the IP address and assignment stay unchanged, then restore the DNS name.
4. Try Cancel, unchanged values, invalid DNS syntax (review disabled), and intentional clearing only on an appropriate object. Permission/conflict/offline cases follow the existing description procedure above.

Automated verification uses only synthetic responses. No token is exported and no automated production write is performed.

## Milestone 10 — Prefix and IP address creation

From a main Prefixes/IP addresses list (Dashboard or IPAM tab), tap **+**. The form supports CIDR, status, VRF, tenant, description/comments and DNS name for IPs. Global VRF and No tenant are explicit choices; currently selected VRF/tenant filters initialize the form. Other filters remain on the originating list after closing, so a newly created object may be hidden by those filters; its success screen can always open the returned object directly. Contained-network/interface lists do not offer creation, avoiding an implied assignment or inherited address allocation.

IPv4/IPv6 syntax and prefix length are validated. A prefix must be a network address (host bits zero); an IP preserves its host bits. Outer whitespace is removed, IPv6 notation is canonicalized and DNS name is lowercased. Descriptions/comments/DNS keep their existing 200/10,000/255 Unicode-code-point client limits. IP host-only comparison follows the [NetBox 4.7.2 NetIn lookup](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/lookups.py). The form selects only positive reference IDs from paginated GET pickers; empty choices explicitly transmit `null` for VRF/tenant. [NetBox 4.7.2 serializers](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/api/serializers_/ip.py) define the supported creation fields.

Review creation checks exact visible prefixes or host IPs in the selected VRF using the [NetBox 4.7.2 filters](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/filtersets.py), then shows the server, collection, normalized CIDR, status, reference names/IDs, description/comments and DNS. Confirm creation rechecks visible duplicates and sends one typed collection POST containing only those fields. IP duplicate checks ignore mask length; the app blocks visible duplicates even if server configuration permits them. No available-IP allocation, assignments, NAT, VLAN/scope/roles, custom fields, bulk creation or ETag/idempotency guarantee is claimed. The duplicate check cannot see permission-hidden objects or prevent another client from creating concurrently; NetBox rules still decide the POST result. Required custom fields or extra server validation may cause a refusal; use NetBox itself for unsupported creation fields.

Success requires a positive returned ID, matching parsed CIDR/family, exact VRF/tenant, status and submitted text values, and no IP assignment. The success page links to a fresh detail GET. A denied, rejected, lost, cancelled, malformed or mismatched save never triggers an automatic retry; the same editor does not attempt a second POST. The draft/preview remains in memory and **Check existing objects** opens a VRF-scoped read-only verification list. A lost response may have created an object, so check before opening another creation form. Server error-body text is not displayed or logged.

Production creation acceptance remains to do (automated tests use synthetic responses only):

1. Select a prefix or IP that is deliberately free in the intended VRF. Note the intended tenant/status and use a short test description.
2. Tap **+**, enter the CIDR, choose VRF/tenant, review the server and every proposed value, then confirm once.
3. Open the new object from the success screen and compare its ID, CIDR, VRF, tenant, text/DNS and unassigned state with NetBox and its change log. Try IPv4 and IPv6 as appropriate.
4. Try invalid CIDRs/host bits, visible duplicates, Cancel and a token without add permission. Cancel before confirmation must not create anything.
5. If the response is uncertain, use **Check existing objects** and verify NetBox before another attempt. Remove a temporary test object in the NetBox UI if needed; deletion is not available in MNetBox yet.

## Milestone 11a — Device and VM name/status editing

Authorized on 2026-10-04 after the production server upgrade to 4.7.2. Open an existing Device or VM detail → Edit → Edit name / Edit status. The existing editor fetches that typed ID and pairs the field with a fresh ETag. It reviews exactly one field before Confirm change and verifies returned identity/value. Cancel and unchanged values do not write; closing refreshes the detail. Other list rows may need refresh.

Name limits follow the [4.7.2 Device model](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/models/devices.py) and [VM model](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/virtualization/models/virtualmachines.py): 64 Unicode code points. Outer whitespace is removed; names retain case, and line breaks/control characters are rejected. An empty Device name is transmitted as `{"name":null}` and reviewed as Empty; a VM requires a name. A missing name key is an invalid snapshot, while a present null name is valid for an unnamed Device. Server-side naming uniqueness rules are authoritative.

Status uses only [standard Device choices](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/choices.py) or [VM choices](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/virtualization/choices.py). Paused is a VM choice; Inventory is a Device choice. The JSON contains the raw status value, not its localized label. Current custom statuses remain visible; this editor offers standard statuses rather than arbitrary strings. Configurations that override standard choices may refuse a change. Status edits update NetBox metadata and do not operate the equipment or VM. A 403, conflict, lost response or mismatched reply retains the draft and requires explicit reload/review; no automatic retry.

The user confirmed real name/status acceptance on 2026-10-04. These steps remain useful for regression and negative-case checks:

1. Choose a Device or VM and note its current name/status. Use the existing write-enabled token, entered only in the app.
2. Change one field, check the server/ID and Before/After, confirm once, then compare NetBox and its change log. Verify the other field and relationships remain unchanged. Restore the original through the same flow.
3. Check Cancel/no-op and, on a deliberately selected Device, optional unnamed behavior. Check that empty VM names and overlong names disable review.
4. Verify permissions and a stale-version conflict; reload and compare the current value before confirming again. After network uncertainty, check NetBox first.

Automated verification is synthetic only; no production token is read, logged or exported. Interface and relationship writes remain proposed for subsequent scope.

## Milestones 11b/11c — Interfaces and inventory relations

The user requested both planned milestones together on 2026-10-04 and accepted real 11a name/status edits. Interface details now offer **Edit enabled** and **Edit MTU**, and Device/VM details offer **Edit tenant**, **Edit role** and **Edit platform**. Each editor changes exactly one field after fresh GET/ETag, immutable review and confirmation. The response must match target identity and the reviewed value. Closing refreshes the originating detail; other list rows may need refresh. Cancel/no-op sends no PATCH.

Enabled is a JSON boolean. MTU uses an integer between 1 and 65,536 or null for an explicitly empty field, following [4.7.2 BaseInterface](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/models/device_components.py) and [MTU constants](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/constants.py). Both physical and VM interfaces use this base model. The fresh snapshot/reply must keep the expected parent ID; an interface moved to another parent cannot be edited from a stale detail. Interface edits update NetBox metadata; they send no cable, VLAN, MAC, address or operating-system configuration commands.

References send only a positive ID or null. Tenant and platform can be cleared on Devices/VMs. Device role is required; VM role can be cleared and must have vm_role=true when set, per [Device serializer](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/api/serializers_/devices.py), [VM serializer](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/virtualization/api/serializers_/virtualmachines.py) and [VM model](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/virtualization/models/virtualmachines.py). Search/pagination keeps the VM-role filter; incompatible rows are rejected. Every nonempty reference is freshly resolved at review and again before PATCH. The target object's ETag protects against target changes; NetBox validates reference permissions, manufacturer/platform constraints and changes to referenced objects. Permission, conflict, uncertain or mismatched replies retain the draft and require reload/review; no mutation retries automatically.

The user confirmed normal production acceptance on 2026-10-04; negative cases remain useful:

1. Choose a physical and a VM interface; note enabled/MTU values. Review and confirm one field, compare NetBox and the change log, then restore it. Confirm parent, cables, VLANs, MACs and IPs remain unchanged. Test MTU clearing only deliberately; invalid/out-of-range input should disable review.
2. Choose a Device and a VM, note tenant/role/platform. Select a reference, review names/IDs, confirm once and compare NetBox; restore the original value. Check optional clearing and that Device role has no None choice; VM role choices should exclude non-VM roles.
3. Verify Cancel/no-op, read-only-token refusal, a changed target's ETag conflict and unavailable references. After transport uncertainty, reload/check NetBox before confirming again.

All automated tests use synthetic responses. No production credential is exported and no arbitrary production object is changed automatically.

## Milestone 12 — IPAM, primary addresses and interface creation

Prefix/IP Edit menus offer status and tenant; IP details additionally offer assignment. Choose Device/VM, parent, then an interface; review the before/after kind and ID. Remove assignment sends exactly `assigned_object_type:null` and `assigned_object_id:null`. Existing non-interface assignments remain readable and are not edited by this flow. NetBox may refuse removing a primary address's assignment; deliberately clear the primary designation first. No related object is automatically modified.

Device/VM Edit menus offer primary IPv4/IPv6, including None. The picker uses [4.7.2 IP filters](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/filtersets.py) for family and parent; a fresh IP and interface GET verifies exact family, assignment type and parent. Initial scope is directly assigned interfaces (no NAT/FHRP inference). Payload is only `primary_ip4` or `primary_ip6`, positive ID/null. Target ETags and returned identities/values are checked. Related-object races remain subject to NetBox validation.

A scoped Interfaces list offers **+**. Create a physical/VM interface with name, enabled, MTU, description and physical-only type. Supported types follow [4.7.2 choices](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/choices.py); this first form exposes five common types, not the entire catalog. The preview identifies the server, parent kind/ID and values. Parent and visible name duplicates are checked twice; the server remains authoritative. One POST attempt per editor; uncertain outcomes retain the draft and allow Check existing objects. No mutation automatically retries. Closing refreshes the originating interface list.

Production acceptance still required:

1. On a deliberately chosen prefix/IP, edit status or tenant and compare ID, address/mask, VRF and change log. Restore if needed.
2. Assign an IP to a physical and a VM interface; compare parent/interface identity in NetBox. Test detachment only deliberately; primary constraints may reject it.
3. Set/clear a Device/VM primary IPv4/IPv6 from its assigned addresses. Verify family, parent and the unchanged address/VRF.
4. Create one deliberately named physical/VM interface, compare its fields and parent, and check duplicate refusal/Cancel. Remove temporary interfaces in NetBox if needed.
5. Verify read-only permission refusal, ETag conflict and uncertain response handling. Check current server state before another attempt.
6. Compare again after the next external synchronization: fields owned by that script can be overwritten. The app does not change the script or its ownership rules.

Automated tests do not use production credentials or write to the production server.

## Milestone 13 — Controlled deletion

IP and prefix details: Edit → Delete object. Interface details: Edit → Delete object. Review server, object, decimal ID, VRF or exact Device/VM parent; type the displayed ID exactly before confirming. This is permanent deletion of one object; there is no undo or automatic detachment. The app does not offer Device, VM, Rack, Site, cable or bulk deletion.

Fresh full responses must include the known dependency fields. Checks are repeated immediately before DELETE, with the reviewed ETag in If-Match. IP checks include assignment, NAT (both directions), Device/VM primary address references searched by host and compared by ID across every visible page, Device OOB references and FHRP primary references. Prefix checks include strictly contained prefixes, IPs and ranges in its exact VRF. Interface checks include IPs, MACs, VLAN/VRF/FHRP/L2VPN configuration, parent/bridge relationships and dependents; physical interfaces additionally check cable, occupancy, LAG dependents, module and wireless links. Permission errors, incomplete metadata and inconsistent pagination fail closed.

The DELETE contract follows [NetBox 4.7.2 model viewsets](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/netbox/api/viewsets/__init__.py): only an empty HTTP 204 confirms success. Every editor sends at most one mutation attempt, including after cancellation, conflict, refusal or uncertain transport. Check current object sends GET only; 404 means the object is no longer visible and is not proof that this attempt deleted it. Verify NetBox/change log before deliberately opening a new deletion.

These checks cover only objects visible to the token and cannot lock related objects between preflight and DELETE. Hidden/plugin/custom dependencies and reference races remain subject to server behavior; the target ETag does not version all related objects. NetBox may refuse deletion or apply its own relationship deletion rules. An external synchronization may recreate a deleted object. After success, the originating IPAM/interface list refreshes; other search/context lists can require manual refresh.

Production acceptance:

1. Create a deliberately temporary empty prefix, an unassigned IP and one physical/VM interface without MAC/IP/VLAN/cable dependencies. Compare their IDs, VRF and parents in NetBox.
2. Open Delete object, try an incorrect ID and Cancel. Nothing should be deleted.
3. Review again and confirm the correct ID once. Compare the result and change log in NetBox; check the originating list refreshes.
4. On an assigned IP, occupied/cabled interface or populated prefix, confirm that dependencies block deletion. Do not remove real dependencies just to run this test.
5. Check delete-permission refusal, a changed object's conflict and outcome checking after an uncertain response with controlled test objects. Verify server state before another attempt.
6. Check after the next synchronization; automatic recreation is external to MNetBox.

All automated deletion tests use local synthetic responses, never production tokens or production objects.

## Milestone 14 — Interface names, descriptions and physical types

Interface → Edit now offers name and description for physical/VM interfaces, plus type for physical interfaces. Fresh GET pairs the exact positive object/parent identity with its ETag. Review Before/After and confirm one selected field; the PATCH contains only name, description or type, with If-Match. Cancel/no-op sends no mutation; errors retain the draft and require reload/review, never automatic mutation retry.

Names are required, trimmed, limited to 64 Unicode scalars and reject control characters. Descriptions trim outer whitespace, allow up to 200 Unicode scalars and clear with an empty string. The Clear description button prepares that empty draft; review and confirmation are still required. These limits follow [NetBox 4.7.2 components](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/models/device_components.py) and [VM interfaces](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/virtualization/models/virtualmachines.py). Server uniqueness rules, custom validators and permissions remain authoritative; a duplicate name can be refused by NetBox.

Physical type offers the five common values already supported by interface creation: virtual, 1000base-t, 10gbase-x-sfpp, lag and other. Other current type values are displayed/preserved when editing another field; use NetBox for other new type choices. The app sends no cable, MAC, VLAN, bridge/LAG membership, IP or host/guest configuration change. NetBox may refuse a type incompatible with existing dependencies. No related objects are automatically changed. Closing refreshes the detail; other lists may need manual refresh.

Production acceptance: choose deliberately temporary or suitable physical/VM interfaces; rename, change/clear description and change a physical type after review. Compare exact IDs, parents, values and change log in NetBox, and unchanged cable/IP/MAC/VLAN relations. Restore values if needed. Check Cancel/no-op, invalid names, duplicate refusal, permissions/conflict and uncertain response handling. Compare after the next external synchronization; script-owned values may be overwritten. Automated tests use synthetic responses only.

## Milestone 15 — VLAN configuration and direct editing

Tap a detail row with a pencil to open its existing editor, or keep using Edit. Supported name/status/reference/interface/IPAM fields remain unchanged; empty description/comments rows allow adding text. Each write still requires Before/After review and explicit confirmation.

IP assignment now checks the original parent before detachment or a move to another parent. NetBox [4.7.2 IP validation](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/models/ip.py) rejects a move/detachment while the IP is a primary or OOB address on its original parent. Open that Device/VM and clear the relevant primary IPv4/IPv6 designation deliberately first; clear OOB in NetBox. The app never clears another object automatically. An interface move on the same parent retains its primary designation. Missing metadata/permissions block the check. Server-side primary/OOB errors become static, actionable messages; other assignment HTTP 400 replies get a static compatibility/validation message. Raw server messages are never displayed or logged. The user confirmed on 2026-10-04 that this NetBox constraint caused the reported detachment failure.

Interface → VLAN mode / Untagged VLAN / Tagged VLANs, or Edit → Edit VLAN configuration. The reviewed PATCH includes exactly mode, untagged_vlan (positive ID or null) and tagged_vlans (unique positive IDs, possibly empty), with paired If-Match. No other field or object is written. Supported modes: routed (empty), access, tagged, tagged-all. Routed requires no VLANs; Access and Tagged all require an empty tagged list. The app also rejects the same VLAN as both explicit untagged and tagged. Mode changes retain all draft selections; remove incompatible selections explicitly. All three current/proposed fields are visible in review.

The picker separately offers VLANs on the parent's site and Global VLANs. Parents without a site can use Global only. Positive IDs, VID 1...4094 and explicit nullable site metadata are required. Filters/search persist in pagination, and returned scope is checked. Every chosen VLAN and the parent site are freshly read before review and again before PATCH; changed parent site, target version/configuration, incompatible reference or missing data blocks writing. Snapshot/reply must retain the exact interface and original positive parent identity. Unsupported modes, QinQ and VLAN translation policies are managed in NetBox; this editor does not clear them.

This follows the [physical-interface serializer](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/api/serializers_/device_components.py) and [VM-interface serializer](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/virtualization/api/serializers_/virtualmachines.py). NetBox permissions, custom validators and reference races remain authoritative. Failure/uncertainty preserves the draft and requires reload/review; no automatic retry. This changes NetBox data, not switch or guest configuration.

Production acceptance: use a suitable interface, test Cancel, then site/global choices, mode plus explicit clearing, and review once before confirmation. Compare all three VLAN fields, exact interface/parent IDs and change log with NetBox. Check incompatible scope, unsupported QinQ/translation, restricted permissions, conflict and offline recovery on controlled objects. For the previously refused IP, first inspect its original VM primary designation; clear it only if that is the intended configuration, then review detachment. Compare after the next external synchronization. Automated tests remain synthetic only.


The user accepted milestone 15 normal production testing on 2026-10-04. Milestone 16 adds read-only VLAN/group browsing and links to existing prefix/interface editors; it introduces no VLAN/group object mutation. Broader permissions/conflict/offline cases and persistence across synchronization remain useful acceptance checks.

Milestones 17–18 and the graphical Dashboard introduce no mutation endpoints. Context navigation can open the existing reviewed editors; their confirmation and dependency rules still apply. VLAN object writes/MAC administration remain milestone 19, separately scoped. No automated production mutation is used in this delivery.

## Milestone 19: VLAN and MAC writes — 0.6.0 build 19

VLAN creation: IPAM → VLANs → +. Enter VID (1–4094), name (required, ≤64 Unicode scalars), status and optional Site, VLAN group, Tenant and IPAM Role; review all fields/server before confirming. The group is freshly read for ranges and direct Site/Site-group compatibility. Visible duplicate VID/name checks repeat before POST; ungrouped checks use the selected direct site and do not claim global uniqueness. One typed POST creates one VLAN. No interface assignment, QinQ or switch configuration is sent. A failed/lost/mismatched reply retains the draft and blocks a second attempt in the form; check existing objects before starting anew.

VLAN details: tap Name, Status, Tenant, IPAM Role, Description or Comments. The existing editor reads a paired ETag, reviews Before/After and sends one field. VID and Site/group moves are deliberately read-only after creation. VLAN/group deletion and group writes are later scope.

MAC creation: Device/VM → Interface → MAC addresses → +. Colon, hyphen, compact and Cisco dotted 48-bit input normalizes to uppercase colon format. The preview shows the exact interface and parent. One POST creates an assigned, nonprimary MAC with optional description/comments. The visible duplicate check is local to that interface; another object with the same address is not assumed to be the same MAC.

Primary MAC: on an interface, tap Primary MAC or Edit → Edit primary MAC. Select only a MAC already assigned to that exact interface, or None to clear its designation. Fresh target/reference reads and paired If-Match precede one primary_mac_address PATCH. It does not delete or move the MAC.

Assignment: on a MAC detail, tap Assignment; choose physical/VM parent and interface, or Remove assignment. Preview shows Before/After, then one paired type/ID PATCH or both null. A currently primary MAC cannot be moved/detached; explicitly clear it on its original interface first. Primary designation checks are repeated, and NetBox remains authoritative for related-object races. No automatic clearing, chained mutation, address replacement or MAC deletion. Text edits use the existing reviewed description/comments path. These are NetBox data changes only; devices/guests are not configured. The external synchronization may own/reapply MAC fields.

Manual acceptance, when the iPhone is available:

1. Create a deliberately chosen test VLAN, compare VID/name/site/group/status/tenant/role and change log. Tap a supported field; verify Cancel, then review/confirm one edit.
2. On a chosen physical/VM interface, compare its MAC list and primary designation. Create a spare MAC; verify normalization, exact parent/assignment and that primary remains unchanged.
3. Set/clear a primary MAC deliberately, then test secondary detachment or move; verify a primary move is blocked without any implicit clearing. Compare IDs when addresses recur.
4. Check restricted permissions, conflict/offline/uncertain responses on controlled objects, plus persistence after the next external synchronization. Synthetic automation performs no production writes.

Version-pinned contracts: [VLAN serializer/model](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/api/serializers_/vlans.py), [VLAN constraints](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/models/vlans.py), [MAC serializer](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/api/serializers_/devices.py), [MAC primary-assignment constraint](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/models/devices.py), [interface primary MAC field](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/api/serializers_/device_components.py).

## Milestone 20: groups and guarded deletion — 0.7.0 build 20

IPAM → VLAN groups → + creates a group with name (required, ≤100 Unicode scalars), slug (required, ≤100 ASCII letters/digits/underscore/hyphen), VID intervals and optional tenant. Enter intervals as `1-100,200,300-399`; bounds are 1–4094, no overlap, at most 100 intervals. Default is 1–4094. Choose Global or a specific region/site group/site/location/rack group/rack/cluster group/cluster, then select its exact object. Scope changes clear the previous draft scope selection. Review shows server, scope type/object ID and all proposed values before a single POST. Fresh references and same-scope visible name/slug checks are repeated before creation. Failure/uncertainty never retries; check existing groups first. Group detail taps edit name/description/comments individually. Existing slug/tenant/ranges/scope are read-only; no group deletion.

VLAN/MAC details expose a trash button. VLANs with prefixes, explicit physical/VM interface assignments, QinQ roles/customers or L2VPN termination are blocked. MACs must first be explicitly unassigned and nonprimary; ID-based physical/VM primary-reference checks also apply. Review exact server/object/ID (VLAN VID/site/group context), then enter the decimal object ID. Full fields, paired ETag and fresh repeated dependencies are mandatory. One DELETE with If-Match, no cleanup or retries. Only empty 204 confirms deletion. A later GET/404 indicates absence of visibility, not proof of deletion. Closing success returns to the originating list/search and refreshes it without clearing filters. Hidden/plugin dependencies and reference races remain subject to server validation.

Manual acceptance when available:
1. Create a deliberately named temporary group, Global or scoped to a known object, with `100-199,250`; compare scope, tenant and ranges in NetBox. Tap its name/description/comments and verify a single field changes.
2. Create a disposable VLAN in that group, without dependencies; delete it using its NetBox object ID, compare absence and list/search refresh. Test that a VLAN linked to an interface/prefix is blocked.
3. On a disposable secondary MAC, explicitly detach it, then delete by ID; a primary or assigned MAC must remain blocked. Distinguish reused address strings by object ID.
4. Check restricted permissions, changed references/conflicts/offline outcomes and persistence after the external synchronization. Group deletion is performed manually in NetBox if desired.

All automated validation uses synthetic responses; no production API writes. Version-pinned contracts: [group/VLAN serializer](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/api/serializers_/vlans.py), [group/VLAN constraints and filters](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/filtersets.py), [physical interface filters](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/filtersets.py), [VM interface filters](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/virtualization/filtersets.py).

## Bundled milestones 21–23 — 0.8.0 build 23

Prefix details: tap VLAN, Role or Scope. Select an exact VLAN/IPAM role or None; scope offers Global or a positively identified Region/Site group/Site/Location. Scope writes the type/ID pair together, including two nulls for Global. Searchable selectors, fresh reference resolution, Before/After confirmation and ETag protect each typed PATCH. Existing addressing, VRF and modeled metadata must remain unchanged in the reply. Unsupported/plugin scopes stay read-only in this editor.

Prefix/IP details: tap Address / prefix or VRF (also available under Edit). Address and VRF are separate one-field changes, not a multi-object migration. Normalize IPv4/IPv6 CIDR; prefixes require network addresses, /0 is rejected and the family cannot change. Prefixes with children/IPs/ranges are blocked; IPs with assignment, NAT, primary/OOB/FHRP references are blocked. Explicitly clear dependencies in a separate action if appropriate; the app never does this automatically. Review server, object ID, current VRF and Before/After; repeated dependency checks and target ETag precede PATCH. Destination duplicate checks are advisory and scoped to Global/named VRF, exclude the current positive ID and treat equal IP hosts with different masks as duplicates. Expanding/moving a prefix cannot absorb existing children/IPs/ranges; legitimate containing parent prefixes remain allowed. The app conservatively rejects visible duplicates even where a server allows them. Failed/lost/mismatched replies preserve the draft and require reload/review; no automatic retry. Related-object races and hidden/plugin references remain subject to server validation.

Manual real-server acceptance:
1. On a deliberately selected prefix, change/clear VLAN and IPAM role, and set/clear a supported scope. Compare object IDs and verify CIDR/VRF did not change. Try Cancel and verify no change.
2. Use a temporary empty prefix and unassigned IP for same-family CIDR/mask and Global/named VRF changes. Compare exact values in NetBox; test IPv4 and IPv6. Verify an occupied prefix, assigned/primary/NAT IP and duplicate destination are blocked.
3. Inventory → Cables: compare search/status/unterminated filters, device-scoped lists, pagination, A/B endpoints and all branches with NetBox. Open a known interface from the diagram; unfamiliar ports remain labels. This graph shows one cable, not a traced network path.
4. Check restricted accounts, unavailable references, conflicts/offline outcomes and values after the external synchronization. Synchronization may overwrite application changes according to that script's ownership rules.

No automated production mutation. Source contracts: [Prefix/IP serializer](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/api/serializers_/ip.py), [IPAM model validation](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/models/ip.py), [location scope types](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/constants.py), [cable serializer](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/api/serializers_/cables.py), [cable filters](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/filtersets.py).

## Milestone 24 — 0.9.0 build 24

Use a deliberately selected temporary VLAN with no prefixes, physical/VM interface assignments, QinQ or L2VPN relationships. Tap VLAN ID, Site or VLAN group directly, or use Edit. Verify Before/After, server and object ID before confirming; compare the result with NetBox. Test clearing site/group and Cancel. IDs stay stable; these fields describe NetBox objects and do not configure switches. Occupied VLAN identity changes are intentionally blocked in this version.

For a VLAN group, test slug and tenant (including None). Test ranges with multiple intervals: keep every member VID in range; excluding an existing member must block confirmation. Change scope only on an empty group. Global and the eight supported scope types use fixed searchable reference selectors. A nonempty group cannot change scope; no member is migrated or modified implicitly. Duplicate name/slug in the destination scope, duplicate VID/name in a VLAN destination group, invalid ranges and incompatible Site/Site-group membership block review. Unknown scopes stay readable and cannot be edited here.

Compare other fields after every save. Use restricted accounts, stale versions and offline saving to verify errors keep the draft and require explicit reload/review. A lost response may already have saved: inspect the current server object before another attempt. Checks cannot reveal hidden/plugin dependencies or lock related objects. NetBox remains authoritative. Do not change fields owned by the external synchronization without accounting for its next run; this app never alters the synchronizer.

Contracts checked against the [NetBox 4.7.2 VLAN models](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/models/vlans.py) and [serializers](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/api/serializers_/vlans.py). No automated production writes are used for validation.

## Milestone 25a — 0.10.0 build 25

Use deliberately selected temporary VRF, tenant and IPAM-role objects. In each global directory, the plus button opens creation with server/kind review. Verify name, nullable references, RD/enforce_unique (VRF), slug/group (tenant) or slug/weight (role), description/comments before confirming. Open the returned object and compare its positive ID and fields in NetBox. No other object or network setting is changed. Tenant names/slugs are checked in their exact group; reused VRF names are conservatively blocked by the app even though the server can permit them. Nonempty RD duplicates are blocked. Weight is limited to the portable 0–32767 range.

Tap a metadata field or use Edit. Verify one selected field changes and other references, RD, uniqueness and route targets remain unchanged. Test nullable tenant/group clearing, duplicate destination group, missing references, invalid slug/weight, Cancel, restricted permissions, stale versions and lost responses. An uncertain creation may exist already: inspect existing objects before starting a new form. Failed edits keep the draft and require explicit reload/review. Context deletions, existing RD/uniqueness changes and route-target administration are deferred. External synchronization remains external and can overwrite managed fields.

For graphical/image acceptance, compare returned context counts with NetBox. Open an equipment/site/rack/VM with image attachments; equipment may also inherit front/rear images from its NetBox device type. Up to four attachments plus two device-type images load automatically; tap opens a larger thumbnail. Without NetBox images the native header remains. The app does not search public catalogs or upload pictures. HTTPS same-origin media uses no API token/browser cookie: private media requiring browser login or external/signed URLs may be unavailable. Test empty galleries, denied metadata, protected media, offline/retry and large images. No production image/object writes were used in automated testing.

Reference contracts: [VRFs](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/api/serializers_/vrfs.py), [tenants](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/tenancy/api/serializers_/tenants.py), [roles](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/ipam/api/serializers_/roles.py), [attachments](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/extras/api/serializers_/attachments.py), [device types](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/api/serializers_/devicetypes.py).

## Build 27 manual read-only acceptance

Open devices with existing images and refresh/retry their existing NetBox JPG/PNG images. Compare attachment and device-type front/rear pictures; tap to preview. The app now supplies the existing token only on the two native same-origin image directories, with no cookie/redirect/external storage support. Token must retain view permissions. No server configuration change or image upload is required by this app update. If unavailable persists, investigate the server media response/permissions without exposing the token.

On a deliberately chosen physical interface with documented cabling, open Cable trace and compare every returned step with NetBox, including front/rear patch-panel connections, cable status and linked objects. An empty/partial/split/restricted path is not proof of network reachability. No cable mutation, detach or hardware command is sent. Other context deletions remain proposed.

Authentication and trace contracts verified in [NetBox 4.7.2 media view](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/netbox/views/misc.py), [token mixin](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/utilities/views.py), and [trace API](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/api/views.py).

## Image attachment upload — 0.12.0 build 28

Site/rack/device/VM detail → Add image → Choose photo (iPhone Photos picker). Enter a nonempty name (<=50 scalars) and optional description (<=200), inspect oriented JPEG preview and exact server/object/name/ID, then Confirm upload. Selected source max20 MiB/100M pixels; output <=2048 pixels/8 MiB. Source GPS/EXIF/filename metadata is not copied, original photo is unchanged. Parent visibility/title is checked at review and before one multipart POST to the fixed attachment endpoint. NetBox must grant add_imageattachment/view permissions and a write-enabled token. No parent field or device-type picture is replaced. A successful positive exact reply/HTTP201 closes to a refreshed gallery showing newest four attachments; extra images stay available in NetBox.

Manual checks: choose a disposable intended site/rack/device/VM, cancel after preview, compare that nothing was added. Upload a chosen photo and compare name/description/orientation and object ID with NetBox; reopen/refresh and enlarge it. Try a PNG/HEIC photo and Photos cancellation, denied add permissions/offline state, and a changed parent title between review/confirmation. After a lost/unconfirmed response, inspect existing attachments before opening a new form; no retry is sent by the old form. Automated tests use synthetic bytes only. Device-type image writes, replacement/deletion, camera capture and bulk upload remain outside scope.

Multipart fields and limits verified in the [NetBox 4.7.2 attachment serializer](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/extras/api/serializers_/attachments.py) and [image model](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/extras/models/models.py).

Passive ports: interface → cable trace → front/rear port. Compare type, position count, device/cable and opposite mapping links with NetBox. No port or cable write is sent. Contracts follow [4.7.2 component serializers](https://github.com/netbox-community/netbox/blob/v4.7.2/netbox/dcim/api/serializers_/device_components.py).


Build 29 manual acceptance: on a disposable attachment under a site/rack/device/VM, tap Delete image, verify server/name/ID, cancel once, then reopen and enter its exact decimal ID to confirm. Ensure only the selected attachment disappears after Done; shared device-type pictures have no delete button. Upload a transparent PNG from Photos and verify its transparent edges in the checkerboard preview and in NetBox; opaque JPEG upload must still work. NetBox delete/add permissions remain authoritative. A denied/lost/ambiguous deletion permits GET-only inspection; verify NetBox before opening a fresh confirmation. No automated real-server write was run.


Build 30 manual acceptance: create/select a disposable unused VRF or IPAM role, open its trash action, review server/title/ID and blockers, cancel once then confirm by exact ID. Verify return to refreshed directory after success. A VRF with import/export targets or any visible prefix/IP/range/interface must block; a role used by a prefix/VLAN/range/ASN must block. Native nonzero annotated counts also block despite empty filtered visibility. Do not use synchronization-owned objects as disposable tests. No automatic cleanup/retry; inspect NetBox after uncertain outcomes. Tenant deletion remains unavailable. Browse Device → Ports and verify console/power details, passive mappings, search/pagination and native traces against your data.


Build 32 refines the GET-only graphical equipment port panel. Only records scoped to the exact device appear, with empty families hidden and read failures distinguished. Tapping a connector selects its record; Open port details opens the existing detail and reviewed editors. Verify real switches/routers/servers, selection/full names, actual family availability, cable/admin state, search/filter and pagination. No manufacturer placement, live operational status or hardware command is inferred.

## Graphical cable creation — build 33

On a disposable pair of physically connectable, unused NetBox data ports, open Device → Port panel, select a free port and Connect a cable. Choose the destination device, select its actual free interface/front/rear port on the panel, and Choose this port. Check full names and equipment on both A/B cards, optional label/type, Connected versus Planned documentation status and color. Review connection sends GET checks only; Back to editing and Cancel must not create a cable. Confirm connection sends one POST after fresh checks. Verify the created cable and both occupied endpoints in NetBox; remove a disposable test cable in NetBox itself if needed (app cable deletion remains planned).

Occupied, marked-connected, same endpoint, unsupported family, virtual/wireless/channel or changed identity must block. Denied/invalid/lost responses must retain the proposal without automatic retry: inspect NetBox before starting another form. The app documents cabling; no switch/router configuration command is sent. Fresh checks cannot lock endpoint races or hidden/plugin validation. Automated tests use synthetic requests exclusively.

## Cable deletion — milestone 34a

On a disposable test cable (for example one created with build 33), open Inventory → Cables or Interface → Cable, tap the trash button and check server, title, ID and both A/B ends. Cancel once and verify the cable still exists. Reopen, type the exact ID and confirm. Verify in NetBox that only this cable disappeared and that both ports are free again, with their names, descriptions and VLANs unchanged. Modifying the cable in NetBox between review and confirmation must produce a conflict without deletion. A denied, lost or ambiguous reply is never retried: check NetBox before opening a new deletion. Automated tests use synthetic responses only.
