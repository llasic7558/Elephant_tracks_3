#!/usr/bin/env python3
"""
Analyze and compare gem5 simulation results for explicit memory management
vs garbage collection
"""

import argparse
import re
import os
import json
from collections import defaultdict
import matplotlib.pyplot as plt
import numpy as np

class SimulationStats:
    def __init__(self, stats_file):
        self.stats_file = stats_file
        self.stats = {}
        self.parse_stats()
    
    def parse_stats(self):
        """Parse gem5 stats.txt file"""
        if not os.path.exists(self.stats_file):
            print(f"Warning: Stats file not found: {self.stats_file}")
            return
        
        with open(self.stats_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('---'):
                    continue
                
                # Parse stat lines: "stat_name   value   # description"
                parts = line.split()
                if len(parts) >= 2:
                    stat_name = parts[0]
                    try:
                        stat_value = float(parts[1])
                        self.stats[stat_name] = stat_value
                    except ValueError:
                        self.stats[stat_name] = parts[1]
    
    def get(self, stat_name, default=0):
        """Get a stat value by name"""
        return self.stats.get(stat_name, default)
    
    def __repr__(self):
        return f"SimulationStats({len(self.stats)} stats)"


class ResultAnalyzer:
    def __init__(self, explicit_dir, gc_dir):
        self.explicit_stats = SimulationStats(os.path.join(explicit_dir, 'stats.txt'))
        self.gc_stats = SimulationStats(os.path.join(gc_dir, 'stats.txt'))
        
    def compare_performance(self):
        """Compare overall performance metrics"""
        print("\n" + "="*80)
        print("PERFORMANCE COMPARISON")
        print("="*80)
        
        metrics = {
            'Total Cycles': 'system.cpu.numCycles',
            'Simulated Seconds': 'simSeconds',
            'Instructions': 'system.cpu.committedInsts',
            'IPC': 'system.cpu.ipc',
        }
        
        results = {}
        for name, stat_key in metrics.items():
            explicit_val = self.explicit_stats.get(stat_key)
            gc_val = self.gc_stats.get(stat_key)
            
            if explicit_val and gc_val and explicit_val != 0:
                overhead = ((gc_val - explicit_val) / explicit_val) * 100
            else:
                overhead = 0
            
            results[name] = {
                'explicit': explicit_val,
                'gc': gc_val,
                'overhead_%': overhead
            }
            
            print(f"\n{name}:")
            print(f"  Explicit:  {explicit_val:,.2f}")
            print(f"  GC:        {gc_val:,.2f}")
            print(f"  Overhead:  {overhead:+.2f}%")
        
        return results
    
    def compare_cache_behavior(self):
        """Compare cache hit rates and miss rates"""
        print("\n" + "="*80)
        print("CACHE BEHAVIOR COMPARISON")
        print("="*80)
        
        cache_stats = {
            'L1 Data Cache': {
                'Overall Hit Rate': 'system.cpu.dcache.overall_hit_rate::total',
                'Overall Miss Rate': 'system.cpu.dcache.overall_miss_rate::total',
                'Average Miss Latency': 'system.cpu.dcache.overall_avg_miss_latency::total',
                'Total Accesses': 'system.cpu.dcache.overall_accesses::total',
                'Total Misses': 'system.cpu.dcache.overall_misses::total',
            },
            'L1 Instruction Cache': {
                'Overall Hit Rate': 'system.cpu.icache.overall_hit_rate::total',
                'Overall Miss Rate': 'system.cpu.icache.overall_miss_rate::total',
                'Average Miss Latency': 'system.cpu.icache.overall_avg_miss_latency::total',
                'Total Accesses': 'system.cpu.icache.overall_accesses::total',
            },
            'L2 Cache': {
                'Overall Hit Rate': 'system.l2cache.overall_hit_rate::total',
                'Overall Miss Rate': 'system.l2cache.overall_miss_rate::total',
                'Average Miss Latency': 'system.l2cache.overall_avg_miss_latency::total',
                'Total Accesses': 'system.l2cache.overall_accesses::total',
                'Total Misses': 'system.l2cache.overall_misses::total',
            }
        }
        
        results = {}
        for cache_name, stats_dict in cache_stats.items():
            print(f"\n{cache_name}:")
            results[cache_name] = {}
            
            for metric_name, stat_key in stats_dict.items():
                explicit_val = self.explicit_stats.get(stat_key)
                gc_val = self.gc_stats.get(stat_key)
                
                results[cache_name][metric_name] = {
                    'explicit': explicit_val,
                    'gc': gc_val
                }
                
                print(f"  {metric_name}:")
                print(f"    Explicit:  {explicit_val:,.4f}")
                print(f"    GC:        {gc_val:,.4f}")
                if explicit_val != 0:
                    diff = ((gc_val - explicit_val) / explicit_val) * 100
                    print(f"    Diff:      {diff:+.2f}%")
        
        return results
    
    def compare_memory_bandwidth(self):
        """Compare memory bandwidth usage"""
        print("\n" + "="*80)
        print("MEMORY BANDWIDTH COMPARISON")
        print("="*80)
        
        # Bytes read/written
        stats = {
            'Memory Bytes Read': 'system.mem_ctrl.bytes_read::total',
            'Memory Bytes Written': 'system.mem_ctrl.bytes_written::total',
            'Memory Read Bandwidth (MB/s)': 'system.mem_ctrl.bw_read::total',
            'Memory Write Bandwidth (MB/s)': 'system.mem_ctrl.bw_write::total',
        }
        
        results = {}
        for name, stat_key in stats.items():
            explicit_val = self.explicit_stats.get(stat_key)
            gc_val = self.gc_stats.get(stat_key)
            
            # Convert to MB if it's bytes
            if 'Bytes' in name:
                explicit_val /= (1024 * 1024)
                gc_val /= (1024 * 1024)
            
            results[name] = {
                'explicit': explicit_val,
                'gc': gc_val
            }
            
            print(f"\n{name}:")
            print(f"  Explicit:  {explicit_val:,.2f}")
            print(f"  GC:        {gc_val:,.2f}")
            if explicit_val != 0:
                diff = ((gc_val - explicit_val) / explicit_val) * 100
                print(f"  Diff:      {diff:+.2f}%")
        
        return results
    
    def generate_plots(self, output_dir='plots'):
        """Generate comparison plots"""
        os.makedirs(output_dir, exist_ok=True)
        
        # Plot 1: Performance Metrics
        self._plot_performance(output_dir)
        
        # Plot 2: Cache Behavior
        self._plot_cache_behavior(output_dir)
        
        # Plot 3: Memory Bandwidth
        self._plot_memory_bandwidth(output_dir)
        
        print(f"\nPlots saved to: {output_dir}/")
    
    def _plot_performance(self, output_dir):
        """Plot performance comparison"""
        metrics = ['Total Cycles', 'Instructions', 'IPC']
        stat_keys = [
            'system.cpu.numCycles',
            'system.cpu.committedInsts',
            'system.cpu.ipc'
        ]
        
        explicit_vals = [self.explicit_stats.get(k) for k in stat_keys]
        gc_vals = [self.gc_stats.get(k) for k in stat_keys]
        
        # Normalize to make comparison easier
        normalized_explicit = []
        normalized_gc = []
        for e, g in zip(explicit_vals, gc_vals):
            if e != 0:
                normalized_explicit.append(1.0)
                normalized_gc.append(g / e)
            else:
                normalized_explicit.append(0)
                normalized_gc.append(0)
        
        x = np.arange(len(metrics))
        width = 0.35
        
        fig, ax = plt.subplots(figsize=(10, 6))
        ax.bar(x - width/2, normalized_explicit, width, label='Explicit', color='skyblue')
        ax.bar(x + width/2, normalized_gc, width, label='GC', color='lightcoral')
        
        ax.set_xlabel('Metrics')
        ax.set_ylabel('Normalized Value')
        ax.set_title('Performance Comparison (Normalized to Explicit=1.0)')
        ax.set_xticks(x)
        ax.set_xticklabels(metrics)
        ax.legend()
        ax.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, 'performance_comparison.png'), dpi=300)
        plt.close()
    
    def _plot_cache_behavior(self, output_dir):
        """Plot cache miss rates"""
        caches = ['L1D', 'L1I', 'L2']
        stat_keys = [
            'system.cpu.dcache.overall_miss_rate::total',
            'system.cpu.icache.overall_miss_rate::total',
            'system.l2cache.overall_miss_rate::total'
        ]
        
        explicit_vals = [self.explicit_stats.get(k) * 100 for k in stat_keys]
        gc_vals = [self.gc_stats.get(k) * 100 for k in stat_keys]
        
        x = np.arange(len(caches))
        width = 0.35
        
        fig, ax = plt.subplots(figsize=(10, 6))
        ax.bar(x - width/2, explicit_vals, width, label='Explicit', color='skyblue')
        ax.bar(x + width/2, gc_vals, width, label='GC', color='lightcoral')
        
        ax.set_xlabel('Cache Level')
        ax.set_ylabel('Miss Rate (%)')
        ax.set_title('Cache Miss Rate Comparison')
        ax.set_xticks(x)
        ax.set_xticklabels(caches)
        ax.legend()
        ax.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, 'cache_miss_rates.png'), dpi=300)
        plt.close()
    
    def _plot_memory_bandwidth(self, output_dir):
        """Plot memory bandwidth comparison"""
        operations = ['Read', 'Write']
        stat_keys = [
            'system.mem_ctrl.bytes_read::total',
            'system.mem_ctrl.bytes_written::total'
        ]
        
        # Convert to MB
        explicit_vals = [self.explicit_stats.get(k) / (1024 * 1024) for k in stat_keys]
        gc_vals = [self.gc_stats.get(k) / (1024 * 1024) for k in stat_keys]
        
        x = np.arange(len(operations))
        width = 0.35
        
        fig, ax = plt.subplots(figsize=(10, 6))
        ax.bar(x - width/2, explicit_vals, width, label='Explicit', color='skyblue')
        ax.bar(x + width/2, gc_vals, width, label='GC', color='lightcoral')
        
        ax.set_xlabel('Operation')
        ax.set_ylabel('Data Volume (MB)')
        ax.set_title('Memory Bandwidth Comparison')
        ax.set_xticks(x)
        ax.set_xticklabels(operations)
        ax.legend()
        ax.grid(True, alpha=0.3)
        
        plt.tight_layout()
        plt.savefig(os.path.join(output_dir, 'memory_bandwidth.png'), dpi=300)
        plt.close()
    
    def generate_report(self, output_file='comparison_report.txt'):
        """Generate a comprehensive text report"""
        with open(output_file, 'w') as f:
            f.write("="*80 + "\n")
            f.write("GEM5 MEMORY MANAGEMENT COMPARISON REPORT\n")
            f.write("="*80 + "\n\n")
            
            # Redirect print to file
            import sys
            old_stdout = sys.stdout
            sys.stdout = f
            
            self.compare_performance()
            self.compare_cache_behavior()
            self.compare_memory_bandwidth()
            
            # Restore stdout
            sys.stdout = old_stdout
        
        print(f"\nReport saved to: {output_file}")


