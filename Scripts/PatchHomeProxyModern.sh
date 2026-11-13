#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
set -euo pipefail

PKG_DIR="${1:-luci-app-homeproxy}"
PYTHON_BIN=""
for candidate in python3 python; do
	if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "" 2>/dev/null; then
		PYTHON_BIN="$candidate"
		break
	fi
done
[ -n "$PYTHON_BIN" ] || { echo "ERROR: Python is required to patch HomeProxy" >&2; exit 1; }

"$PYTHON_BIN" - "$PKG_DIR" <<'PY'
from pathlib import Path
import json
import re
import sys

root = Path(sys.argv[1])
views = root / "htdocs/luci-static/resources/view/homeproxy"
resources = root / "htdocs/luci-static/resources"
scripts = root / "root/etc/homeproxy/scripts"
changes = {}

def read(path):
    return changes[path] if path in changes else path.read_text(encoding="utf-8")

def replace(path, old, new, expected=1):
    source = read(path)
    count = source.count(old)
    if count != expected:
        raise SystemExit(f"{path}: expected {expected} occurrence(s) of {old!r}, found {count}")
    changes[path] = source.replace(old, new)

def substitute(path, pattern, replacement, expected=1):
    changes[path], count = re.subn(pattern, replacement, read(path), flags=re.M)
    if count != expected:
        raise SystemExit(f"{path}: expected {expected} match(es) for {pattern!r}, found {count}")

client_types = "'anytls', 'hysteria2', 'shadowsocks', 'trojan', 'tuic', 'vless'"
methods = """[
	'aes-128-gcm', 'aes-192-gcm', 'aes-256-gcm', 'chacha20-ietf-poly1305',
	'xchacha20-ietf-poly1305', '2022-blake3-aes-128-gcm',
	'2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305'
]"""

shared = resources / "homeproxy.js"
substitute(shared, r"(\tshadowsocks_encrypt_methods: \[\n)\t\t/\* Stream \*/\n\t\t'none',\n", r"\1")

node = views / "node.js"
def client_choices(match):
    filtered, count = re.subn(
        r"^\t{1,2}o\.value\('(?:http|hysteria|shadowtls|socks|ssh|vmess)',.*\n", "",
        match[0], flags=re.M,
    )
    if count != 6:
        raise SystemExit(f"{node}: expected six legacy client choices, found {count}")
    return filtered

substitute(node, r"^\to = s\.option\(form\.ListValue, 'type', _\('Type'\)\);[\s\S]*?^\to\.rmempty = false;",
           client_choices)
substitute(node, r"^\t/\* Stream ciphers \*/\n(?:\to\.value\('[^']+'\);\n)+?(?=\to\.default)", "")
substitute(
    node,
    r"^\t{4}if \(type === 'shadowsocks'\) \{\n"
    r"\t{5}let encmode = this\.section\.formvalue\(section_id, 'shadowsocks_encrypt_method'\);\n"
    r"\t{5}if \(encmode === 'none'\)\n\t{6}return true;\n\t{4}\}\n",
    "",
)
substitute(node, r"^\to = s\.option\(form\.Value, 'vmess_alterid'[\s\S]*?(?=\t/\* VMess config end \*/)", "")
replace(node, "\tif (config) {\n\t\tconfig.tls_utls", f"""	if (config && ![{client_types}].includes(config.type))
		return null;

	if (config) {{
		config.tls_utls""")

server = views / "server.js"
replace(server, "\t\to = s.option(form.Flag, 'enabled', _('Enable'));\n",
        "\t\to = s.option(form.Flag, 'enabled', _('Enable'));\n\t\to.readonly = true;\n", expected=2)
replace(server, "\t\to.default = o.enabled;", "\t\to.default = o.disabled;")
substitute(
    server, r"^\t\to = s\.option\(form\.ListValue, 'type', _\('Type'\)\);[\s\S]*?\n\t\to\.rmempty = false;",
    """		o = s.option(form.ListValue, 'type', _('Type'));
		o.value('anytls', _('AnyTLS'));
		o.value('hysteria2', _('Hysteria2'));
		o.value('shadowsocks', _('Shadowsocks'));
		o.value('trojan', _('Trojan'));
		if (features.with_quic)
			o.value('tuic', _('TUIC'));
		o.value('vless', _('VLESS'));
		o.rmempty = false;""",
)

menu = root / "root/usr/share/luci/menu.d/luci-app-homeproxy.json"
entries = json.loads(read(menu))
del entries["admin/services/homeproxy/server"]
changes[menu] = json.dumps(entries, ensure_ascii=False, indent="\t") + "\n"

generator = scripts / "generate_client.uc"
guard = f"const modern_node_types = [ 'direct', {client_types}, 'wireguard' ];\n"
guard += f"const modern_shadowsocks_methods = {methods};\n"
guard += """
function is_modern_node(node) {
	return type(node) === 'object' && node.type in modern_node_types &&
		(node.type !== 'shadowsocks' || node.shadowsocks_encrypt_method in modern_shadowsocks_methods);
}

function filter_modern_nodes(values) {
	return filter(filterExistingNodes(uci, uciconfig, values),
		(id) => is_modern_node(uci.get_all(uciconfig, id)));
}

"""
replace(generator, "let domain_groups = [];", guard + "let domain_groups = [];")
replace(generator, "filterExistingNodes(uci, uciconfig, cfg.urltest_nodes)", "filter_modern_nodes(cfg.urltest_nodes)")
replace(generator, "urltest_nodes = filterExistingNodes(\n\t\t\tuci, uciconfig, uci.get",
        "urltest_nodes = filter_modern_nodes(\n\t\t\tuci.get")
