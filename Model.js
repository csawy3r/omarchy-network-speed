// Shell one-liner run every poll: prints the default-route interface, then
// byte counters for every non-loopback interface. No `${}` is used anywhere
// in here so it's safe to embed as a QML template literal (which would try
// to interpolate `${...}` itself).
function pollScript() {
  return "auto=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i==\"dev\"){print $(i+1); exit}}')\n"
    + "echo \"AUTO $auto\"\n"
    + "for d in /sys/class/net/*; do\n"
    + "  i=$(basename \"$d\")\n"
    + "  [ \"$i\" = lo ] && continue\n"
    + "  rx=$(cat \"$d/statistics/rx_bytes\" 2>/dev/null || echo 0)\n"
    + "  tx=$(cat \"$d/statistics/tx_bytes\" 2>/dev/null || echo 0)\n"
    + "  echo \"IFACE $i $rx $tx\"\n"
    + "done\n"
}

// raw -> { auto: "eth0", ifaces: { eth0: {rx,tx}, ... }, list: [names...] }
function parseSample(raw) {
  var lines = String(raw || "").split("\n")
  var auto = ""
  var ifaces = {}
  var list = []

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split(/\s+/)
    if (parts[0] === "AUTO") {
      auto = parts[1] || ""
    } else if (parts[0] === "IFACE" && parts[1]) {
      var name = parts[1]
      ifaces[name] = { rx: parseFloat(parts[2] || "0"), tx: parseFloat(parts[3] || "0") }
      list.push(name)
    }
  }

  list.sort()
  return { auto: auto, ifaces: ifaces, list: list }
}

// Resolves the configured selection ("auto" | "all" | <iface name>) against
// a parsed sample to a single { rx, tx, label } reading.
function resolveActive(sample, selected) {
  var s = sample || { auto: "", ifaces: {}, list: [] }

  if (selected === "all") {
    var rx = 0, tx = 0
    for (var k in s.ifaces) { rx += s.ifaces[k].rx; tx += s.ifaces[k].tx }
    return { rx: rx, tx: tx, label: "All interfaces" }
  }

  if (!selected || selected === "auto") {
    var name = s.auto
    var entry = name && s.ifaces[name] ? s.ifaces[name] : { rx: 0, tx: 0 }
    return { rx: entry.rx, tx: entry.tx, label: name || "No connection" }
  }

  var found = s.ifaces[selected]
  if (found) return { rx: found.rx, tx: found.tx, label: selected }
  return { rx: 0, tx: 0, label: selected + " (not found)" }
}

// Same delta-over-time algorithm as the built-in network panel's
// throughputState, keyed by an opaque string instead of a bare iface name so
// switching between auto/all/<iface> also resets the rate to 0.
function throughputState(previous, next, now) {
  var prev = previous || {}
  var key = next.key || ""
  var rx = Number(next.rx || 0)
  var tx = Number(next.tx || 0)
  var previousTime = Number(prev.prevTime || 0)

  if (key !== (prev.prevKey || "") || previousTime === 0) {
    return { prevKey: key, prevRx: rx, prevTx: tx, prevTime: now, downloadRate: 0, uploadRate: 0 }
  }

  var dt = now - previousTime
  var downloadRate = Number(prev.downloadRate || 0)
  var uploadRate = Number(prev.uploadRate || 0)
  if (dt > 0) {
    downloadRate = Math.max(0, (rx - Number(prev.prevRx || 0)) / dt)
    uploadRate = Math.max(0, (tx - Number(prev.prevTx || 0)) / dt)
  }

  return { prevKey: key, prevRx: rx, prevTx: tx, prevTime: now, downloadRate: downloadRate, uploadRate: uploadRate }
}

function formatBytes(bytes) {
  var n = Number(bytes)
  if (!isFinite(n) || n < 0) n = 0
  if (n < 1024) return Math.round(n) + " B"
  if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB"
  if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB"
  return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB"
}

function formatRate(bytesPerSec) {
  return formatBytes(bytesPerSec) + "/s"
}
