'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { after, test } = require('node:test');

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

// The helpers are links into the coding-agent-kit submodule.
const scripts = path.resolve(__dirname, '../common/claude/.claude/dotfiles');
if (!fs.statSync(path.join(scripts, 'statusline.cjs'), { throwIfNoEntry: false })?.isFile()) {
  throw new Error('coding-agent-kit submodule not initialized; run git submodule update --init --recursive.');
}
const settings = JSON.parse(fs.readFileSync(path.join(scripts, '../settings.json'), 'utf8'));

test('Git fixtures use ordinary empty config and template paths', () => {
  assert.ok(fs.lstatSync(process.env.GIT_CONFIG_GLOBAL).isFile());
  assert.equal(fs.readFileSync(process.env.GIT_CONFIG_GLOBAL, 'utf8'), '');
  assert.ok(fs.lstatSync(process.env.GIT_TEMPLATE_DIR).isDirectory());
  assert.deepEqual(fs.readdirSync(process.env.GIT_TEMPLATE_DIR), []);
});

test('portable launchers resolve stowed helpers through a home path containing spaces', () => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'claude home '));
  try {
    const target = path.join(temporary, '.claude', 'dotfiles');
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
    assert.equal(execute(settings.statusLine.command, {}).stdout.trim(), 'Claude | ctx ? | ~$?');
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
