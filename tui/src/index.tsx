#!/usr/bin/env bun

import { createCliRenderer } from "@opentui/core"
import { createRoot, useKeyboard, useRenderer } from "@opentui/react"
import { useCallback, useEffect, useRef, useState } from "react"

type Container = { id: string; name: string; image: string; state: string; status: string; ports: string; project?: string }
type Port = { pid: number; command: string; user: string; address: string; port: number; type: string; docker: boolean }
type Tab = "containers" | "ports"
type ContainerGroup = { name: string; containers: Container[] }

function groupedContainers(rows: Container[]): ContainerGroup[] {
  const groups = new Map<string, Container[]>()
  for (const container of rows) {
    const name = container.project || "Standalone"
    groups.set(name, [...(groups.get(name) || []), container])
  }
  return [...groups.entries()].map(([name, containers]) => ({ name, containers }))
}

function ContainerList({ rows, selected, collapsed, onToggle }: { rows: Container[]; selected: number; collapsed: Set<string>; onToggle: (name: string) => void }) {
  let offset = 0
  return <>{groupedContainers(rows).map((group) => {
    const start = offset
    offset += group.containers.length
    return <box key={`group-${group.name}`} style={{ flexDirection: "column" }}>
      <box style={{ height: 1, flexDirection: "row", paddingLeft: 1, alignItems: "center" }} onMouseDown={() => onToggle(group.name)}>
        <text content={`${collapsed.has(group.name) ? "▸" : "▾"} ${group.name}  (${group.containers.length})`} fg="#f5c451" />
      </box>
      {!collapsed.has(group.name) && group.containers.map((c, localIndex) => {
        const i = start + localIndex
        return <box key={c.id} style={{ flexDirection: "row", height: 1, paddingLeft: 1, alignItems: "center" }}><text content={`${i === selected ? "❯" : " "} `} fg="#f5c451" /><text content={`● ${clip(c.name, 25)}`} fg={stateColor(c.state)} /><text content={`  ${clip(c.image, 22)}`} fg="#b6c0cf" /><text content={`  ${clip(c.ports, 30)}`} fg="#7e8b9d" /></box>
      })}
    </box>
  })}</>
}

async function run(command: string, args: string[]) {
  try {
    const p = Bun.spawn([command, ...args], { stdout: "pipe", stderr: "pipe" })
    const [stdout, stderr] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text()])
    const code = await p.exited
    return { stdout, stderr, ok: code === 0 }
  } catch (error) {
    return { stdout: "", stderr: error instanceof Error ? error.message : String(error), ok: false }
  }
}

async function containers(): Promise<Container[]> {
  const r = await run("docker", ["ps", "-a", "--format", "{{json .}}"])
  if (!r.ok) throw new Error(r.stderr.trim() || "Docker daemon is unavailable")
  return r.stdout.split("\n").filter(Boolean).flatMap((line) => {
    try {
      const x = JSON.parse(line)
      const labels = Object.fromEntries((x.Labels || "").split(",").filter(Boolean).map((v: string) => v.split("=")))
      return [{ id: x.ID, name: x.Names, image: x.Image, state: x.State, status: x.Status, ports: x.Ports || "—", project: labels["com.docker.compose.project"] }]
    } catch { return [] }
  })
}

async function ports(): Promise<Port[]> {
  const r = await run("lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcLuPn"])
  if (!r.stdout && r.stderr) throw new Error(r.stderr.trim())
  const result: Port[] = []
  let pid = 0, command = "", user = "", type = "TCP"
  for (const line of r.stdout.split("\n")) {
    const tag = line[0], value = line.slice(1)
    if (tag === "p") pid = Number(value)
    else if (tag === "c") command = value
    else if (tag === "L") user = value
    else if (tag === "P") type = value
    else if (tag === "t") type = "TCP" + (value.includes("6") ? "6" : "4")
    else if (tag === "n") {
      const match = value.match(/:(\d+)$/)
      if (match) result.push({ pid, command, user, address: value.slice(0, -match[0].length) || "*", port: Number(match[1]), type, docker: /docker|vpnkit|com\.docker/i.test(command) })
    }
  }
  return result.sort((a, b) => a.port - b.port || a.pid - b.pid)
}

