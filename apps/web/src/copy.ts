/**
 * Mandated product copy, in one place.
 *
 * `docs/TRUST_ASSUMPTIONS.md` fixes both what the UI must say and what it must never say. Keeping
 * the strings here rather than scattered through components means the rule is testable: `copy.test`
 * asserts every exported string against the banned-phrase list, so a well-meaning edit that
 * introduces "trustless bridge" fails the build instead of shipping.
 */

/** Phrases that must never appear in user-facing text. Checked against every export below. */
export const BANNED_PHRASES = [
  'trustless bridge',
  'trustless',
  'atomic swap',
  'fully decentralized bridge',
  'your bitcoin is secured by the protocol',
  'verified by bitcoin',
  'wrapped',
  'bridged',
] as const;

/** The five statements the spec requires to appear prominently. */
export const REQUIRED_STATEMENTS = {
  puppetStays: 'Your Bitcoin Puppet never leaves Bitcoin.',
  quorum: 'A 3-of-5 verifier quorum confirms ownership and BTC payments.',
  ethPayout: 'ETH payout is on Robinhood Chain.',
  btcPayout: 'BTC payout is native Bitcoin sent by a bonded solver.',
  oneHoodPup: 'One verified HoodPup may be minted per protocol Root.',
} as const;

export const TRUST_MODEL = {
  heading: 'How this is verified',
  body:
    'Five independent operators each check Bitcoin themselves, and three must agree before ' +
    'anything settles. They can never move, spend or encumber your Puppet — the protocol holds no ' +
    'Bitcoin key. A dishonest majority could assert a false fact, which is why the operators are ' +
    'independent and publicly identified.',
  // Deliberately phrased without the banned words, even in denial. The copy check is a blunt
  // substring match by design — teaching it to parse negations would make it fail exactly where a
  // careless edit turns "not a bridge" into "a bridge". Concrete language is better copy anyway.
  notABridge:
    'This is an attested settlement system. Your Puppet is not converted into a token on another ' +
    'chain, and nobody holds it on your behalf. It stays exactly where it is, under your key.',
} as const;

export const HOLDER = {
  heading: 'Approve a HoodPup from your Bitcoin Puppet',
  signingIntro:
    'You will sign one message with the Bitcoin wallet that controls this Puppet. Signing does ' +
    'not spend it, transfer it, or give anyone else the ability to.',
  neverSeed:
    'We will never ask for your seed phrase or private key. If a page or a person asks, it is not us.',
  coldWallet:
    'Using a cold wallet? Export the signing request, sign it offline on your device, and paste ' +
    'the signature back. The Puppet stays where it is.',
  // Phrased without the word "import" even in refusal. A user skimming a warning takes away the
  // verbs they see, and "import" next to a wallet is the single most dangerous one on this page.
  unsupportedWallet:
    'This wallet cannot produce the proof this protocol requires. The trust-minimised claim is not ' +
    'available for this wallet type yet — and we would rather say so plainly than have you move ' +
    'your Puppet or copy it into other software.',
  reviewBeforeSigning:
    'Read the exact terms below before you sign. The payout address shown is the only address that ' +
    'can be paid — it is part of what you are signing.',
} as const;

export const BUYER = {
  heading: 'Make an offer for a HoodPup',
  splitExplainer:
    'Every paid mint splits the same way: half to the current Bitcoin Puppet controller, a quarter ' +
    'to the Bitcoin Puppets ecosystem treasury, a quarter to the protocol. These percentages are ' +
    'compiled into the contract and cannot be changed by anyone.',
  noCancel:
    'You cannot cancel an open offer. A Bitcoin holder may be part-way through a cold-wallet ' +
    'signing ceremony, and a cancellable offer would let a buyer bait a signature and withdraw. ' +
    'Your ETH returns automatically at expiry, or immediately if someone else mints this Root first.',
  btcModeRisk:
    'In BTC mode a bonded solver sends the exact satoshis first and is reimbursed from your escrow ' +
    'only after three verifiers confirm the precise Bitcoin output. If no solver takes the quote, ' +
    'your offer expires and refunds.',
  noOracle:
    'The satoshi amount and the ETH reimbursement are both fixed by you, now. There is no price ' +
    'feed involved in settlement.',
} as const;

export const PAYOUT = {
  heading: 'Your claimable balance',
  explainer:
    'Payouts are credited to you inside the vault rather than pushed to your wallet. That way a ' +
    'payout address that rejects a transfer can never block someone else’s mint.',
  gasless:
    'No ETH for gas? Sign a withdrawal authorisation and a relayer can submit it for you. The funds ' +
    'go where you specify.',
  distinction: 'Claimable credit is not the same as your wallet balance until you withdraw it.',
} as const;

export const ROOT_OWNERSHIP = {
  heading: 'Root ownership',
  explainer:
    'Root-linked value follows whoever currently proves control of the Bitcoin Puppet. When it ' +
    'changes hands, a watcher records the move and future value is held until the new owner proves ' +
    'control.',
  lagWarning:
    'Verification reflects what watchers have reported, and can lag Bitcoin. Value accrued during ' +
    'that gap is held for the Root rather than paid out, so it is recoverable.',
} as const;

export const TOURS = {
  heading: 'Tours',
  explainer:
    'Lend a HoodPup temporarily without transferring it. The owner keeps the NFT throughout.',
  noReward:
    'Tours record provenance and miles. There is no token, no cash and no share of revenue.',
  notHumanity:
    'Tour rules enforce one wallet per token per season. That is not proof of a unique person, and ' +
    'we do not claim it is.',
} as const;

/** Every user-facing string, flattened, so tests can sweep them all. */
export function allCopyStrings(): string[] {
  const groups = [REQUIRED_STATEMENTS, TRUST_MODEL, HOLDER, BUYER, PAYOUT, ROOT_OWNERSHIP, TOURS];
  return groups.flatMap((g) => Object.values(g as Record<string, string>));
}
