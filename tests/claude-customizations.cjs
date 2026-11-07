'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { after, test } = require('node:test');
const { stripVTControlCharacters } = require('node:util');

// Git exports repository overrides while running commit hooks. Isolate this
// test process before calling the in-process gitBranch helper as well as any
// fixture subprocess: otherwise git -C can still target the caller's checkout.
for (const key of Object.keys(process.env)) {
  if (key.startsWith('GIT_')) delete process.env[key];
}
// Git for Windows rejects Node's device path (\\.\nul) as a config file.
// A regular empty file and directory work consistently on every platform.
const gitEnvironment = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-git-env-'));
after(() => fs.rmSync(gitEnvironment, { recursive: true, force: true }));
process.env.GIT_CONFIG_GLOBAL = path.join(gitEnvironment, 'empty.gitconfig');
fs.writeFileSync(process.env.GIT_CONFIG_GLOBAL, '');
process.env.GIT_CONFIG_NOSYSTEM = '1';
process.env.GIT_TEMPLATE_DIR = path.join(gitEnvironment, 'empty-template');
fs.mkdirSync(process.env.GIT_TEMPLATE_DIR);

// The helpers come from an installed coding-agent-kit: DOTFILES_TEST_KIT_HOME
// names a home it is installed in (CI installs the real kit there, through
// scripts/payload-update.sh); without one, the helper case skips.
const kitHome = process.env.DOTFILES_TEST_KIT_HOME;
const scripts = kitHome ? path.join(kitHome, '.claude', 'coding-agent-kit') : '';
if (kitHome && !fs.statSync(path.join(scripts, 'statusline.cjs'), { throwIfNoEntry: false })?.isFile()) {
  throw new Error(`DOTFILES_TEST_KIT_HOME=${kitHome} has no installed coding-agent-kit helpers in ${scripts}.`);
}
const settings = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../home/.policy/claude-settings.json'), 'utf8'));

test('Git fixtures use ordinary empty config and template paths', () => {
  assert.ok(fs.lstatSync(process.env.GIT_CONFIG_GLOBAL).isFile());
  assert.equal(fs.readFileSync(process.env.GIT_CONFIG_GLOBAL, 'utf8'), '');
  assert.ok(fs.lstatSync(process.env.GIT_TEMPLATE_DIR).isDirectory());
  assert.deepEqual(fs.readdirSync(process.env.GIT_TEMPLATE_DIR), []);
});

// Each settings.json command with the platform it sees forced: coding-agent-kit
// installs no helpers on native Windows, so there the command runs none and
// exits 0; elsewhere a missing helper stays visible.
const helperCommands = () => [
  ['statusline.cjs', settings.statusLine.command],
  ['notify.cjs', settings.hooks.Notification[0].hooks[0].command],
  ['check-git-hooks.cjs', settings.hooks.PreToolUse[0].hooks[0].command],
];
const runAs = (platform, home, command, environment = {}) => {
  const match = command.match(/^node -e "([^"]+)"$/);
  assert.ok(match, command);
  return spawnSync(process.execPath, ['-e',
    `Object.defineProperty(process, 'platform', { value: '${platform}' }); ` +
    'require("os").homedir = () => process.env.CLAUDE_DOTFILES_TEST_HOME; ' + match[1]], {
    env: { ...process.env, ...environment, CLAUDE_DOTFILES_TEST_HOME: home }, input: '{}', encoding: 'utf8', timeout: 5000,
  });
};

test('a missing helper is silent only on native Windows', () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'claude home '));
  try {
    for (const [name, command] of helperCommands()) {
      assert.ok(command.includes(`/.claude/coding-agent-kit/${name}`), command);
      const windows = runAs('win32', temporary, command);
      assert.deepEqual([windows.status, windows.stdout, windows.stderr], [0, '', ''], command);
      const unix = runAs('linux', temporary, command);
      assert.equal(unix.status, 1, command);
      assert.equal(unix.stdout, '');
      assert.ok(unix.stderr.includes(path.join(temporary, '.claude', 'coding-agent-kit', name)) ||
        unix.stderr.includes(`${temporary}/.claude/coding-agent-kit/${name}`), unix.stderr);
    }
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
});

test('a present helper runs off native Windows, its exit status kept; native Windows runs none', () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'claude home '));
  try {
    const target = path.join(temporary, '.claude', 'coding-agent-kit');
    fs.mkdirSync(target, { recursive: true });
    for (const [name] of helperCommands()) {
      fs.writeFileSync(path.join(target, name),
        `exports.main = () => { process.stdout.write('${name} ran'); process.exitCode = 2; };\n`);
    }
    for (const platform of ['linux', 'darwin']) {
      for (const [name, command] of helperCommands()) {
        const result = runAs(platform, temporary, command);
        assert.deepEqual([result.status, result.stdout], [2, `${name} ran`], `${platform}: ${command}: ${result.stderr}`);
      }
    }
    for (const [, command] of helperCommands()) {
      const windows = runAs('win32', temporary, command);
      assert.deepEqual([windows.status, windows.stdout, windows.stderr], [0, '', ''], command);
    }
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
});

test('status line enables captured-output colors and preserves explicit overrides', () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'claude color home '));
  try {
    const target = path.join(temporary, '.claude', 'coding-agent-kit');
    fs.mkdirSync(target, { recursive: true });
    fs.writeFileSync(path.join(target, 'statusline.cjs'),
      "exports.main = () => process.stdout.write(process.env.CODING_AGENT_KIT_COLOR ?? 'unset');\n");
    for (const value of [undefined, 'auto', 'always', 'never', '']) {
      const result = runAs('linux', temporary, settings.statusLine.command, { CODING_AGENT_KIT_COLOR: value });
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout, value ?? 'always');
    }
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
});

test('portable commands run the installed helpers through a home path containing spaces',
  { skip: kitHome ? false : 'no installed coding-agent-kit (DOTFILES_TEST_KIT_HOME)' }, () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'claude home '));
  try {
    const target = path.join(temporary, '.claude', 'coding-agent-kit');
    fs.mkdirSync(target, { recursive: true });
    for (const name of fs.readdirSync(scripts)) fs.copyFileSync(path.join(scripts, name), path.join(target, name));
    const execute = (command, input) => {
      const match = command.match(/^node -e "([^"]+)"$/);
      assert.ok(match, command);
      return spawnSync(process.execPath, ['-e',
        'require("os").homedir = () => process.env.CLAUDE_DOTFILES_TEST_HOME; ' + match[1]], {
        env: { ...process.env, CLAUDE_DOTFILES_TEST_HOME: temporary },
        input: JSON.stringify(input), encoding: 'utf8', timeout: 5000,
      });
    };
    assert.equal(stripVTControlCharacters(execute(settings.statusLine.command, {}).stdout).trim(), 'Claude | ctx ? | ~$?');
    const notify = settings.hooks.Notification[0].hooks[0];
    const output = execute(notify.command, { hook_event_name: 'Notification', notification_type: 'idle_prompt' });
    assert.equal(output.status, 0, output.stderr);
    assert.ok(JSON.parse(output.stdout).terminalSequence);
    const guard = execute(settings.hooks.PreToolUse[0].hooks[0].command,
      { tool_input: { command: 'git commit --no-verify' } });
    assert.equal(guard.status, 2, guard.stderr);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
});
