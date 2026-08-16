import { describe, expect, it } from 'vitest';
import { privateKeyToAccount } from 'viem/accounts';
import type { Hex } from 'viem';
import {
  assembleQuorum,
  groupByDigest,
  MemorySubmissionStore,
  QuorumError,
  quorumProgress,
  sortGroupAscending,
  statusFromMatching,
  submitQuorum,
  type CollectedAttestation,
  type QuorumGroup,
  type Submitter,
} from '../src/index.js';

const DIGEST_A = `0x${'aa'.repeat(32)}` as Hex;
const DIGEST_B = `0x${'bb'.repeat(32)}` as Hex;

/** Five deterministic attestor keys, mirroring the production set size. */
const keys = Array.from({ length: 6 }, (_, i) => `0x${String(i + 1).padStart(2, '0').repeat(32)}` as Hex);
const accounts = keys.map((k) => privateKeyToAccount(k));
const AUTHORIZED = accounts.slice(0, 5).map((a) => a.address as Hex);
const OUTSIDER = accounts[5]!;

async function collect(
  accountIndex: number,
  digest: Hex,
  attestation: unknown = { note: 'facts' },
): Promise<CollectedAttestation<unknown>> {
  const account = accounts[accountIndex]!;
  return {
    operator: `operator-${accountIndex}`,
    attestation,
    digest,
    signature: await account.sign({ hash: digest }),
    attestor: account.address as Hex,
  };
}

describe('grouping counts facts, not signatures', () => {
  it('groups signatures over the same digest together', async () => {
    const groups = await groupByDigest([await collect(0, DIGEST_A), await collect(1, DIGEST_A), await collect(2, DIGEST_A)]);
    expect(groups.size).toBe(1);
    expect(groups.get(DIGEST_A)!.signers).toHaveLength(3);
  });

  it('keeps disagreeing operators in separate groups', async () => {
    // Three individually valid signatures over three different fact sets is NOT a quorum.
    const groups = await groupByDigest([await collect(0, DIGEST_A), await collect(1, DIGEST_B), await collect(2, DIGEST_A)]);
    expect(groups.size).toBe(2);
    expect(groups.get(DIGEST_A)!.signers).toHaveLength(2);
    expect(groups.get(DIGEST_B)!.signers).toHaveLength(1);
  });

  it('discards a signature whose recovered address is not the claimed attestor', async () => {
    // A compromised or buggy operator must not be able to inflate a group by lying about who signed.
    const honest = await collect(0, DIGEST_A);
    const liar = { ...(await collect(1, DIGEST_A)), attestor: accounts[4]!.address as Hex };
    const groups = await groupByDigest([honest, liar]);
    expect(groups.get(DIGEST_A)!.signers).toHaveLength(1);
  });

  it('drops a malformed signature without failing the whole collection', async () => {
    // One broken operator must not stop a quorum the other four can still form.
    const bad = { ...(await collect(0, DIGEST_A)), signature: '0xdeadbeef' as Hex };
    const groups = await groupByDigest([bad, await collect(1, DIGEST_A), await collect(2, DIGEST_A)]);
    expect(groups.get(DIGEST_A)!.signers).toHaveLength(2);
  });

  it('counts one operator answering twice only once', async () => {
    const groups = await groupByDigest([await collect(0, DIGEST_A), await collect(0, DIGEST_A)]);
    expect(groups.get(DIGEST_A)!.signers).toHaveLength(1);
  });
});

