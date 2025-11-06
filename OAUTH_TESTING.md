# OAuth Testing Guide

Thanos now supports OAuth authentication for GitHub Copilot and Anthropic Claude Max!

---

## Prerequisites

- **GitHub Account** (for Copilot)
- **Claude Max Subscription** ($20/month) - for Anthropic OAuth

---

## Testing GitHub OAuth (Copilot)

### Authenticate

```bash
cargo run --bin thanos-auth -- github
```

**Flow:**
1. Browser opens to `https://github.com/login/device`
2. Enter the 8-character code shown in terminal
3. Click "Authorize" on GitHub
4. Wait ~5-10 seconds
5. ✅ Tokens stored in system keyring!

**What you get:**
- GitHub access token
- Copilot inference token
- Expires: Check with `status` command

---

## Testing Anthropic OAuth (Claude Max)

### Authenticate

```bash
cargo run --bin thanos-auth -- anthropic
```

**Flow:**
1. Browser opens to `https://console.anthropic.com/oauth/authorize`
2. Log in with your Claude Max account
3. Click "Authorize"
4. You'll see a code like: `abc123...#def456...`
5. Copy the **ENTIRE** code (including `#`)
6. Paste it back in the terminal
7. ✅ Tokens stored in system keyring!

**What you get:**
- Access token (expires in 8 hours)
- Refresh token (long-lived)
- Organization + account info

---

## Check Authentication Status

```bash
cargo run --bin thanos-auth -- status
```

**Output:**
```
🔐 Authentication Status

✅ GitHub Copilot
   Provider ID: github_copilot
   Expires: 2025-11-07 12:30:00 UTC (23 hours remaining)

✅ Anthropic Claude Max
   Provider ID: anthropic_max
   Expires: 2025-11-06 20:30:00 UTC (7 hours remaining)
```

---

## Clear All Tokens

```bash
cargo run --bin thanos-auth -- clear
```

---

## Token Storage

Tokens are stored securely in your system keyring:

- **Linux**: GNOME Keyring / KWallet (Secret Service)
- **macOS**: Keychain
- **Windows**: Credential Manager

**Service name**: `thanos`
**Provider IDs**:
- `github_copilot` - GitHub Copilot tokens
- `anthropic_max` - Anthropic Claude Max tokens

---

## Using Tokens in Thanos

After authenticating, update `config.toml`:

```toml
# Enable GitHub Copilot (OAuth)
[providers.github_copilot]
enabled = true
auth_method = "oauth"
model = "gpt-4"

# Enable Anthropic Claude Max (OAuth)
[providers.anthropic_max]
enabled = true
auth_method = "oauth"
model = "claude-3-7-sonnet-20250219"
```

Thanos will automatically load tokens from keyring when it starts!

---

## Troubleshooting

### GitHub: "Authorization pending"
- Wait up to 5 minutes
- Make sure you entered the code on GitHub
- Check you clicked "Authorize"

### Anthropic: "State mismatch"
- Make sure you copied the **entire** code including `#`
- Try again with a fresh authorization

### Anthropic: "Invalid format"
- The code format is: `code#state`
- Example: `abc123def456#xyz789abc123`
- Don't copy extra spaces or newlines

### Token expired
- Just run the auth command again
- For Anthropic: Tokens auto-refresh (TODO)

---

## Next Steps

Once you've authenticated:

1. Enable the provider in `config.toml`
2. Start Thanos: `cargo run`
3. Test with zeke CLI or curl:

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "anthropic_max/claude-3.7-sonnet",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

---

**Ready to authenticate? Start with:**

```bash
# GitHub Copilot
cargo run --bin thanos-auth -- github

# OR Anthropic Claude Max
cargo run --bin thanos-auth -- anthropic
```

Let me know when you're ready to test! 🚀
