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

// Parses the small, stable subset of theme/colors.toml keys every Omarchy
// theme defines (accent, muted, foreground, red, yellow, orange, green,
// cyan, blue, magenta) into a flat dict. Same regex shape as the shell's
// own Color.qml loader, so it stays correct if a theme quotes values or
// adds trailing comments.
function parseThemeColors(raw) {
  var keys = ["accent", "muted", "foreground", "red", "yellow", "orange", "green", "cyan", "blue", "magenta"]
  var out = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (!match) continue
    if (keys.indexOf(match[1]) !== -1) out[match[1]] = match[2]
  }
  return out
}

// Builds the speed-tier swatch palette from the live theme, falling back to
// the old fixed One Dark values for any key an unusual theme omits.
function themePalette(theme) {
  var t = theme || {}
  return [
    "",
    t.red || "#e06c75",
    t.yellow || "#e5c07b",
    t.green || "#98c379",
    t.cyan || "#56b6c2",
    t.blue || t.accent || "#61afef",
    t.magenta || "#c678dd",
    t.muted || "#abb2bf",
    t.foreground || "#ffffff"
  ]
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

// Parses `ss -H -tanpi` output into per-process rx/tx byte totals, then
// diffs against the previous sample to get a rate. Unprivileged: `ss -p`
// only resolves process info for sockets the current user owns, so this
// only ever shows the current user's own apps.
function parseNetworkProcesses(raw, previous, now) {
  var lines = String(raw || "").split("\n")
  var pending = null
  var txTotals = {}
  var rxTotals = {}
  var names = {}

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var userMatch = line.match(/users:\(\("([^"]+)",pid=(\d+)/)
    if (userMatch) {
      pending = { pid: userMatch[2], name: userMatch[1] }
      names[pending.pid] = pending.name
    }
    if (line.indexOf("bytes_") < 0) continue
    var ackedMatch = line.match(/bytes_acked:(\d+)/)
    var sentMatch = line.match(/bytes_sent:(\d+)/)
    var receivedMatch = line.match(/bytes_received:(\d+)/)
    if (!ackedMatch && !sentMatch && !receivedMatch) continue
    var pid = pending ? pending.pid : null
    if (!pid) continue
    var txBytes = ackedMatch ? Number(ackedMatch[1]) : (sentMatch ? Number(sentMatch[1]) : 0)
    var rxBytes = receivedMatch ? Number(receivedMatch[1]) : 0
    txTotals[pid] = (txTotals[pid] || 0) + txBytes
    rxTotals[pid] = (rxTotals[pid] || 0) + rxBytes
    pending = null
  }

  var prev = previous || {}
  var list = []
  var nextPrev = {}

  for (var pidKey in names) {
    var tx = txTotals[pidKey] || 0
    var rx = rxTotals[pidKey] || 0
    var prevEntry = prev[pidKey]
    var rxRate = 0
    var txRate = 0
    if (prevEntry) {
      var seconds = Math.max(0.5, (now - prevEntry.at) / 1000)
      rxRate = Math.max(0, (rx - prevEntry.rx) / seconds)
      txRate = Math.max(0, (tx - prevEntry.tx) / seconds)
    }
    nextPrev[pidKey] = { rx: rx, tx: tx, at: now }
    if (!prevEntry && rx + tx <= 0) continue
    list.push({ pid: pidKey, name: names[pidKey], rxRate: rxRate, txRate: txRate })
  }

  list.sort(function(a, b) { return (b.rxRate + b.txRate) - (a.rxRate + a.txRate) })

  return { list: list, previous: nextPrev }
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