describe('ascending signer order', () => {
  it('sorts signatures by recovered address, not by signature bytes', async () => {
    const group = (await groupByDigest([await collect(2, DIGEST_A), await collect(0, DIGEST_A), await collect(1, DIGEST_A)])).get(
      DIGEST_A,
    )!;
    const sorted = sortGroupAscending(group);

    for (let i = 1; i < sorted.signers.length; i++) {
      expect(sorted.signers[i]!.toLowerCase() > sorted.signers[i - 1]!.toLowerCase()).toBe(true);
    }
    // The signatures must travel with their signers. Sorting the signature bytes independently
    // would produce an order unrelated to the recovered addresses, and the oracle would reject it.
    for (let i = 0; i < sorted.signers.length; i++) {
      const original = group.signers.indexOf(sorted.signers[i]!);
      expect(sorted.signatures[i]).toBe(group.signatures[original]);
    }
  });

  it('produces the same submission regardless of collection order', async () => {
    // Determinism is the second job the ascending rule does: a relayer that collected answers in a
    // different order must build a byte-identical transaction.
    const a = sortGroupAscending((await groupByDigest([await collect(0, DIGEST_A), await collect(1, DIGEST_A), await collect(2, DIGEST_A)])).get(DIGEST_A)!);
    const b = sortGroupAscending((await groupByDigest([await collect(2, DIGEST_A), await collect(1, DIGEST_A), await collect(0, DIGEST_A)])).get(DIGEST_A)!);
    expect(a.signatures).toEqual(b.signatures);
    expect(a.signers).toEqual(b.signers);
  });

  it('rejects a duplicated signer outright', () => {
    const group: QuorumGroup<unknown> = {
      digest: DIGEST_A,
      attestation: {},
      signatures: ['0x01' as Hex, '0x02' as Hex],
      signers: [accounts[0]!.address as Hex, accounts[0]!.address as Hex],
      operators: ['a', 'b'],
    };
    expect(() => sortGroupAscending(group)).toThrow(QuorumError);
  });
});

describe('quorum assembly', () => {
  const options = { threshold: 3, authorizedAttestors: AUTHORIZED };

  it('assembles at exactly the threshold', async () => {
    const group = await assembleQuorum(
      [await collect(0, DIGEST_A), await collect(1, DIGEST_A), await collect(2, DIGEST_A)],
      options,
    );
    expect(group.signatures).toHaveLength(3);
    expect(group.digest).toBe(DIGEST_A);
  });

  it('includes every agreeing signature above the threshold', async () => {
    const group = await assembleQuorum(
      [await collect(0, DIGEST_A), await collect(1, DIGEST_A), await collect(2, DIGEST_A), await collect(3, DIGEST_A)],
      options,
    );
    expect(group.signatures).toHaveLength(4);
  });

  it('fails with NO_QUORUM when there are simply not enough answers', async () => {
    await expect(assembleQuorum([await collect(0, DIGEST_A), await collect(1, DIGEST_A)], options)).rejects.toThrow(
      /only 2 of 3/,
    );
  });

  it('fails with MIXED_FACTS when the operators disagree', async () => {
    // Distinguishing "slow" from "disagreeing" matters: the first is infrastructure, the second is
    // the 3-of-5 design firing and must never be resolved by submitting the largest group anyway.
    const collected = [
      await collect(0, DIGEST_A),
      await collect(1, DIGEST_A),
      await collect(2, DIGEST_B),
      await collect(3, DIGEST_B),
    ];
    await expect(assembleQuorum(collected, options)).rejects.toThrow(/operators disagree/);
    await assembleQuorum(collected, options).catch((e: QuorumError) => {
      expect(e.code).toBe('MIXED_FACTS');
      expect((e.detail['digests'] as Hex[]).sort()).toEqual([DIGEST_A, DIGEST_B].sort());
    });
  });

  it('ignores a signature from outside the authorized set', async () => {
    // It could never reach quorum on chain, so counting it here would only produce a transaction
    // that reverts.
    const outsiderEntry: CollectedAttestation<unknown> = {
      operator: 'impostor',
      attestation: { note: 'facts' },
      digest: DIGEST_A,
      signature: await OUTSIDER.sign({ hash: DIGEST_A }),
      attestor: OUTSIDER.address as Hex,
    };
    await expect(
      assembleQuorum([await collect(0, DIGEST_A), await collect(1, DIGEST_A), outsiderEntry], options),
    ).rejects.toThrow(/only 2 of 3/);
  });

  it('fails with NO_QUORUM when nothing valid was collected', async () => {
    await expect(assembleQuorum([], options)).rejects.toThrow(/no valid attestations/);
  });
});