def main():
    parser = argparse.ArgumentParser(
        description='Analyze gem5 simulation results for memory management comparison'
    )
    parser.add_argument('explicit_dir', help='Directory with explicit mode results')
    parser.add_argument('gc_dir', help='Directory with GC mode results')
    parser.add_argument('--plot', action='store_true', 
                        help='Generate comparison plots')
    parser.add_argument('--report', type=str, default='comparison_report.txt',
                        help='Output report file (default: comparison_report.txt)')
    parser.add_argument('--plot-dir', type=str, default='plots',
                        help='Directory for plots (default: plots)')
    
    args = parser.parse_args()
    
    print(f"Analyzing results...")
    print(f"  Explicit mode: {args.explicit_dir}")
    print(f"  GC mode:       {args.gc_dir}")
    
    analyzer = ResultAnalyzer(args.explicit_dir, args.gc_dir)
    
    # Print to console
    analyzer.compare_performance()
    analyzer.compare_cache_behavior()
    analyzer.compare_memory_bandwidth()
    
    # Generate report
    analyzer.generate_report(args.report)
    
    # Generate plots if requested
    if args.plot:
        try:
            analyzer.generate_plots(args.plot_dir)
        except ImportError:
            print("\nWarning: matplotlib not available, skipping plots")
            print("Install with: pip install matplotlib numpy")


if __name__ == '__main__':
    main()