async function action(tab: Tab, item: Container | Port, key: string) {
  if (tab === "containers") {
    const c = item as Container
    const command = key === "s" ? (c.state === "running" ? "stop" : "start") : key === "R" ? "restart" : key === "k" ? "kill" : "rm"
    const args = command === "rm" ? ["rm", "-f", c.id] : [command, c.id]
    return run("docker", args)
  }
  return run("kill", [key === "K" ? "-KILL" : "-TERM", String((item as Port).pid)])
}

const stateColor = (state: string) => state === "running" ? "#48d597" : state === "paused" ? "#f5b942" : "#8993a4"
const clip = (value: string, n: number) => value.length > n ? value.slice(0, n - 1) + "…" : value

function App() {
  const renderer = useRenderer()
  const [tab, setTab] = useState<Tab>("containers")
  const [containerRows, setContainerRows] = useState<Container[]>([])
  const [portRows, setPortRows] = useState<Port[]>([])
  const [selected, setSelected] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [message, setMessage] = useState("Ready")
  const [confirm, setConfirm] = useState("")
  const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(new Set())
  const refreshVersion = useRef(0)

  const refresh = useCallback(async () => {
    const version = ++refreshVersion.current
    const requestedTab = tab
    setLoading(true); setError("")
    try {
      if (requestedTab === "containers") {
        const next = await containers()
        if (version !== refreshVersion.current) return
        setContainerRows(next)
        setSelected((value) => Math.min(value, Math.max(0, next.length - 1)))
      } else {
        const next = await ports()
        if (version !== refreshVersion.current) return
        setPortRows(next)
        setSelected((value) => Math.min(value, Math.max(0, next.length - 1)))
      }
      setMessage(`Updated ${new Date().toLocaleTimeString()}`)
    } catch (e) { setError(e instanceof Error ? e.message : String(e)) }
    finally {
      if (version === refreshVersion.current) setLoading(false)
    }
  }, [tab])
  useEffect(() => { refresh() }, [refresh])
  useEffect(() => { const timer = setInterval(refresh, 5000); return () => clearInterval(timer) }, [refresh])
  useEffect(() => { setSelected(0) }, [tab])

  const rows = tab === "containers" ? containerRows : portRows
  const selectedItem = rows[selected]
  const doAction = async (key: string) => {
    if (!selectedItem) return
    const destructive = tab === "containers" ? key === "d" || key === "k" : true
    if (destructive && !confirm) { setConfirm(key); setMessage("Press y to confirm, any other key to cancel"); return }
    setConfirm(""); setMessage("Working…")
    const r = await action(tab, selectedItem, key)
    if (!r.ok) setMessage(r.stderr.trim() || "Action failed")
    else { setMessage("Action complete"); await refresh() }
  }
  const quit = useCallback(() => {
    // Always let OpenTUI restore raw mode, mouse mode, and the alternate
    // screen before the Node process exits. Calling process.exit directly
    // leaves the terminal in application mode and causes garbled input.
    renderer.destroy()
    setTimeout(() => process.exit(0), 50)
  }, [renderer])

  useKeyboard((key) => {
    if (confirm) { if (key.name === "y") doAction(confirm); else setConfirm(""); return }
    if (key.name === "q" || key.name === "escape") { quit(); return }
    if (key.name === "tab") {
      setTab((current) => current === "containers" ? "ports" : "containers")
      return
    }
    if (key.name === "left") { setTab("containers"); return }
    if (key.name === "right") { setTab("ports"); return }
    // `r` is restart in the Containers tab and refresh in the Ports tab.
    // Keep this before the navigation/refresh handlers so restart is not
    // accidentally swallowed by the global refresh shortcut.
    if (tab === "containers") {
      if (key.name === "s") { doAction("s"); return } // start or stop
      if (key.name === "r") { doAction("R"); return } // restart
      if (key.name === "d") { doAction("d"); return } // remove
    }
    if (key.name === "r") { refresh(); return }
    if (key.name === "up" || key.name === "k") { setSelected((v) => Math.max(0, v - 1)); return }
    if (key.name === "down" || key.name === "j") { setSelected((v) => Math.min(Math.max(0, rows.length - 1), v + 1)); return }
    if (tab === "containers" && (key.name === "f" || key.name === "space")) {
      const container = containerRows[selected]
      if (container) {
        const name = container.project || "Standalone"
        setCollapsedGroups((current) => { const next = new Set(current); next.has(name) ? next.delete(name) : next.add(name); return next })
      }
      return
    }
    if (tab === "ports" && key.name === "x") {
      doAction(key.shift ? "K" : "k") // x = SIGTERM, Shift+x = SIGKILL
      return
    }
  })

  return <box style={{ flexDirection: "column", flexGrow: 1, padding: 1 }}>
    <box style={{ flexDirection: "row", height: 3, alignItems: "center" }}>
      <text content="  PORTAIN  " fg="#f5c451" />
      <text content={tab === "containers" ? "[ CONTAINERS ]" : "  CONTAINERS  "} fg={tab === "containers" ? "#ffffff" : "#6f7b8d"} />
      <text content="   " />
      <text content={tab === "ports" ? "[ PORTS ]" : "  PORTS  "} fg={tab === "ports" ? "#ffffff" : "#6f7b8d"} />
      <text content={loading ? "     syncing…" : ""} fg="#6f7b8d" />
    </box>
    <box style={{ flexDirection: "row", flexGrow: 1, gap: 1 }}>
      <scrollbox key={tab} title={tab === "containers" ? `Containers · ${containerRows.length}` : `Listening ports · ${portRows.length}`} border scrollY scrollX={false} style={{ flexGrow: 1, height: "100%", borderColor: "#303b4b" }} wrapperOptions={{ height: "100%" }} viewportOptions={{ height: "100%" }} contentOptions={{ flexDirection: "column", flexGrow: 0, flexShrink: 0 }}>
        {error ? <text content={`  ⚠ ${error}`} fg="#ff7373" /> : rows.length === 0 && !loading ? <text content="  Nothing running" fg="#8993a4" /> : tab === "containers" ? <ContainerList rows={containerRows} selected={selected} collapsed={collapsedGroups} onToggle={(name) => setCollapsedGroups((current) => { const next = new Set(current); next.has(name) ? next.delete(name) : next.add(name); return next })} /> : portRows.map((p, i) => <box key={`${p.pid}-${p.port}-${p.address}`} style={{ flexDirection: "row", height: 1, paddingLeft: 1, alignItems: "center" }}><text content={`${i === selected ? "❯" : " "} ${String(p.port).padEnd(7)} ${clip(p.command, 20).padEnd(21)} ${String(p.pid).padEnd(8)} ${clip(p.address, 18).padEnd(19)} ${p.docker ? "DOCKER" : p.user}`} fg={i === selected ? "#ffffff" : p.docker ? "#67a8ff" : "#c3ccd8"} /></box>)}
      </scrollbox>
      <box title="Details" border style={{ width: 34, borderColor: "#303b4b", padding: 1, flexDirection: "column" }}>
        {selectedItem ? tab === "containers" ? <><text content={(selectedItem as Container).name} fg="#f5c451" /><text content={`\n${(selectedItem as Container).status}`} fg={stateColor((selectedItem as Container).state)} /><text content={`\nimage  ${(selectedItem as Container).image}\nid      ${(selectedItem as Container).id.slice(0, 12)}\nports   ${(selectedItem as Container).ports}`} fg="#aab5c5" /></> : <><text content={`:${(selectedItem as Port).port}`} fg="#f5c451" /><text content={`\n${(selectedItem as Port).command}`} fg="#ffffff" /><text content={`\npid     ${(selectedItem as Port).pid}\nuser    ${(selectedItem as Port).user}\naddr    ${(selectedItem as Port).address}\ntype    ${(selectedItem as Port).type}`} fg="#aab5c5" /></> : <text content="Select an item" fg="#8993a4" />}
      </box>
    </box>
    <box style={{ height: 2, flexDirection: "row", alignItems: "center" }}><text content={confirm ? "  CONFIRM?  y / any key cancel" : `  ${message}`} fg={confirm ? "#ffb86b" : "#8993a4"} /><text content={tab === "containers" ? "  s start/stop · r restart · d remove · f fold" : "  x terminate · Shift+x force kill"} fg="#596579" /></box>
  </box>
}

const renderer = await createCliRenderer({ exitOnCtrlC: true })
createRoot(renderer).render(<App />)
