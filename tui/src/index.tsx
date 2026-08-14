#!/usr/bin/env bun

import { createCliRenderer, type ScrollBoxRenderable } from "@opentui/core";
import { createRoot, useKeyboard, useRenderer } from "@opentui/react";
import { useCallback, useEffect, useRef, useState } from "react";
// Read the version from the manifest rather than restating it here, so a
// `npm version` bump cannot leave the status bar reporting a stale number. npm
// always ships package.json in the tarball regardless of the `files` field, so
// this resolves for a published install as well as from a source checkout.
import pkg from "../package.json";

// Every colour the UI draws with. Names describe the role, not the hue, so a
// role can be retuned without hunting through JSX — several roles deliberately
// share a value today (the muted grey, the amber accent).
const theme = {
	// Frame: header, tab strip, panel borders
	logo: "#ff4bc9",
	tabActive: "#ffffff",
	tabIdle: "#6f7b8d",
	syncing: "#6f7b8d",
	border: "#303b4b",

	// Container state dot, also the status line in the details pane
	stateRunning: "#48d597",
	statePaused: "#f5b942",
	stateStopped: "#8993a4",

	// Container list: cursor, RUNNING/STOPPED headers, project headers, columns
	cursor: "#d7d7d7",
	sectionRunning: "#48d597",
	sectionStopped: "#8993a4",
	sectionCount: "#5d6878",
	groupRunning: "#c6c6c6",
	groupStopped: "#8993a4",
	containerName: "#ffffff",
	containerNameIdle: "#8993a4",
	containerImage: "#b6c0cf",
	containerPorts: "#7e8b9d",

	// Port list
	portSelected: "#ffffff",
	portDocker: "#67a8ff",
	portRow: "#c3ccd8",

	// Details pane
	detailTitle: "#ff4bc9",
	detailValue: "#ffffff",
	detailBody: "#aab5c5",

	// Status bar and messages
	message: "#8993a4",
	confirm: "#ff4bc9",
	hint: "#596579",
	error: "#ff7373",
	empty: "#8993a4",
	version: "#596579",
} as const;

type Container = {
	id: string;
	name: string;
	image: string;
	state: string;
	status: string;
	ports: string;
	project?: string;
};
type Port = {
	pid: number;
	command: string;
	user: string;
	address: string;
	port: number;
	type: string;
	docker: boolean;
};
type Tab = "containers" | "ports";
type ContainerGroup = { name: string; containers: Container[] };
type ContainerSection = {
	key: "running" | "stopped";
	label: string;
	groups: ContainerGroup[];
	count: number;
};

// Paused and restarting containers are still up, so they belong with the running
// ones rather than buried in the stopped pile.
const isUp = (container: Container) =>
	container.state === "running" ||
	container.state === "paused" ||
	container.state === "restarting";

function groupedContainers(rows: Container[]): ContainerGroup[] {
	const groups = new Map<string, Container[]>();
	for (const container of rows) {
		const name = container.project || "Standalone";
		groups.set(name, [...(groups.get(name) || []), container]);
	}
	return [...groups.entries()].map(([name, containers]) => ({
		name,
		containers,
	}));
}

// Running first, then stopped, each still grouped by compose project. A project
// with some services up and some down appears in both sections, which is what
// makes a half-started stack obvious at a glance. Empty sections are dropped.
function sectionedContainers(rows: Container[]): ContainerSection[] {
	const up = rows.filter(isUp);
	const down = rows.filter((container) => !isUp(container));
	return [
		{ key: "running" as const, label: "RUNNING", rows: up },
		{ key: "stopped" as const, label: "STOPPED", rows: down },
	]
		.filter((section) => section.rows.length > 0)
		.map((section) => ({
			key: section.key,
			label: section.label,
			count: section.rows.length,
			groups: groupedContainers(section.rows),
		}));
}

// Fold keys are namespaced by section because the same project can appear under
// both, and folding its running services must not fold its stopped ones.
const groupKey = (section: ContainerSection["key"], name: string) =>
	`${section}/${name}`;
const sectionKey = (section: ContainerSection["key"]) => `@${section}`;

type ContainerLine =
	| {
			kind: "section";
			key: string;
			label: string;
			count: number;
			folded: boolean;
			running: boolean;
	  }
	| {
			kind: "group";
			key: string;
			name: string;
			count: number;
			folded: boolean;
			running: boolean;
	  }
	| { kind: "container"; key: string; container: Container; index: number };
