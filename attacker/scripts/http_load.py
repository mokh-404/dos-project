#!/usr/bin/env python3
"""
DoS Lab — Async HTTP Load Simulator
====================================
Generates controlled HTTP load for performance analysis.

EDUCATIONAL USE ONLY — ISOLATED DOCKER LAB
Do NOT use against external systems.
"""

import asyncio
import argparse
import time
import statistics
import json
import os
from datetime import datetime, timezone
from collections import defaultdict

try:
    import aiohttp
    HAS_AIOHTTP = True
except ImportError:
    HAS_AIOHTTP = False

try:
    from rich.console import Console
    from rich.table import Table
    from rich.progress import Progress, SpinnerColumn, BarColumn, TimeElapsedColumn
    from rich.panel import Panel
    HAS_RICH = True
except ImportError:
    HAS_RICH = False


# ── Configuration ─────────────────────────────────────────────
DEFAULT_TARGET  = os.getenv("TARGET_HOST", "172.21.0.10")
DEFAULT_PORT    = int(os.getenv("TARGET_PORT", "80"))
DEFAULT_RATE    = int(os.getenv("ATTACK_RATE", "50"))
DEFAULT_DUR     = int(os.getenv("ATTACK_DURATION", "30"))
DEFAULT_CONC    = int(os.getenv("ATTACK_CONCURRENCY", "10"))

ENDPOINTS = [
    "/",
    "/about.html",
    "/api.html",
    "/health",
    "/contact.html",
]


