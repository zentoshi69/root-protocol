#!/usr/bin/env node

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const reportPath = resolve(process.argv[2] ?? 'contracts/lcov.info');
const text = readFileSync(reportPath, 'utf8');

const thresholds = {
  aggregate: { lines: 95, functions: 95, branches: 85 },
  perFile: { lines: 90, functions: 90, branches: 70 },
};

const metrics = [];
for (const record of text.split('end_of_record')) {
  const values = new Map();
  for (const line of record.split('\n')) {
    const separator = line.indexOf(':');
    if (separator === -1) continue;
    values.set(line.slice(0, separator), line.slice(separator + 1));
  }

  const source = values.get('SF');
  if (!source) continue;
  const normalized = source.replaceAll('\\', '/');
  if (!normalized.includes('/src/') && !normalized.startsWith('src/')) continue;

  metrics.push({
    source: normalized,
    lines: { hit: Number(values.get('LH') ?? 0), found: Number(values.get('LF') ?? 0) },
    functions: { hit: Number(values.get('FNH') ?? 0), found: Number(values.get('FNF') ?? 0) },
    branches: { hit: Number(values.get('BRH') ?? 0), found: Number(values.get('BRF') ?? 0) },
  });
}

if (metrics.length === 0) {
  throw new Error(`no contracts/src coverage records found in ${reportPath}`);
}

const percent = ({ hit, found }) => (found === 0 ? 100 : (hit * 100) / found);
const format = (metric) => `${percent(metric).toFixed(2)}% (${metric.hit}/${metric.found})`;
const failures = [];

for (const file of metrics) {
  for (const kind of ['lines', 'functions', 'branches']) {
    if (file[kind].found === 0) continue;
    const actual = percent(file[kind]);
    const required = thresholds.perFile[kind];
    if (actual < required) {
      failures.push(`${file.source}: ${kind} ${format(file[kind])} is below ${required}%`);
    }
  }
}

const aggregate = {
  lines: { hit: 0, found: 0 },
  functions: { hit: 0, found: 0 },
  branches: { hit: 0, found: 0 },
};
for (const file of metrics) {
  for (const kind of ['lines', 'functions', 'branches']) {
    aggregate[kind].hit += file[kind].hit;
    aggregate[kind].found += file[kind].found;
  }
}

for (const kind of ['lines', 'functions', 'branches']) {
  const actual = percent(aggregate[kind]);
  const required = thresholds.aggregate[kind];
  if (actual < required) {
    failures.push(`aggregate ${kind} ${format(aggregate[kind])} is below ${required}%`);
  }
}

console.log(
  `Solidity source coverage: lines ${format(aggregate.lines)}, ` +
    `functions ${format(aggregate.functions)}, branches ${format(aggregate.branches)}`,
);

if (failures.length > 0) {
  for (const failure of failures) console.error(`coverage gate: ${failure}`);
  process.exitCode = 1;
}
