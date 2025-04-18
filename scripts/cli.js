#!/usr/bin/env node

// npm install axios yargs cli-tablenode musicctl.js --zone="Kitchen" --what=all3

const axios = require('axios');
const yargs = require('yargs/yargs');
const { hideBin } = require('yargs/helpers');
const querystring = require('querystring');
const Table = require('cli-table3');

const argv = yargs(hideBin(process.argv))
  .option('zone', { type: 'string', describe: 'Zone name (e.g. Kitchen)' })
  .option('mpath', { type: 'string', describe: 'Music path (e.g. /)' })
  .option('queue', { type: 'string', describe: 'Queue ID to view' })
  .option('what', { type: 'string', choices: ['globals', 'music', 'zones', 'zone', 'queue', 'none', 'all'], describe: 'What to view' })
  .option('action', { type: 'string', describe: 'Action to perform' })
  .option('lastupdate', { type: 'number', describe: 'Timestamp of last update' })
  .option('link', { type: 'string', describe: 'Zone to link with given zone' })
  .option('volume', { type: 'number', describe: 'Volume to set' })
  .option('savename', { type: 'string', describe: 'Save queue with this name' })
  .option('NoWait', { type: 'number', choices: [0, 1], describe: 'Set NoWait to 1 to skip waiting for update' })
  .help()
  .alias('help', 'h')
  .argv;

const baseUrl = 'http://127.0.0.1:9999/api';

function printTableFromArray(dataArray, title) {
  if (!Array.isArray(dataArray)) return;

  if (dataArray.length === 0) {
    console.log(`\n${title}: No data`);
    return;
  }

  const keys = Object.keys(dataArray[0]);
  const table = new Table({ head: keys });

  for (const item of dataArray) {
    table.push(keys.map(key => item[key]));
  }

  console.log(`\n=== ${title} ===`);
  console.log(table.toString());
}

(async () => {
  const params = {};
  const fields = ['zone', 'mpath', 'queue', 'what', 'action', 'lastupdate', 'link', 'volume', 'savename', 'NoWait'];
  for (const field of fields) {
    if (argv[field] !== undefined) {
      params[field] = argv[field];
    }
  }

  const query = querystring.stringify(params);
  const url = `${baseUrl}?${query}`;

  try {
    const response = await axios.get(url);
    const data = response.data;

    // Pretty table output for known collections
    if (data.music_loop) printTableFromArray(data.music_loop, 'Music Library');
    if (data.queue_loop) printTableFromArray(data.queue_loop, 'Queue');
    if (data.zones_loop) printTableFromArray(data.zones_loop.map(z => z.ZONE_MEMBERS[0]), 'Zones');

    // Fallback JSON view for other data
    const omitKeys = ['music_loop', 'queue_loop', 'zones_loop'];
    const rest = Object.fromEntries(Object.entries(data).filter(([k]) => !omitKeys.includes(k)));
    if (Object.keys(rest).length > 0) {
      console.log('\n=== Raw Data ===');
      console.log(JSON.stringify(rest, null, 2));
    }

  } catch (err) {
    console.error(`Error: ${err.message}`);
  }
})();
