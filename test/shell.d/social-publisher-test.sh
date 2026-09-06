#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-launch-browser" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >>"$OMARCHY_TEST_BROWSER_URL"
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$OMARCHY_TEST_NOTIF"
SH

cat >"$stub_bin/wl-copy" <<'SH'
#!/bin/bash
cat >"$OMARCHY_TEST_CLIPBOARD"
SH

chmod +x "$stub_bin"/*
export PATH="$stub_bin:$ROOT/bin:$PATH"
export OMARCHY_TEST_BROWSER_URL="$tmp_dir/browser-url"
export OMARCHY_TEST_NOTIF="$tmp_dir/notification"
export OMARCHY_TEST_CLIPBOARD="$tmp_dir/clipboard"

# Test 1: Publish command route and help
help_output=$("$ROOT/bin/omarchy" publish --help)
[[ $help_output == *"Publish screen recordings, GIFs, or images to social media"* ]] || \
  fail "omarchy publish --help displays summary"
pass "omarchy publish --help displays summary"

alias_output=$("$ROOT/bin/omarchy" social --help)
[[ $alias_output == *"omarchy-publish"* ]] || \
  fail "omarchy social resolves to omarchy-publish"
pass "omarchy social resolves to omarchy-publish"

# Test 2: Menu integration
grep -F '"trigger.share.social"' "$ROOT/default/omarchy/omarchy-menu.jsonc" >/dev/null || \
  fail "menu contains trigger.share.social"
grep -F '"trigger.share.social-latest"' "$ROOT/default/omarchy/omarchy-menu.jsonc" >/dev/null || \
  fail "menu contains trigger.share.social-latest"
pass "menu contains social media triggers"

# Test 3: Non-interactive execution for X
test_img="$tmp_dir/test.png"
touch "$test_img"

rm -f "$OMARCHY_TEST_BROWSER_URL"
"$ROOT/bin/omarchy-publish" --platform=x --text="Hello Omarchy" "$test_img"

captured_url=$(cat "$OMARCHY_TEST_BROWSER_URL" 2>/dev/null || true)
[[ $captured_url == *"x.com/intent/post?text=Hello%20Omarchy"* ]] || \
  fail "omarchy-publish generates proper X intent URL" "$captured_url"
pass "omarchy-publish generates proper X intent URL"

# Test 4: Bluesky intent
rm -f "$OMARCHY_TEST_BROWSER_URL"
"$ROOT/bin/omarchy-publish" --platform=bluesky --text="Post to Bsky" "$test_img"
captured_bsky_url=$(cat "$OMARCHY_TEST_BROWSER_URL" 2>/dev/null || true)
[[ $captured_bsky_url == *"bsky.app/intent/compose?text=Post%20to%20Bsky"* ]] || \
  fail "omarchy-publish generates proper Bluesky compose URL" "$captured_bsky_url"
pass "omarchy-publish generates proper Bluesky compose URL"

# Test 5: Latest media detection
rec_marker="/tmp/omarchy-screenrecord-filename"
echo "$test_img" >"$rec_marker"
rm -f "$OMARCHY_TEST_BROWSER_URL"
"$ROOT/bin/omarchy-publish" --latest --platform=x --text="From latest"
latest_url=$(cat "$OMARCHY_TEST_BROWSER_URL" 2>/dev/null || true)
[[ $latest_url == *"From%20latest"* ]] || fail "omarchy-publish uses latest capture marker"
pass "omarchy-publish uses latest capture marker"
rm -f "$rec_marker"

# Test 6: Multi-platform publishing (comma-separated)
rm -f "$OMARCHY_TEST_BROWSER_URL"
"$ROOT/bin/omarchy-publish" --platform=x,bluesky,threads --text="Multi-platform post" "$test_img"
multi_urls=$(cat "$OMARCHY_TEST_BROWSER_URL" 2>/dev/null || true)
[[ $multi_urls == *"x.com/intent/post"* ]] || fail "multi-platform publishes to X"
[[ $multi_urls == *"bsky.app/intent/compose"* ]] || fail "multi-platform publishes to Bluesky"
[[ $multi_urls == *"threads.net/intent/post"* ]] || fail "multi-platform publishes to Threads"
pass "omarchy-publish supports multiple comma-separated platforms"

# Test 7: Multiple media files
test_img2="$tmp_dir/test2.png"
touch "$test_img2"
rm -f "$OMARCHY_TEST_BROWSER_URL" "$OMARCHY_TEST_CLIPBOARD"
"$ROOT/bin/omarchy-publish" --platform=x --text="Two photos" "$test_img" "$test_img2"
clipboard_content=$(cat "$OMARCHY_TEST_CLIPBOARD" 2>/dev/null || true)
[[ $clipboard_content == *"file://$test_img"* ]] || fail "clipboard has first image URI"
[[ $clipboard_content == *"file://$test_img2"* ]] || fail "clipboard has second image URI"
pass "omarchy-publish copies multiple media files as uri-list to clipboard"

# Test 8: Cross-platform mention translation
mock_config_dir="$tmp_dir/.config/omarchy"
mkdir -p "$mock_config_dir"
cat >"$mock_config_dir/social_mentions.json" <<'JSON'
{
  "omarchy": {
    "x": "@omarchy_os",
    "bluesky": "@omarchy.bsky.social"
  }
}
JSON
rm -f "$OMARCHY_TEST_BROWSER_URL"
XDG_CONFIG_HOME="$tmp_dir/.config" "$ROOT/bin/omarchy-publish" --platform=x,bluesky --text="Great update @omarchy" "$test_img"
tag_urls=$(cat "$OMARCHY_TEST_BROWSER_URL" 2>/dev/null || true)
[[ $tag_urls == *"x.com/intent/post?text=Great%20update%20%40omarchy_os"* ]] || fail "X mention replaced"
[[ $tag_urls == *"bsky.app/intent/compose?text=Great%20update%20%40omarchy.bsky.social"* ]] || fail "Bluesky mention replaced"
pass "omarchy-publish translates cross-platform mentions from social_mentions.json"
