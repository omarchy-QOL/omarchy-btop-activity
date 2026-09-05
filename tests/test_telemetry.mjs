import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'
import vm from 'node:vm'

const root = path.resolve(import.meta.dirname, '..')
const model = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(root, 'lib/Telemetry.js'), 'utf8')
  .replace(/^\.pragma library\n/, ''), model)
const state = () => ({
  metadata: {}, attempted: {}, retryAfter: {}, amdIds: null,
  xpuInfo: {}, fdPrevious: null
})
const device = (vendor = '0x8086', driver = 'i915', id = '0000:00:02.0') => {
  const gpu = model.emptyGpu({
    id, vendor, driver, card: 'card1',
    path: '/sys/devices/pci0000:00/' + id
  }, {})
  gpu.status = 'active'
  return gpu
}

test('discovery resolves PCI aliases for the Intel sys selector', () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'btop-discovery-'))
  try {
    const gpu = path.join(fixture, 'devices/pci0000:00/0000:00:02.0')
    const aliases = path.join(fixture, 'bus/pci/devices')
    fs.mkdirSync(path.join(gpu, 'drm/card1'), { recursive: true })
    fs.mkdirSync(aliases, { recursive: true })
    fs.writeFileSync(path.join(gpu, 'class'), '0x030000\n')
    fs.writeFileSync(path.join(gpu, 'vendor'), '0x8086\n')
    fs.symlinkSync('/sys/bus/pci/drivers/i915', path.join(gpu, 'driver'))
    fs.symlinkSync(gpu, path.join(aliases, '0000:00:02.0'))
    const raw = execFileSync('/bin/bash', ['helpers/discover-telemetry.sh'], {
      cwd: root, encoding: 'utf8', env: { ...process.env, BTOP_SYS_ROOT: fixture }
    })
    const inventory = model.discovery(raw)
    assert.equal(inventory.gpus.length, 1)
    assert.equal(inventory.gpus[0].path, gpu)
    const sample = device()
    sample.path = inventory.gpus[0].path
    const job = model.nextJob([sample], { intel_gpu_top: '/usr/bin/intel_gpu_top' },
      state(), root, Date.now())
    assert.equal(job.command.at(-1), 'sys:' + gpu)
  } finally {
    fs.rmSync(fixture, { recursive: true, force: true })
  }
})

test('Intel package presence selects the reader, absence keeps the fallback', () => {
  const gpu = device()
  const tools = { intel_gpu_top: '/usr/bin/intel_gpu_top' }
  assert.equal(model.nextJob([gpu], tools, state(), root, Date.now()).kind, 'intel')
  assert.equal(model.nextJob([gpu], {}, state(), root, Date.now()).kind, 'fdinfo')
  assert.equal(model.nextJob([gpu], tools, state(), root, Date.now()).kind, 'intel')
})

test('Intel uses the last complete device sample, not client counters', () => {
  const intel = device()
  const amd = device('0x1002', 'amdgpu', '0000:03:00.0')
  const raw = JSON.stringify([
    { engines: { Render: { busy: 99 } } },
    { engines: { Render: { busy: 27 }, Video: { busy: 6 } },
      clients: { one: { busy: 90 } } }
  ])
  model.applyBackend({ kind: 'intel', ids: [intel.id] }, raw, [amd, intel], state())
  assert.equal(intel.usage, 27)
  assert.equal(intel.sources.usage, 'intel_gpu_top')
  assert.equal(intel.scope, 'device')
  assert.equal(amd.usage, null)
})

test('Intel rejects warmup-only and invalid samples, but accepts idle zero', () => {
  for (const samples of [
    [{ engines: { Render: { busy: 32 } } }],
    [{}, { engines: { Render: { busy: 101 }, Video: { busy: null } } }]
  ]) {
    const gpu = device()
    model.applyBackend({ kind: 'intel', ids: [gpu.id] }, JSON.stringify(samples),
      [gpu], state())
    assert.equal(gpu.usage, null)
  }
  const gpu = device()
  model.applyBackend({ kind: 'intel', ids: [gpu.id] },
    '[{}, {"engines":{"Render":{"busy":0}}}]', [gpu], state())
  assert.equal(gpu.usage, 0)
})

test('AMD kernel readings do not acquire a ROCm dependency', () => {
  const gpu = device('0x1002', 'amdgpu', '0000:03:00.0')
  gpu.memoryKind = 'dedicated'
  model.merge([gpu], gpu.id,
    { usage: 12, temperature: 36, memoryUsed: 1024, memoryTotal: 4096 }, 'kernel')
  for (const tools of [{}, { 'rocm-smi': '/usr/bin/rocm-smi' }, {}]) {
    assert.equal(model.nextJob([gpu], tools, state(), root, Date.now()), null)
    assert.equal(gpu.usage, 12)
    assert.equal(gpu.sources.temperature, 'kernel')
  }
})

test('ROCm fills missing AMD fields and matches PCI IDs, not card numbers', () => {
  const gpu = device('0x1002', 'amdgpu', '0000:03:00.0')
  const intel = device()
  const job = model.nextJob([gpu], { 'rocm-smi': '/usr/bin/rocm-smi' },
    state(), root, Date.now())
  assert.equal(job.kind, 'rocm')
  model.applyBackend(job, JSON.stringify({ card9: {
    'PCI Bus': gpu.id, 'GPU use (%)': '13',
    'Temperature (Sensor edge) (C)': '37',
    'VRAM Total Used Memory (B)': '1024', 'VRAM Total Memory (B)': '4096'
  } }), [intel, gpu], state())
  assert.equal(gpu.usage, 13)
  assert.equal(gpu.temperature, 37)
  assert.equal(gpu.memoryUsed, 1024)
  assert.equal(gpu.sources.usage, 'rocm-smi')
  assert.equal(intel.usage, null)
})

test('stale optional readings expire after a reader disappears', () => {
  const old = device()
  model.merge([old], old.id, { usage: 42 }, 'intel_gpu_top')
  const time = old.updated.usage
  const next = device()
  assert.equal(model.publish([next], [old], time + 1000, 5000)[0].usage, 42)
  assert.equal(model.publish([device()], [old], time + 6000, 5000)[0].usage, null)
})

test('a sleeping Intel GPU is never queried', () => {
  const gpu = device()
  gpu.status = 'sleeping'
  assert.equal(model.nextJob([gpu], { intel_gpu_top: '/usr/bin/intel_gpu_top' },
    state(), root, Date.now()), null)
})
