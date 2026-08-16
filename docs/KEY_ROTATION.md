# Key Rotation

Covers attestor signing keys, the relayer key, solver keys, and the admin multisig. Bitcoin keys
belonging to users are explicitly out of scope — the protocol never holds one.

## Why rotation is cheap here

Every membership change to `BitcoinAttestorRegistry` increments `attestorEpoch`, and every
attestation binds the epoch it was signed under. The instant a rotation lands, **every signature
produced by the old set is worthless**, including any an attacker exfiltrated.

That is deliberate. The alternative — a grace period during which a removed operator still counts
toward quorum — is a window an attacker can aim for.

The cost is that in-flight authorizations must be re-collected. Announce a quiet window before a
planned rotation.

## Attestor key — planned rotation

Quarterly, or whenever an operator changes infrastructure.

1. Generate the new key in the operator's HSM/KMS. The private key never leaves it and never
   appears in a config file, a log, or an environment variable.
2. Operator publishes the new address and proves control by signing a rotation notice with the
   **old** key.
3. Queue `replaceAttestor(old, new)` on the timelock. `replaceAttestor` is atomic and never lets
   the set transiently drop below the five-attestor minimum.
4. Announce the pending epoch bump with its execution time. Relayers should stop collecting
   signatures shortly before.
5. Execute. Confirm on chain:
   ```bash
   cast call $ATTESTOR_REGISTRY "isAttestor(address)(bool)" $OLD   # false
   cast call $ATTESTOR_REGISTRY "isAttestor(address)(bool)" $NEW   # true
   cast call $ATTESTOR_REGISTRY "attestorEpoch()(uint64)"          # +1
   cast call $ATTESTOR_REGISTRY "attestorCount()(uint256)"         # unchanged
   ```
6. Operator restarts its attestor pointed at the new key and confirms `/health` reports the new
   epoch.
7. Destroy the old key material.

## Attestor key — emergency rotation

Suspected or confirmed compromise. **Speed beats process.**

1. The operator takes its attestor offline immediately. A key that cannot be reached cannot sign.
2. Assess blast radius:
   - **One key** — quorum still needs two more. Serious, not yet an emergency for the protocol.
   - **Two keys** — one away from quorum. Treat as SEV-1.
   - **Three keys** — the quorum is compromised. Pause oracle consumption now, rotate after.
3. Queue `replaceAttestor` (or `removeAttestor` if no replacement is ready — the set must stay at
   five or more, so removal is only available above the minimum).
4. If the timelock delay is intolerable given the blast radius, the guardian pauses oracle
   consumption while the timelock runs. Pausing consumption does not block refunds or withdrawals.
5. Audit every digest consumed since the earliest possible compromise. Cross-reference the
   compromised operator's audit log against the other four; look for facts only it asserted.
6. Post-mortem per [`INCIDENT_RESPONSE.md`](./INCIDENT_RESPONSE.md).

### Why there is no instant-revoke bypass

A path that could remove an attestor without the timelock would be a path an attacker could use to
remove *honest* attestors and reach quorum with fewer keys. The guardian pause is the fast lever;
membership always goes through the timelock.

## Relayer key

The relayer is trusted for liveness only. It cannot alter terms — every field is covered by
attestor signatures. Rotation is therefore routine:

1. Stand up a new relayer with a fresh key and funded gas.
2. Drain the old one's in-flight queue or let it expire.
3. Decommission.

No on-chain change is needed. Relaying is permissionless.

## Solver key

Two distinct keys, and conflating them is the mistake to avoid:

- **EVM key** — posts bonds, calls `settle`, receives reimbursement.
- **Bitcoin operational key** — pays sellers.

The Bitcoin operational wallet must be **separate from any inscription wallet**, hardware- or
HSM-backed, and PSBT-based in production. Never hardcode a seed in an environment file.

To rotate: stop reserving, let open reservations settle or expire, move funds to the new wallet,
restart. Rotating mid-reservation strands the bond, because `settle` requires `msg.sender` to be
the reserved solver.

## Admin multisig

The `DEFAULT_ADMIN_ROLE` on every contract belongs to a `TimelockController` whose proposers are a
multisig.

Rotating a signer:

1. Multisig owners approve the change through the multisig's own process.
2. No protocol contract changes — they only know the timelock address.
3. Re-run `scripts/verify-roles.mjs` and confirm no EOA holds a protocol role.

Rotating the timelock itself means granting admin to a new timelock and revoking the old one, in
that order, verified between steps. Getting the order wrong bricks administration permanently,
because there is no recovery path — which is the price of having no backdoor.

## Standing rules

- Private keys live in an HSM or KMS. Never in a repo, a `.env`, a log line, a CI secret used for
  anything else, or a screenshot.
- Every attestor operator holds exactly one key and does not hold anyone else's.
- Rotate on any operator staff change with key access.
- Test the rotation procedure on testnet before it is needed. A procedure first executed during an
  incident is not a procedure.
- `.gitignore` already excludes `*.key`, `*.pem`, `*.p12`, `keystore/`, `secrets/`, `wallets/` and
  every `.env` except `.env.example`. Secret scanning runs in CI regardless.
