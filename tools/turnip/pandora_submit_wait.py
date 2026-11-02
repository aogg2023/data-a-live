#!/usr/bin/env python3
"""Turnip's Darwin backend waits on the CPU for every sync before submitting. That deadlocks a
wait on a sync the ring's own later submission resolves (wait-before-signal turned into a wait for
completion). UniXNU fixed it on 2026-10-28 (commit 2c40ae9, "no CPU wait on syncs already on the
ring"); our build pins the 10-23 UniXNU tree, so apply the same change here.

  pandora_submit_wait.py MESA_DIR

The kernel client has one ring and each job's prologue waits for idle (NativeAdrenoRing::emitPrologue),
so a wait whose sync already resolved to a ring fence is met by the ring itself, as msm_gem_submit()
skips fences of the submitting ring's own context. A sync not yet resolved is waited for until it is
submitted, never for its completion.
"""
import pathlib
import sys

p = pathlib.Path(sys.argv[1]) / 'src/freedreno/vulkan/tu_knl_darwin.cc'
s = p.read_text()
old = """   /* The kernel client has one ring and no GPU-side waits: wait on the CPU before submitting. */
   for (uint32_t i = 0; i < wait_count; i++) {
      struct vk_darwin_sync *s = container_of(waits[i].sync, struct vk_darwin_sync, vk);
      VkResult result = darwin_sync_wait(dev, s, UINT64_MAX);
      if (result != VK_SUCCESS)
         return vk_device_set_lost(&dev->vk, "wait before submit failed");
   }
"""
new = """   /* data-a-live (UniXNU 2c40ae9): every client submits to the kernel's one ring, which runs jobs in order,
    * and each job's prologue flushes and invalidates the GPU caches and waits for idle (NativeAdrenoRing::
    * emitPrologue) before its buffers run. A wait on a sync already resolved to a ring fence is therefore
    * met by the ring itself, as msm_gem_submit() skips fences of the submitting ring's own context: the CPU
    * does not wait for that work to complete. A sync not yet resolved (wait-before-signal) is waited for
    * until it is submitted, never for its completion. */
   for (uint32_t i = 0; i < wait_count; i++) {
      struct vk_darwin_sync *s = container_of(waits[i].sync, struct vk_darwin_sync, vk);
      /* tu_queue_submit() holds submit_mutex here (tu_queue.cc), which the wait releases while it sleeps. */
      while (s->state == DARWIN_SYNC_UNSIGNALED)
         pthread_cond_wait(&dev->timeline_cond, &dev->submit_mutex);
   }
"""
assert s.count(old) == 1, ('submit wait block', s.count(old))
p.write_text(s.replace(old, new))
print('edited', p)