describe('progress reporting', () => {
  it('reports the largest agreeing group, not the raw count', async () => {
    // A user watching three operators disagree must not see "3 of 3" and then a failure.
    const progress = await quorumProgress([await collect(0, DIGEST_A), await collect(1, DIGEST_B), await collect(2, DIGEST_B)], 3);
    expect(progress.matching).toBe(2);
    expect(progress.distinctFactSets).toBe(2);
  });

  it('maps counts to UI statuses', () => {
    expect(statusFromMatching(0)).toBe('VERIFYING');
    expect(statusFromMatching(1)).toBe('ATTESTATIONS_1_OF_3');
    expect(statusFromMatching(2)).toBe('ATTESTATIONS_2_OF_3');
    expect(statusFromMatching(3)).toBe('READY_TO_SUBMIT');
  });
});

describe('submission', () => {
  const group: QuorumGroup<unknown> = {
    digest: DIGEST_A,
    attestation: {},
    signatures: ['0x01' as Hex],
    signers: [accounts[0]!.address as Hex],
    operators: ['a'],
  };

  const noSleep = { sleep: async () => {} };

  function submitter(over: Partial<Submitter> = {}): Submitter & { sent: number; simulated: number } {
    const s = {
      sent: 0,
      simulated: 0,
      async simulate() {
        s.simulated++;
      },
      async send(): Promise<Hex> {
        s.sent++;
        return `0x${'cc'.repeat(32)}` as Hex;
      },
      async waitForReceipt() {
        return true;
      },
      ...over,
    };
    return s as Submitter & { sent: number; simulated: number };
  }

  it('simulates before sending', async () => {
    const s = submitter();
    const record = await submitQuorum(group, s, new MemorySubmissionStore(), noSleep);
    expect(s.simulated).toBe(1);
    expect(record.status).toBe('CONFIRMED');
    expect(record.txHash).toBeTruthy();
  });

  it('does not broadcast when simulation says it would revert', async () => {
    // An expired offer or a rotated epoch costs nothing to discover in simulation and real gas to
    // discover on chain.
    const s = submitter({
      simulate: async () => {
        throw new Error('OfferExpired');
      },
    });
    const record = await submitQuorum(group, s, new MemorySubmissionStore(), noSleep);
    expect(s.sent).toBe(0);
    expect(record.status).toBe('REJECTED');
    expect(record.error).toContain('OfferExpired');
  });

  it('is idempotent — a second call does not rebroadcast', async () => {
    const store = new MemorySubmissionStore();
    const s = submitter();
    await submitQuorum(group, s, store, noSleep);
    await submitQuorum(group, s, store, noSleep);
    expect(s.sent).toBe(1);
  });

  it('retries a broadcast failure, since the digest is still unconsumed', async () => {
    let attempts = 0;
    const s = submitter({
      send: async () => {
        attempts++;
        if (attempts < 3) throw new Error('RPC timeout');
        return `0x${'dd'.repeat(32)}` as Hex;
      },
    });
    const record = await submitQuorum(group, s, new MemorySubmissionStore(), { ...noSleep, maxAttempts: 3 });
    expect(attempts).toBe(3);
    expect(record.status).toBe('CONFIRMED');
  });

  it('gives up after maxAttempts and records why', async () => {
    const s = submitter({
      send: async () => {
        throw new Error('RPC down');
      },
    });
    const record = await submitQuorum(group, s, new MemorySubmissionStore(), { ...noSleep, maxAttempts: 2 });
    expect(record.status).toBe('REJECTED');
    expect(record.attempts).toBe(2);
    expect(record.error).toContain('RPC down');
  });

  it('records an on-chain revert as REJECTED, not CONFIRMED', async () => {
    const s = submitter({ waitForReceipt: async () => false });
    const record = await submitQuorum(group, s, new MemorySubmissionStore(), noSleep);
    expect(record.status).toBe('REJECTED');
    expect(record.error).toContain('reverted');
  });
});