replace(generator, "isEmpty(cfg.node) || isEmpty(uci.get_all(uciconfig, cfg.node))",
        "isEmpty(cfg.node) || !is_modern_node(uci.get_all(uciconfig, cfg.node))")
replace(generator, "if (isEmpty(node))\n\t\t\tdie(`Node ${section_id} is unavailable.`);",
        "if (!is_modern_node(node))\n\t\t\tdie(`Node ${section_id} is unavailable or unsupported.`);")

updater = scripts / "update_subscriptions.uc"
guard = f"const modern_node_types = [ {client_types} ];\n"
guard += f"const modern_shadowsocks_methods = {methods};\n"
guard += r"""
function modern_check(config) {
	if (isEmpty(config) || !(config.type in modern_node_types))
		return null;
	if (config.type === 'shadowsocks' && !(config.shadowsocks_encrypt_method in modern_shadowsocks_methods))
		return null;

	const address = replace(config.address || '', /\[|\]/g, '');
	if (address === 'localhost' || address === '0.0.0.0' || address === '::' || address === '::1' ||
	    match(address, /^127\./) || match(config.label || '', /v2rayN|old client|client too old|update client/)) {
		log(sprintf('Skipping placeholder subscription node: %s.', config.label || config.address || 'NULL'));
		return null;
	}
	return config;
}

"""
replace(updater, "/* Common var end */", guard + "/* Common var end */")
replace(updater, "config = parse_uri(node);", "config = modern_check(parse_uri(node));")
anchor = "\treconcileUrltestNodes(uci, uciconfig, (message) => log(message));"
replace(updater, anchor, anchor + """

	if (isEmpty(uci.get(uciconfig, 'config', 'main_node'))) {
		for (let node in node_result) {
			if (uci.get(uciconfig, node.__section_id) !== ucinode)
				continue;
			uci.set(uciconfig, 'config', 'main_node', node.__section_id);
			log('No main node is selected, switching to the first node.');
			break;
		}
	}""")

source = read(generator)
for required in ("action: 'sniff'", "config.route.default_http_client = 'direct-http';", "tag: 'direct-http'"):
    if required not in source:
        raise SystemExit(f"{generator}: missing upstream sing-box configuration: {required}")
if re.search(r"sniff_override_destination:|sniff: true|download_detour:", source):
    raise SystemExit(f"{generator}: deprecated sing-box configuration is present")

makefile = root / "Makefile"
changes[makefile] = "LUCI_MINIFY_JS:=0\n" + read(makefile)
guard_path = root / "root/usr/libexec/homeproxy-c8-check-legacy"
changes[guard_path] = """#!/bin/sh
legacy() {
	printf 'HomeProxy: retained option %s is unsupported; migrate it manually before starting HomeProxy. Configuration was preserved.\\n' "$1" >&2
	exit 1
}
case "$(uci -q get homeproxy.config.routing_mode)" in
	''|bypass_mainland_china|global) ;;
	*) legacy routing_mode ;;
esac
case "$(uci -q get homeproxy.config.main_udp_node)" in
	''|nil|same) ;;
	*) legacy main_udp_node ;;
esac
if [ -n "$(uci -q get homeproxy.config.main_udp_urltest_nodes)" ]; then
	legacy main_udp_urltest_nodes
fi
case "$(uci -q get homeproxy.control.lan_proxy_mode)" in
	''|disabled) ;;
	*) legacy lan_proxy_mode ;;
esac
for option in lan_direct_ipv6_ips lan_proxy_ipv6_ips lan_global_proxy_ipv6_ips lan_gaming_mode_ipv6_ips lan_gaming_mode_ipv4_ips lan_gaming_mode_mac_addrs lan_global_proxy_ipv4_ips lan_global_proxy_mac_addrs; do
	if [ -n "$(uci -q get "homeproxy.control.$option")" ]; then
		legacy "$option"
	fi
done
exit 0
"""
service = root / "root/etc/init.d/homeproxy"
replace(service, "start_service() {\n", """start_service() {
	if ! /usr/libexec/homeproxy-c8-check-legacy >>"$LOG_PATH" 2>&1; then
		return 1
	fi
""")
migrate = root / "root/etc/uci-defaults/luci-homeproxy"
replace(migrate, 'ucode "/etc/homeproxy/scripts/migrate_config.uc" || exit 1',
        '/usr/libexec/homeproxy-c8-check-legacy || exit 1\n'
        'ucode "/etc/homeproxy/scripts/migrate_config.uc" || exit 1')
defaults = root / "root/etc/uci-defaults/99-homeproxy-modern-defaults"
changes[defaults] = """#!/bin/sh
/usr/libexec/homeproxy-c8-check-legacy || exit 1
if ! uci -q get homeproxy.subscription.user_agent >/dev/null; then
	uci -q set homeproxy.subscription.user_agent='v2ray' || exit 1
fi
if ! uci -q get homeproxy.subscription.allow_insecure >/dev/null; then
	uci -q set homeproxy.subscription.allow_insecure='0' || exit 1
fi
uci -q commit homeproxy || exit 1
exit 0
"""
defaults.parent.mkdir(parents=True, exist_ok=True)
guard_path.parent.mkdir(parents=True, exist_ok=True)
for path, content in changes.items():
    path.write_text(content, encoding="utf-8", newline="\n")
defaults.chmod(0o755)
guard_path.chmod(0o755)
PY

echo "HomeProxy modern client mode patched"