type ContainerSlot = {
	line: number;
	visible: boolean;
	group: string;
	section: string;
};

// Builds the flat list of rows to draw alongside the selection model, so the
// cursor index and the drawn rows can never drift apart. Every row is one cell
// tall, so a slot's `line` is both its array position and its content line —
// which is all scroll-into-view needs. A row hidden by a fold points at the
// header that hides it.
function containerLayout(
	rows: Container[],
	collapsed: Set<string>,
): { lines: ContainerLine[]; items: Container[]; slots: ContainerSlot[] } {
	const lines: ContainerLine[] = [];
	const items: Container[] = [];
	const slots: ContainerSlot[] = [];
	for (const section of sectionedContainers(rows)) {
		const sectionFoldKey = sectionKey(section.key);
		const sectionFolded = collapsed.has(sectionFoldKey);
		const sectionLine = lines.length;
		lines.push({
			kind: "section",
			key: sectionFoldKey,
			label: section.label,
			count: section.count,
			folded: sectionFolded,
			running: section.key === "running",
		});
		for (const group of section.groups) {
			const groupFoldKey = groupKey(section.key, group.name);
			const groupFolded = collapsed.has(groupFoldKey);
			const groupLine = lines.length;
			if (!sectionFolded)
				lines.push({
					kind: "group",
					key: groupFoldKey,
					name: group.name,
					count: group.containers.length,
					folded: groupFolded,
					running: section.key === "running",
				});
			for (const container of group.containers) {
				const visible = !sectionFolded && !groupFolded;
				items.push(container);
				slots.push({
					line: visible
						? lines.length
						: sectionFolded
							? sectionLine
							: groupLine,
					visible,
					group: groupFoldKey,
					section: sectionFoldKey,
				});
				if (visible)
					lines.push({
						kind: "container",
						key: container.id,
						container,
						index: items.length - 1,
					});
			}
		}
	}
	return { lines, items, slots };
}

function ContainerList({
	lines,
	selected,
	onToggle,
}: {
	lines: ContainerLine[];
	selected: number;
	onToggle: (key: string) => void;
}) {
	return (
		<>
			{lines.map((line) =>
				line.kind === "container" ? (
					<box
						key={line.key}
						style={{
							flexDirection: "row",
							height: 1,
							paddingLeft: 3,
							alignItems: "center",
						}}
					>
						<text
							content={`${line.index === selected ? "❯" : " "} `}
							fg={theme.cursor}
						/>
						<text content="● " fg={stateColor(line.container.state)} />
						<text
							content={clip(line.container.name, 25)}
							fg={nameColor(line.container.state)}
						/>
						<text
							content={`  ${clip(line.container.image, 22)}`}
							fg={theme.containerImage}
						/>
						<text
							content={`  ${clip(line.container.ports, 30)}`}
							fg={theme.containerPorts}
						/>
					</box>
				) : line.kind === "section" ? (
					<box
						key={line.key}
						style={{
							height: 1,
							flexDirection: "row",
							paddingLeft: 1,
							alignItems: "center",
						}}
						onMouseDown={() => onToggle(line.key)}
					>
						<text
							content={`${line.folded ? "▸" : "▾"} ${line.label}`}
							fg={line.running ? theme.sectionRunning : theme.sectionStopped}
						/>
						<text content={`  ${line.count}`} fg={theme.sectionCount} />
					</box>
				) : (
					<box
						key={line.key}
						style={{
							height: 1,
							flexDirection: "row",
							paddingLeft: 2,
							alignItems: "center",
						}}
						onMouseDown={() => onToggle(line.key)}
					>
						<text
							content={`${line.folded ? "▸" : "▾"} ${line.name}  (${line.count})`}
							fg={line.running ? theme.groupRunning : theme.groupStopped}
						/>
					</box>
				),
			)}
		</>
	);
}

async function run(command: string, args: string[]) {
	try {
		const p = Bun.spawn([command, ...args], { stdout: "pipe", stderr: "pipe" });
		const [stdout, stderr] = await Promise.all([
			new Response(p.stdout).text(),
			new Response(p.stderr).text(),
		]);
		const code = await p.exited;
		return { stdout, stderr, ok: code === 0 };
	} catch (error) {
		return {
			stdout: "",
			stderr: error instanceof Error ? error.message : String(error),
			ok: false,
		};
	}
}

