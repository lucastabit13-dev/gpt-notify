#!/usr/bin/env node

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const packageRoot = path.resolve(__dirname, '..');
const command = process.argv[2] || 'help';

function usage() {
  console.log(`Codex Gpt Notify

Usage:
  codex-gpt-notify setup   Install global Codex hooks and configure ntfy
  codex-gpt-notify test    Send a test push through the saved ntfy topic
  codex-gpt-notify help    Show this help`);
}

function setup() {
  if (process.platform !== 'win32') {
    console.error('The current installer supports Windows only.');
    process.exitCode = 1;
    return;
  }

  const setupScript = path.join(packageRoot, 'scripts', 'setup.ps1');
  const result = spawnSync(
    'powershell.exe',
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', setupScript],
    { stdio: 'inherit' },
  );

  if (result.error) {
    console.error(`Could not start PowerShell: ${result.error.message}`);
    process.exitCode = 1;
  } else if (result.status !== 0) {
    process.exitCode = result.status || 1;
  }
}

async function sendTest() {
  if (process.platform !== 'win32') {
    console.error('The current installer supports Windows only.');
    process.exitCode = 1;
    return;
  }

  const appData = process.env.APPDATA;
  if (!appData) {
    console.error('APPDATA is not set. Run this command from Windows.');
    process.exitCode = 1;
    return;
  }

  const configPath = path.join(appData, 'GptNotify', 'config.json');
  let config;
  try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8').replace(/^\uFEFF/, ''));
  } catch (error) {
    console.error(`Could not read ${configPath}: ${error.message}`);
    console.error('Run "codex-gpt-notify setup" first.');
    process.exitCode = 1;
    return;
  }

  if (typeof config.topic !== 'string' || !/^[A-Za-z0-9_-]{16,128}$/.test(config.topic)) {
    console.error('The saved ntfy topic is missing or invalid. Rerun setup.');
    process.exitCode = 1;
    return;
  }

  const server = (config.server || 'https://ntfy.sh').replace(/\/+$/, '');
  if (!server.startsWith('https://')) {
    console.error('The configured ntfy server must use HTTPS.');
    process.exitCode = 1;
    return;
  }

  try {
    const response = await fetch(`${server}/${config.topic}`, {
      method: 'POST',
      headers: { Title: 'Codex Gpt Notify test', Priority: 'high' },
      body: 'Manual test notification from codex-gpt-notify.',
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) {
      throw new Error(`ntfy returned HTTP ${response.status}`);
    }
    console.log(`ntfy accepted the test notification (HTTP ${response.status}).`);
  } catch (error) {
    console.error(`Could not send the test notification: ${error.message}`);
    process.exitCode = 1;
  }
}

if (command === 'setup') {
  setup();
} else if (command === 'test') {
  sendTest();
} else {
  usage();
  if (command !== 'help' && command !== '--help' && command !== '-h') {
    process.exitCode = 1;
  }
}
