#!/usr/bin/env python3
"""Gate for n8n workflow JSON. Fails (exit 1) on anything that must not be imported.

BLOCK: shell/SSH/local-file nodes, hard-coded secrets, active=true,
       embedded credential IDs, unparseable files.
WARN:  Code nodes, public webhooks/forms/chat triggers, nodes that send messages.
Usage: python3 tools/n8n_audit.py workflows/
"""
import json, os, re, sys

BLOCK_TYPES = {
    "n8n-nodes-base.executeCommand": "shell command",
    "n8n-nodes-base.ssh": "SSH",
    "n8n-nodes-base.readWriteFile": "local files",
    "n8n-nodes-base.readBinaryFiles": "local files",
    "n8n-nodes-base.writeBinaryFile": "local files",
    "n8n-nodes-base.localFileTrigger": "local files",
}
WARN_TYPES = ("code", "function", "functionItem", "webhook", "formTrigger", "chatTrigger")
SENDERS = re.compile(r"(gmail|emailSend|microsoftOutlook|sendGrid|mailgun|twilio|whatsApp|telegram|slack)", re.I)
SECRET = re.compile(r"(sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[bp]-[0-9A-Za-z-]{10,}|ghp_[A-Za-z0-9]{30,}|AIza[0-9A-Za-z_-]{30,}|Bearer [A-Za-z0-9._-]{20,})")


def audit(path):
    block, warn = [], []
    raw = open(path, encoding="utf-8").read()
    try:
        wf = json.loads(raw)
        nodes = wf["nodes"]
    except Exception as exc:  # noqa: BLE001
        return [f"unparseable: {exc}"], []
    if wf.get("active"):
        block.append("active=true (must import switched off)")
    if SECRET.search(raw):
        block.append("hard-coded secret pattern")
    for n in nodes:
        t, name = n.get("type", ""), n.get("name", "?")
        if t in BLOCK_TYPES:
            block.append(f"{BLOCK_TYPES[t]} node '{name}'")
        for c in (n.get("credentials") or {}).values():
            if isinstance(c, dict) and c.get("id"):
                block.append(f"embedded credential id in '{name}'")
        short = t.split(".")[-1]
        if short in WARN_TYPES:
            warn.append(f"{short} '{name}'")
        if SENDERS.search(t) and "Trigger" not in t:
            warn.append(f"sends via {short} '{name}'")
    return block, warn


def main(root):
    failed = 0
    files = sorted(os.path.join(d, f) for d, _, fs in os.walk(root) for f in fs if f.endswith(".json"))
    for p in files:
        block, warn = audit(p)
        status = "BLOCK" if block else "ok"
        print(f"[{status}] {p}")
        for b in block:
            print(f"    x {b}")
        for w in warn:
            print(f"    ! {w}")
        failed += bool(block)
    print(f"\n{len(files)} workflows, {failed} blocked")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "workflows"))