async function containers(): Promise<Container[]> {
	const r = await run("docker", ["ps", "-a", "--format", "{{json .}}"]);
	if (!r.ok) throw new Error(r.stderr.trim() || "Docker daemon is unavailable");
	return r.stdout
		.split("\n")
		.filter(Boolean)
		.flatMap((line) => {
			try {
				const x = JSON.parse(line);
				const labels = Object.fromEntries(
					(x.Labels || "")
						.split(",")
						.filter(Boolean)
						.map((v: string) => v.split("=")),
				);
				return [
					{
						id: x.ID,
						name: x.Names,
						image: x.Image,
						state: x.State,
						status: x.Status,
						ports: x.Ports || "—",
						project: labels["com.docker.compose.project"],
					},
				];
			} catch {
				return [];
			}
		});
}

// A listener's identity: the same triple is used to dedupe lsof's output, to key
// the drawn rows, and to keep the cursor on one process across a refresh.
const portKey = (p: Pick<Port, "pid" | "address" | "port">) =>
	`${p.pid}:${p.address}:${p.port}`;
const familyDigit = (family: string) => (family === "IPv6" ? "6" : "4");

// `t` (IPv4/IPv6) has to be in the field list. Without it lsof reports every row
// as a bare "TCP" and a dual-stack bind becomes two indistinguishable rows —
// which is what made the list look like it was repeating itself.
async function ports(): Promise<Port[]> {
	const r = await run("lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcLuPnt"]);
	if (!r.stdout && r.stderr) throw new Error(r.stderr.trim());
	const rows = new Map<string, Port>();
	let pid = 0,
		command = "",
		user = "",
		protocol = "TCP",
		family = "";
	for (const line of r.stdout.split("\n")) {
		const tag = line[0],
			value = line.slice(1);
		if (tag === "p") pid = Number(value);
		else if (tag === "c") command = value;
		else if (tag === "L") user = value;
		// `t` and `P` are separate fields that both precede the `n` they describe,
		// so they are tracked apart and joined only when a row is emitted. Folding
		// them into one variable lets whichever arrives last win, and `P` arrives
		// last — that is how the family was being lost.
		else if (tag === "t") family = value;
		else if (tag === "P") protocol = value;
		else if (tag === "n") {
			const match = value.match(/:(\d+)$/);
			if (!match) continue;
			const port = Number(match[1]);
			const address = value.slice(0, -match[0].length) || "*";
			// lsof reports one record per descriptor, not per listener: a dual-stack
			// wildcard bind arrives twice under an identical name, and forked or
			// SO_REUSEPORT servers dup one socket across many FDs. Collapse those
			// onto a single row that names every family it covers ("TCP4/6").
			// Distinct bind addresses (127.0.0.1 vs [::1]) still get their own rows —
			// those really are two different listeners.
			const key = portKey({ pid, address, port });
			const existing = rows.get(key);
			const digit = family ? familyDigit(family) : "";
			if (existing) {
				if (digit && !existing.type.includes(digit))
					existing.type += `/${digit}`;
			} else
				rows.set(key, {
					pid,
					command,
					user,
					address,
					port,
					type: protocol + digit,
					docker: /docker|vpnkit|com\.docker/i.test(command),
				});
			family = "";
		}
	}
	return [...rows.values()].sort((a, b) => a.port - b.port || a.pid - b.pid);
}

async function action(tab: Tab, item: Container | Port, key: string) {
	if (tab === "containers") {
		const c = item as Container;
		const command =
			key === "s"
				? c.state === "running"
					? "stop"
					: "start"
				: key === "R"
					? "restart"
					: key === "k"
						? "kill"
						: "rm";
		const args = command === "rm" ? ["rm", "-f", c.id] : [command, c.id];
		return run("docker", args);
	}
	return run("kill", [
		key === "K" ? "-KILL" : "-TERM",
		String((item as Port).pid),
	]);
}

const stateColor = (state: string) =>
	state === "running"
		? theme.stateRunning
		: state === "paused"
			? theme.statePaused
			: theme.stateStopped;
// The dot carries the full state; the name only separates actually-running from
// everything else (paused included), so anything not serving traffic reads dim.
const nameColor = (state: string) =>
	state === "running" ? theme.containerName : theme.containerNameIdle;
const clip = (value: string, n: number) =>
	value.length > n ? value.slice(0, n - 1) + "…" : value;

