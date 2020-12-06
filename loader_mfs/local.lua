--
--

local function set_system_version_specific_env()
   local common = {
      ["hint.acpi_throttle.0.disabled"] = "1",
      ["hint.p4tcc.0.disabled"]         = "1",
      ["hw.pci.do_power_nodriver"]      = "3"
   }
   local drm_i915 = {
      ["drm.i915.enable_rc6"]           = "7",
      ["drm.i915.powersave"]            = "1",
      ["drm.i915.intel_iommu_enabled"]  = "1",
      ["drm.i915.lvds_downclock"]       = "1",
      ["drm.i915.semaphores"]           = "1",
      ["drm.i915.enable_fbc"]           = "1"
   }
   local env = {}

   local v = loader.getenv("smbios.system.version") or "no"

   if     v == "ThinkPad T14 Gen 1" then
      env = { common, { ["hw.vmm.amdvi.enable"] = "1" } }
   elseif v == "ThinkPad W541"
       or v == "ThinkPad X230"
       or v == "ThinkPad T410s"     then
      env = { common, drm_i915 }
   end

   for k,v in next, env do for k, v in next, v do
	 loader.setenv(k,v) end end
end

set_system_version_specific_env()
