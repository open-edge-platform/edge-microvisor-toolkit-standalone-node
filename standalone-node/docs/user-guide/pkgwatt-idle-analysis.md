# Why a Lower-GPU-Core System Can Show Higher Idle `PkgWatt`

## Scope

This note explains why a system with fewer GPU cores can still report higher package power (`PkgWatt`)
in `turbostat` while both systems are on the `powersave` CPU governor in Ubuntu 24.04.

`PkgWatt` is whole-package energy over time, not only GPU core power. It includes CPU cores, uncore,
SoC fabric, memory controller, display/media blocks, and leakage.

## Why This Happens

### 1. Platform Power Limits and BIOS Policy Can Dominate

Even with the same CPU model family, OEM BIOS policy can differ:

- PL1/PL2 configuration and time windows
- cTDP-up/cTDP-down policy
- package C-state limits (`PC10` disabled, package floor states forced)
- background features enabled in firmware (telemetry, debug, device polling)

A system configured for higher sustained responsiveness can hold higher voltage/frequency floors,
raising idle `PkgWatt` regardless of GPU core count.

### 2. Uncore Frequency Floor Often Matters More Than GPU Core Count at Idle

Your sample already shows different uncore clocks (`800 MHz` vs `500 MHz`). A higher uncore floor can
increase idle package power significantly because ring/interconnect/memory-controller domains stay active.

Also check display/media blocks and fabric clocks, which may not collapse if any client prevents deep idle.

### 3. Package C-State Residency Is Usually the Biggest Idle Differentiator

If one system spends less time in deep package states (`PC8/PC10`), `PkgWatt` rises.
Common blockers:

- frequent timer wakeups and kernel threads
- PCIe/NVMe devices with active ASPM disabled
- networking interrupt activity
- iGPU/display or media blocks not entering low-power states
- virtualization or monitoring services causing periodic wakeups

### 4. iGPU/Xe Driver and Boot Parameters Can Change Idle Behavior

Kernel/driver configuration can keep domains awake:

- `i915.force_probe` or `xe.force_probe` combinations
- unexpected module blacklist interactions (`i915` vs `xe`)
- `xe.max_vfs` or SR-IOV settings creating persistent VF overhead
- debug options (`drm.debug`, tracing, perf sampling) increasing wakeups

Two systems using different driver stacks or parameters can show different idle package power,
independent of physical GPU core count.

### 5. Silicon Variability and Thermal/Voltage Effects

Even same SKU CPUs vary due to process spread and leakage.
At low load, leakage and voltage floor differences can dominate dynamic power:

- higher leakage die may show higher `PkgWatt` at similar residency
- warmer silicon usually needs higher leakage current
- board-level VR behavior and memory subsystem can shift package idle power

### 6. Background OS Workload Differences

`powersave` only influences CPU frequency policy. It does not guarantee identical idle residency.
Different services, telemetry agents, containers, irq affinity, or polling loops can keep one platform
out of deep idle states.

## Deep-Dive Diagnostics

Collect data on both systems under the same conditions (AC state, display state, BIOS profile,
kernel, same userspace services). Use at least 60-120 seconds of sampling.

### A. Compare package/core residency with turbostat

```bash
sudo turbostat --Summary --show Busy%,Bzy_MHz,Avg_MHz,PkgWatt,PkgTmp,CorWatt,GFXWatt,RAMWatt,Pkg%pc2,Pkg%pc6,Pkg%pc8,Pkg%pc10 --interval 2 --num_iterations 30
```

Focus on:

- `Pkg%pc8` / `Pkg%pc10` (higher is better for idle)
- `Busy%` and `Avg_MHz` (unexpected activity)
- `PkgTmp` and `PkgWatt` stability

### B. Check CPU idle state usage

```bash
for c in /sys/devices/system/cpu/cpu0/cpuidle/state*/name; do echo "$(basename "$(dirname "$c")"): $(cat "$c")"; done
for s in /sys/devices/system/cpu/cpu0/cpuidle/state*/time; do echo "$(basename "$(dirname "$s")"): $(cat "$s")"; done
```

Also verify package-level state policy in BIOS (allow deepest package C-state).

### C. Validate kernel cmdline and driver state

```bash
cat /proc/cmdline
lsmod | egrep '^(xe|i915)'
journalctl -k --no-pager | egrep -i 'xe|i915|drm|force_probe|sriov|max_vfs'
```

Ensure one coherent graphics stack is active and parameters are intentional.

### D. Inspect PCIe runtime power and ASPM

```bash
for d in /sys/bus/pci/devices/*/power/control; do echo "$d: $(cat "$d")"; done | head -n 40
grep . /sys/module/pcie_aspm/parameters/policy
```

Devices stuck in `on` can block deeper package states.

### E. Find wakeup sources and scheduler noise

```bash
sudo powertop --time=20 --html=/tmp/powertop-idle.html
sudo perf stat -a -e power/energy-pkg/,sched:sched_wakeup -- sleep 20
```

Compare top wakeup offenders between systems.

## BIOS/Firmware Checklist

- Same BIOS revision and same profile (performance/power balanced)
- Deep package C-states enabled (`PC10` allowed)
- C1E/C-states not restricted
- ASPM enabled where stable
- Uncore/fabric minimum frequency not forced high
- SR-IOV/VF count (`xe.max_vfs`) aligned with test scenario
- Memory settings (speed/gear) comparable across systems

## Practical Recommendations

1. Normalize platform state first:
   - same BIOS, kernel, cmdline, graphics driver path, services, display state.
2. Use residency as primary KPI:
   - target higher `Pkg%pc8/pc10` rather than only lower instantaneous `PkgWatt`.
3. Reduce uncore floor and wakeups:
   - enable runtime PM, ASPM, and remove unnecessary polling/monitoring loops.
4. Test with controlled idle scenarios:
   - screen off vs on, network connected vs isolated, telemetry off vs on.
5. If delta persists after normalization:
   - treat as silicon/platform variance and characterize with repeated long-window averages.

## Interpretation of Your Example

From your provided samples, the lower-GPU-core system already shows higher uncore MHz and higher package
temperature, both consistent with a higher package power floor. This supports the hypothesis that uncore,
residency, and platform policy are stronger contributors than GPU core count alone.