function App() {
	const renderer = useRenderer();
	const [tab, setTab] = useState<Tab>("containers");
	const [containerRows, setContainerRows] = useState<Container[]>([]);
	const [portRows, setPortRows] = useState<Port[]>([]);
	// A cursor per tab. Sharing one index meant switching tabs dragged the other
	// list's position along with it, and clamping one list's length truncated the
	// other's cursor.
	const [containerIndex, setContainerIndex] = useState(0);
	const [portIndex, setPortIndex] = useState(0);
	const [loading, setLoading] = useState(true);
	const [error, setError] = useState("");
	const [message, setMessage] = useState("Ready");
	const [confirm, setConfirm] = useState("");
	const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(
		new Set(),
	);
	const refreshVersion = useRef(0);
	const scrollBox = useRef<ScrollBoxRenderable | null>(null);
	const anchorId = useRef("");
	const portAnchor = useRef("");

	const refresh = useCallback(async () => {
		const version = ++refreshVersion.current;
		const requestedTab = tab;
		setLoading(true);
		setError("");
		try {
			if (requestedTab === "containers") {
				const next = await containers();
				if (version !== refreshVersion.current) return;
				setContainerRows(next);
				setContainerIndex((value) =>
					Math.min(value, Math.max(0, next.length - 1)),
				);
			} else {
				const next = await ports();
				if (version !== refreshVersion.current) return;
				setPortRows(next);
				setPortIndex((value) => Math.min(value, Math.max(0, next.length - 1)));
			}
			setMessage(`Updated ${new Date().toLocaleTimeString()}`);
		} catch (e) {
			setError(e instanceof Error ? e.message : String(e));
		} finally {
			if (version === refreshVersion.current) setLoading(false);
		}
	}, [tab]);
	useEffect(() => {
		refresh();
	}, [refresh]);
	useEffect(() => {
		const timer = setInterval(refresh, 5000);
		return () => clearInterval(timer);
	}, [refresh]);
	const layout = containerLayout(containerRows, collapsedGroups);
	const rows = tab === "containers" ? layout.items : portRows;
	const selected = tab === "containers" ? containerIndex : portIndex;
	const setSelected = tab === "containers" ? setContainerIndex : setPortIndex;
	const selectedItem = rows[selected];

	// Keep the viewport following the cursor. Row heights are all 1, so the
	// content line of a row is enough to know whether it sits above or below the
	// visible window — no child measurement needed. Depending on the line rather
	// than on every render means a manual mouse scroll survives the 5s refresh.
	const selectedLine =
		tab === "containers" ? layout.slots[selected]?.line : selected;
	useEffect(() => {
		const box = scrollBox.current;
		if (!box || selectedLine === undefined) return;
		const height = box.viewport.height;
		if (height <= 0) return;
		if (selectedLine < box.scrollTop) box.scrollTo(selectedLine);
		else if (selectedLine >= box.scrollTop + height)
			box.scrollTo(selectedLine - height + 1);
	}, [selectedLine, tab]);

	const move = (delta: 1 | -1) =>
		setSelected((current) => {
			const limit = rows.length - 1;
			if (limit < 0) return 0;
			let next = current;
			// Skip over rows hidden inside a folded group or section so the cursor only
			// ever lands on a row that is actually drawn.
			for (let step = 0; step <= limit; step++) {
				const candidate = next + delta;
				// Ran out of list without finding a drawn row (everything past the cursor
				// is folded away) — stay where we are rather than landing on a hidden row.
				if (candidate < 0 || candidate > limit) return current;
				next = candidate;
				// Each tab anchors to its own list. Writing the container anchor while
				// moving through ports used to blank it, losing the container the
				// cursor was following.
				if (tab === "containers") {
					if (!layout.slots[next]?.visible) continue;
					anchorId.current = layout.items[next]?.id ?? "";
				} else {
					const row = portRows[next];
					portAnchor.current = row ? portKey(row) : "";
				}
				return next;
			}
			return current;
		});

	// Starting or stopping a container moves its row between the RUNNING and
	// STOPPED sections, which would leave a plain index pointing at an unrelated
	// container. Follow the container the cursor was on instead, and re-anchor
	// only when it is gone (removed, or nothing anchored yet).
	useEffect(() => {
		if (tab !== "containers") return;
		const here = layout.items[containerIndex];
		if (here && here.id === anchorId.current) return;
		const restored = anchorId.current
			? layout.items.findIndex((container) => container.id === anchorId.current)
			: -1;
		if (restored >= 0) setContainerIndex(restored);
		else if (here) anchorId.current = here.id;
	});

	// Ports are sorted by number, so a new low-numbered listener shifts every row
	// below it and a bare index would leave the cursor on a different process.
	// With a 5s auto-refresh and `x` bound to kill, that is a live footgun: follow
	// the port the cursor was on and re-anchor only once it is gone.
	useEffect(() => {
		if (tab !== "ports") return;
		const here = portRows[portIndex];
		if (here && portKey(here) === portAnchor.current) return;
		const restored = portAnchor.current
			? portRows.findIndex((p) => portKey(p) === portAnchor.current)
			: -1;
		if (restored >= 0) setPortIndex(restored);
		else if (here) portAnchor.current = portKey(here);
	});

	const toggleFold = (key: string) =>
		setCollapsedGroups((current) => {
			const next = new Set(current);
			next.has(key) ? next.delete(key) : next.add(key);
			return next;
		});
	const doAction = async (key: string) => {
		if (!selectedItem) return;
		const destructive =
			tab === "containers" ? key === "d" || key === "k" : true;
		if (destructive && !confirm) {
			setConfirm(key);
			setMessage("Press y or Enter to confirm, any other key to cancel");
			return;
		}
		setConfirm("");
		setMessage("Working…");
		const r = await action(tab, selectedItem, key);
		if (!r.ok) setMessage(r.stderr.trim() || "Action failed");
		else {
			setMessage("Action complete");
			await refresh();
		}
	};
	const quit = useCallback(() => {
		// Always let OpenTUI restore raw mode, mouse mode, and the alternate
		// screen before the Node process exits. Calling process.exit directly
		// leaves the terminal in application mode and causes garbled input.
		renderer.destroy();
		setTimeout(() => process.exit(0), 50);
	}, [renderer]);

	useKeyboard((key) => {
		if (confirm) {
			// Enter arrives as "return"; anything else still cancels.
			if (key.name === "y" || key.name === "return") doAction(confirm);
			else setConfirm("");
			return;
		}
		if (key.name === "q" || key.name === "escape") {
			quit();
			return;
		}
		if (key.name === "tab") {
			setTab((current) => (current === "containers" ? "ports" : "containers"));
			return;
		}
		// 1 and 2 jump straight to a tab, alongside the positional left/right.
		// Neither digit collides with an action key, and both are safe to test here:
		// the only handler above this point is the confirm guard, where any key that
		// is not y/Enter cancels anyway.
		if (key.name === "1" || key.name === "left") {
			setTab("containers");
			return;
		}
		if (key.name === "2" || key.name === "right") {
			setTab("ports");
			return;
		}
		// `r` is restart in the Containers tab and refresh in the Ports tab.
		// Keep this before the navigation/refresh handlers so restart is not
		// accidentally swallowed by the global refresh shortcut.
		if (tab === "containers") {
			if (key.name === "s") {
				doAction("s");
				return;
			} // start or stop
			if (key.name === "r") {
				doAction("R");
				return;
			} // restart
			if (key.name === "d") {
				doAction("d");
				return;
			} // remove
		}
		if (key.name === "r") {
			refresh();
			return;
		}
		if (key.name === "up" || key.name === "k") {
			move(-1);
			return;
		}
		if (key.name === "down" || key.name === "j") {
			move(1);
			return;
		}
		if (
			tab === "containers" &&
			(key.name === "f" || key.name === "F" || key.name === "space")
		) {
			// f folds the project group under the cursor, Shift+f the whole section.
			const slot = layout.slots[selected];
			if (slot)
				toggleFold(key.shift || key.name === "F" ? slot.section : slot.group);
			return;
		}
		if (tab === "ports" && key.name === "x") {
			doAction(key.shift ? "K" : "k"); // x = SIGTERM, Shift+x = SIGKILL
			return;
		}
	});

	return (
		<box style={{ flexDirection: "column", flexGrow: 1, padding: 1 }}>
			<box style={{ flexDirection: "row", height: 3, alignItems: "center" }}>
				<text content="  PORTAIN  " fg={theme.logo} />
				<text
					content={tab === "containers" ? "[1 CONTAINERS]" : " 1 CONTAINERS "}
					fg={tab === "containers" ? theme.tabActive : theme.tabIdle}
				/>
				<text content=" " />
				<text
					content={tab === "ports" ? "[2 PORTS]" : " 2 PORTS "}
					fg={tab === "ports" ? theme.tabActive : theme.tabIdle}
				/>
				<text content={loading ? "     syncing…" : ""} fg={theme.syncing} />
			</box>
			<box style={{ flexDirection: "row", flexGrow: 1, gap: 1 }}>
				<scrollbox
					key={tab}
					ref={scrollBox}
					title={
						tab === "containers"
							? `Containers · ${containerRows.filter(isUp).length} up / ${containerRows.length}`
							: `Listening ports · ${portRows.length}`
					}
					border
					scrollY
					scrollX={false}
					style={{ flexGrow: 1, height: "100%", borderColor: theme.border }}
					wrapperOptions={{ height: "100%" }}
					viewportOptions={{ height: "100%" }}
					contentOptions={{
						flexDirection: "column",
						flexGrow: 0,
						flexShrink: 0,
					}}
				>
					{error ? (
						<text content={`  ⚠ ${error}`} fg={theme.error} />
					) : rows.length === 0 && !loading ? (
						<text content="  Nothing running" fg={theme.empty} />
					) : tab === "containers" ? (
						<ContainerList
							lines={layout.lines}
							selected={selected}
							onToggle={toggleFold}
						/>
					) : (
						portRows.map((p, i) => (
							// pid + address + port is unique by construction: ports() collapses
							// lsof's per-descriptor records onto one row per listener, so the
							// duplicate keys that forced an index key here can no longer occur.
							// A stable identity key lets React reuse the right row as the list
							// is re-sorted on each refresh.
							<box
								key={portKey(p)}
								style={{
									flexDirection: "row",
									height: 1,
									paddingLeft: 1,
									alignItems: "center",
								}}
							>
								<text
									content={`${i === selected ? "❯" : " "} ${String(p.port).padEnd(7)} ${clip(p.command, 20).padEnd(21)} ${String(p.pid).padEnd(8)} ${clip(p.address, 18).padEnd(19)} ${p.docker ? "DOCKER" : p.user}`}
									fg={
										i === selected
											? theme.portSelected
											: p.docker
												? theme.portDocker
												: theme.portRow
									}
								/>
							</box>
						))
					)}
				</scrollbox>
				<box
					title="Details"
					border
					style={{
						width: 34,
						borderColor: theme.border,
						padding: 1,
						flexDirection: "column",
					}}
				>
					{selectedItem ? (
						tab === "containers" ? (
							<>
								<text
									content={(selectedItem as Container).name}
									fg={theme.detailTitle}
								/>
								<text
									content={`\n${(selectedItem as Container).status}`}
									fg={stateColor((selectedItem as Container).state)}
								/>
								<text
									content={`\nimage  ${(selectedItem as Container).image}\nid      ${(selectedItem as Container).id.slice(0, 12)}\nports   ${(selectedItem as Container).ports}`}
									fg={theme.detailBody}
								/>
							</>
						) : (
							<>
								<text
									content={`:${(selectedItem as Port).port}`}
									fg={theme.detailTitle}
								/>
								<text
									content={`\n${(selectedItem as Port).command}`}
									fg={theme.detailValue}
								/>
								<text
									content={`\npid     ${(selectedItem as Port).pid}\nuser    ${(selectedItem as Port).user}\naddr    ${(selectedItem as Port).address}\ntype    ${(selectedItem as Port).type}`}
									fg={theme.detailBody}
								/>
							</>
						)
					) : (
						<text content="Select an item" fg={theme.empty} />
					)}
				</box>
			</box>
			<box style={{ height: 2, flexDirection: "row", alignItems: "center" }}>
				<text
					content={
					confirm
						? "  CONFIRM?  y or Enter / any key cancel"
						: `  ${message}`
				}
					fg={confirm ? theme.confirm : theme.message}
				/>
				<text
					content={
						tab === "containers"
							? "  s start/stop · r restart · d remove · f fold · Shift+f section"
							: "  x terminate · Shift+x force kill"
					}
					fg={theme.hint}
				/>
				{/* Eats the slack between the hints and the version so the version sits
				    flush right at any terminal width. flexShrink lets it collapse to
				    nothing on a narrow terminal rather than pushing the version off. */}
				<box style={{ flexGrow: 1, flexShrink: 1 }} />
				<text content={`v${pkg.version} `} fg={theme.version} />
			</box>
		</box>
	);
}

const renderer = await createCliRenderer({ exitOnCtrlC: true });
createRoot(renderer).render(<App />);
