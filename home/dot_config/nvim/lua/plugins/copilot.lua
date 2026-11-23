-- Copilot sends the text of every buffer it attaches to. Keep it off files that
-- commonly hold credentials, keys or API tokens.
local secret_dirs = {
  "/.ssh/",
  "/.gnupg/",
  "/.aws/",
  "/.secrets/",
  "/private_dot_secrets/",
  "/.config/chezmoi/age/",
  "/.config/gh/",
  "/.config/gcloud/",
  "/.config/rclone/",
  "/.cache/huggingface/",
  "/.huggingface/",
  "/.docker/",
  "/.kube/",
  "/.kaggle/",
}
local secret_names = {
  ".netrc",
  ".pypirc",
  ".git-credentials",
  ".npmrc",
  "credentials",
  ".credentials.json",
  "auth.json",
  "token",
  "stored_tokens",
}

local function sensitive(name)
  for _, dir in ipairs(secret_dirs) do
    if name:find(dir, 1, true) then
      return true
    end
  end
  local base = vim.fs.basename(name)
  return vim.tbl_contains(secret_names, base)
    or base:find("^%.env") ~= nil
    or base:find("%.env$") ~= nil
    or base:find("%.pem$") ~= nil
    or base:find("%.key$") ~= nil
    or base:find("%.age$") ~= nil
    or base:find("^id_[%w_]+$") ~= nil
end

return {
  {
    "zbirenbaum/copilot.lua",
    opts = {
      should_attach = function(buf, name)
        return require("copilot.config.should_attach").default(buf, name) and not sensitive(name)
      end,
      -- Protein Data Bank coordinate files are large and hold no code.
      filetypes = { pdb = false },
    },
  },
}
