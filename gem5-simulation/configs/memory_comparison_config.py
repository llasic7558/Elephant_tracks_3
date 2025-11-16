"""
gem5 Configuration for Memory Management Comparison
Compares explicit memory management vs garbage collection simulation
"""

import argparse
import sys
import os

import m5
from m5.objects import *
from m5.util import addToPath

# Parse command line arguments
parser = argparse.ArgumentParser(description='gem5 Memory Management Comparison')
parser.add_argument('binary', type=str, help='Path to trace replayer binary')
parser.add_argument('trace', type=str, help='Path to trace file')
parser.add_argument('mode', type=str, choices=['explicit', 'gc'], 
                    help='Memory management mode')
parser.add_argument('--cpu-type', type=str, default='timing',
                    choices=['atomic', 'timing', 'o3'],
                    help='CPU model type (default: timing)')
parser.add_argument('--cpu-clock', type=str, default='3GHz',
                    help='CPU clock frequency (default: 3GHz)')
parser.add_argument('--mem-size', type=str, default='8GB',
                    help='Memory size (default: 8GB)')
parser.add_argument('--l1i-size', type=str, default='32kB',
                    help='L1 instruction cache size (default: 32kB)')
parser.add_argument('--l1d-size', type=str, default='32kB',
                    help='L1 data cache size (default: 32kB)')
parser.add_argument('--l2-size', type=str, default='256kB',
                    help='L2 cache size (default: 256kB)')
parser.add_argument('--gc-threshold', type=int, default=10485760,
                    help='GC threshold in bytes (default: 10MB)')
parser.add_argument('--gc-alloc-count', type=int, default=1000,
                    help='GC after N allocations (default: 1000)')
parser.add_argument('--output-dir', type=str, default='m5out',
                    help='Output directory for stats (default: m5out)')
parser.add_argument('--verbose', action='store_true',
                    help='Enable verbose output')

args = parser.parse_args()

# Set output directory
m5.options.outdir = args.output_dir

# ============================================================================
# System Configuration
# ============================================================================

system = System()

# Clock domain
system.clk_domain = SrcClockDomain()
system.clk_domain.clock = args.cpu_clock
system.clk_domain.voltage_domain = VoltageDomain()

# Memory configuration
system.mem_mode = 'timing'
system.mem_ranges = [AddrRange(args.mem_size)]

# ============================================================================
# CPU Configuration
# ============================================================================

if args.cpu_type == 'atomic':
    system.cpu = AtomicSimpleCPU()
elif args.cpu_type == 'timing':
    system.cpu = TimingSimpleCPU()
elif args.cpu_type == 'o3':
    system.cpu = O3CPU()
    system.cpu.numROBEntries = 192
    system.cpu.numIQEntries = 64
    system.cpu.numLSQEntries = 32
else:
    print(f"Unknown CPU type: {args.cpu_type}")
    sys.exit(1)

print(f"CPU Type: {args.cpu_type}")
print(f"CPU Clock: {args.cpu_clock}")

# ============================================================================
# Cache Configuration
# ============================================================================

# L1 Instruction Cache
system.cpu.icache = Cache(
    size=args.l1i_size,
    assoc=8,
    tag_latency=1,
    data_latency=1,
    response_latency=1,
    mshrs=4,
    tgts_per_mshr=20
)

# L1 Data Cache
system.cpu.dcache = Cache(
    size=args.l1d_size,
    assoc=8,
    tag_latency=1,
    data_latency=1,
    response_latency=1,
    mshrs=4,
    tgts_per_mshr=20
)

# L2 Cache
system.l2cache = Cache(
    size=args.l2_size,
    assoc=16,
    tag_latency=10,
    data_latency=10,
    response_latency=10,
    mshrs=20,
    tgts_per_mshr=12
)

print(f"L1I Cache: {args.l1i_size}")
print(f"L1D Cache: {args.l1d_size}")
print(f"L2 Cache: {args.l2_size}")

# ============================================================================
# Memory Bus and Interconnect
# ============================================================================

system.membus = SystemXBar()
system.membus.badaddr_responder = BadAddr()
system.membus.default = system.membus.badaddr_responder.pio

# L2 Bus for connecting L1 caches to L2
system.l2bus = L2XBar()

# Connect L1 caches to L2 bus
system.cpu.icache.cpu_side = system.cpu.icache_port
system.cpu.icache.mem_side = system.l2bus.cpu_side_ports

system.cpu.dcache.cpu_side = system.cpu.dcache_port
system.cpu.dcache.mem_side = system.l2bus.cpu_side_ports

# Connect L2 cache
system.l2cache.cpu_side = system.l2bus.mem_side_ports
system.l2cache.mem_side = system.membus.cpu_side_ports

# ============================================================================
# Memory Controller Configuration
# ============================================================================

# Use DDR3 memory
system.mem_ctrl = MemCtrl()
system.mem_ctrl.dram = DDR3_1600_8x8()
system.mem_ctrl.dram.range = system.mem_ranges[0]
system.mem_ctrl.port = system.membus.mem_side_ports

print(f"Memory: DDR3-1600, Size: {args.mem_size}")

# ============================================================================
# System Setup
# ============================================================================

# Create interrupt controller for CPU
system.cpu.createInterruptController()

# For x86, connect interrupt ports
if m5.defines.buildEnv['TARGET_ISA'] == "x86":
    system.cpu.interrupts[0].pio = system.membus.mem_side_ports
    system.cpu.interrupts[0].int_requestor = system.membus.cpu_side_ports
    system.cpu.interrupts[0].int_responder = system.membus.mem_side_ports

# System port for functional access
system.system_port = system.membus.cpu_side_ports

# ============================================================================
# Workload Configuration
# ============================================================================

# Build command line for the replayer
cmd = [args.binary, args.trace, args.mode]

if args.mode == 'gc':
    cmd.extend([
        f'--gc-threshold={args.gc_threshold}',
        f'--gc-alloc-count={args.gc_alloc_count}'
    ])

if args.verbose:
    cmd.append('--verbose')

print(f"\nWorkload Command: {' '.join(cmd)}")

# Set up the process
process = Process()
process.cmd = cmd
system.cpu.workload = process
system.cpu.createThreads()

# ============================================================================
# Simulation Setup
# ============================================================================

# Instantiate the system
root = Root(full_system=False, system=system)
m5.instantiate()

print("\n=== Starting Simulation ===")
print(f"Mode: {args.mode}")
print(f"Output Directory: {args.output_dir}")

# Run the simulation
exit_event = m5.simulate()

print("\n=== Simulation Complete ===")
print(f"Exiting @ tick {m5.curTick()} because {exit_event.getCause()}")
print(f"\nStatistics written to: {args.output_dir}/stats.txt")