class LoadSimulator:
    """Async HTTP load simulator with metrics collection."""

    def __init__(self, target_host, target_port, rate, duration, concurrency):
        self.base_url = f"http://{target_host}:{target_port}"
        self.rate = rate
        self.duration = duration
        self.concurrency = concurrency
        self.results = []
        self.errors = defaultdict(int)
        self.status_codes = defaultdict(int)
        self.start_time = None
        self.console = Console() if HAS_RICH else None

    def _log(self, msg, style=None):
        if self.console and style:
            self.console.print(msg, style=style)
        else:
            print(msg)

    async def fetch(self, session, url, req_num):
        """Perform a single HTTP request and record metrics."""
        start = time.monotonic()
        try:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                await resp.read()
                elapsed = (time.monotonic() - start) * 1000  # ms
                self.results.append(elapsed)
                self.status_codes[resp.status] += 1
                return resp.status, elapsed
        except asyncio.TimeoutError:
            self.errors["timeout"] += 1
            return None, None
        except aiohttp.ClientConnectionError:
            self.errors["connection_error"] += 1
            return None, None
        except Exception as e:
            self.errors[type(e).__name__] += 1
            return None, None

    async def worker(self, session, endpoint_cycle, stop_event):
        """Worker coroutine: sends requests until stop_event is set."""
        req_count = 0
        while not stop_event.is_set():
            endpoint = ENDPOINTS[req_count % len(ENDPOINTS)]
            url = f"{self.base_url}{endpoint}"
            await self.fetch(session, url, req_count)
            req_count += 1
            # Rate limiting: sleep to maintain target rate per worker
            if self.rate > 0:
                sleep_time = self.concurrency / self.rate
                await asyncio.sleep(sleep_time)

    async def run(self):
        """Execute the load simulation."""
        if not HAS_AIOHTTP:
            print("[ERROR] aiohttp not installed. Run: pip install aiohttp")
            return None

        self._log(Panel(
            "[bold cyan]DoS Lab — Async HTTP Load Simulator[/bold cyan]\n"
            "[yellow]⚠ Educational use only — isolated Docker lab[/yellow]",
            title="[bold]Load Simulation Engine[/bold]"
        ) if HAS_RICH else "=== DoS Lab HTTP Load Simulator ===")

        self._log(f"\nTarget   : {self.base_url}")
        self._log(f"Rate     : ~{self.rate} req/s")
        self._log(f"Duration : {self.duration}s")
        self._log(f"Workers  : {self.concurrency}")
        self._log(f"Endpoints: {len(ENDPOINTS)}\n")

        stop_event = asyncio.Event()
        connector = aiohttp.TCPConnector(limit=self.concurrency + 5)

        self.start_time = time.monotonic()

        async with aiohttp.ClientSession(connector=connector) as session:
            # Schedule stop
            async def stopper():
                await asyncio.sleep(self.duration)
                stop_event.set()

            workers = [self.worker(session, ENDPOINTS, stop_event)
                       for _ in range(self.concurrency)]

            self._log("Starting load simulation...")
            await asyncio.gather(stopper(), *workers, return_exceptions=True)

        elapsed = time.monotonic() - self.start_time
        return self._build_report(elapsed)

    def _build_report(self, elapsed):
        """Build a statistics report from collected results."""
        total = len(self.results) + sum(self.errors.values())
        successful = len(self.results)
        failed = sum(self.errors.values())

        if not self.results:
            return {"error": "No successful responses recorded"}

        report = {
            "meta": {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "target": self.base_url,
                "rate_target": self.rate,
                "duration_target": self.duration,
                "concurrency": self.concurrency,
                "elapsed_seconds": round(elapsed, 2),
            },
            "summary": {
                "total_requests": total,
                "successful": successful,
                "failed": failed,
                "success_rate_pct": round(successful / total * 100, 2) if total else 0,
                "actual_rps": round(successful / elapsed, 2) if elapsed else 0,
            },
            "latency_ms": {
                "min": round(min(self.results), 2),
                "max": round(max(self.results), 2),
                "mean": round(statistics.mean(self.results), 2),
                "median": round(statistics.median(self.results), 2),
                "p95": round(sorted(self.results)[int(len(self.results) * 0.95)], 2),
                "p99": round(sorted(self.results)[int(len(self.results) * 0.99)], 2),
                "stdev": round(statistics.stdev(self.results), 2) if len(self.results) > 1 else 0,
            },
            "status_codes": dict(self.status_codes),
            "errors": dict(self.errors),
        }
        return report

    def print_report(self, report):
        """Print the report in a formatted way."""
        if not report or "error" in report:
            print(f"Error: {report.get('error', 'unknown')}")
            return

        if HAS_RICH:
            console = Console()

            # Summary table
            t = Table(title="Load Simulation Results", show_header=True)
            t.add_column("Metric", style="cyan")
            t.add_column("Value", style="green")
            s = report["summary"]
            m = report["meta"]
            l = report["latency_ms"]

            t.add_row("Target",           m["target"])
            t.add_row("Elapsed",          f"{m['elapsed_seconds']}s")
            t.add_row("Total Requests",   str(s["total_requests"]))
            t.add_row("Successful",       str(s["successful"]))
            t.add_row("Failed",           str(s["failed"]))
            t.add_row("Success Rate",     f"{s['success_rate_pct']}%")
            t.add_row("Actual RPS",       str(s["actual_rps"]))
            t.add_row("Latency Min",      f"{l['min']} ms")
            t.add_row("Latency Median",   f"{l['median']} ms")
            t.add_row("Latency p95",      f"{l['p95']} ms")
            t.add_row("Latency p99",      f"{l['p99']} ms")
            t.add_row("Latency Max",      f"{l['max']} ms")

            console.print(t)

            # Status codes
            sc_table = Table(title="HTTP Status Codes")
            sc_table.add_column("Code", style="cyan")
            sc_table.add_column("Count", style="yellow")
            for code, count in sorted(report["status_codes"].items()):
                color = "green" if str(code).startswith("2") else "red"
                sc_table.add_row(f"[{color}]{code}[/{color}]", str(count))
            console.print(sc_table)
        else:
            print("\n=== Load Simulation Results ===")
            for section, data in report.items():
                print(f"\n[{section.upper()}]")
                if isinstance(data, dict):
                    for k, v in data.items():
                        print(f"  {k}: {v}")


def main():
    parser = argparse.ArgumentParser(
        description="DoS Lab — Async HTTP Load Simulator (Educational Use Only)"
    )
    parser.add_argument("--target",      default=DEFAULT_TARGET, help="Target host")
    parser.add_argument("--port",        type=int, default=DEFAULT_PORT, help="Target port")
    parser.add_argument("--rate",        type=int, default=DEFAULT_RATE,  help="Target req/s")
    parser.add_argument("--duration",    type=int, default=DEFAULT_DUR,   help="Duration seconds")
    parser.add_argument("--concurrency", type=int, default=DEFAULT_CONC,  help="Concurrency")
    parser.add_argument("--output",      default="/reports",              help="Output directory")
    args = parser.parse_args()

    sim = LoadSimulator(
        target_host=args.target,
        target_port=args.port,
        rate=args.rate,
        duration=args.duration,
        concurrency=args.concurrency,
    )

    report = asyncio.run(sim.run())
    if report:
        sim.print_report(report)
        # Save JSON report
        os.makedirs(args.output, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        outfile = os.path.join(args.output, f"http_load_{ts}.json")
        with open(outfile, "w") as f:
            json.dump(report, f, indent=2)
        print(f"\n[+] JSON report saved: {outfile}")


if __name__ == "__main__":
    main()
