use crate::api::GpuSnapshot;
use libloading::os::unix::Library;
use std::ffi::{CStr, c_char, c_int, c_uint, c_ulonglong, c_void};
use std::ptr;
use std::sync::{Mutex, OnceLock};

const SUCCESS: c_int = 0;
const UNINITIALIZED: c_int = 1;
const NOT_SUPPORTED: c_int = 3;
const NO_PERMISSION: c_int = 4;
const TEMPERATURE_GPU: c_uint = 0;

type Device = *mut c_void;
type DeviceText = unsafe extern "C" fn(Device, *mut c_char, c_uint) -> c_int;

#[repr(C)]
#[derive(Default)]
struct Utilization {
    gpu: c_uint,
    memory: c_uint,
}

#[repr(C)]
#[derive(Default)]
struct Memory {
    total: c_ulonglong,
    free: c_ulonglong,
    used: c_ulonglong,
}

#[repr(C)]
struct MemoryV2 {
    version: c_uint,
    total: c_ulonglong,
    reserved: c_ulonglong,
    free: c_ulonglong,
    used: c_ulonglong,
}

impl Default for MemoryV2 {
    fn default() -> Self {
        Self {
            version: (2 << 24) | (size_of::<Self>() as c_uint),
            total: 0,
            reserved: 0,
            free: 0,
            used: 0,
        }
    }
}

struct Nvml {
    _library: Library,
    initialized: Mutex<bool>,
    init: unsafe extern "C" fn() -> c_int,
    count: unsafe extern "C" fn(*mut c_uint) -> c_int,
    handle: unsafe extern "C" fn(c_uint, *mut Device) -> c_int,
    uuid: DeviceText,
    name: DeviceText,
    utilization: unsafe extern "C" fn(Device, *mut Utilization) -> c_int,
    memory: unsafe extern "C" fn(Device, *mut Memory) -> c_int,
    memory_v2: Option<unsafe extern "C" fn(Device, *mut MemoryV2) -> c_int>,
    temperature: unsafe extern "C" fn(Device, c_uint, *mut c_uint) -> c_int,
}

/// Call only from a blocking worker. A loaded driver stays resident for the process.
pub(crate) fn gpus() -> Option<Vec<GpuSnapshot>> {
    static NVML: OnceLock<Option<Nvml>> = OnceLock::new();
    NVML.get_or_init(Nvml::load).as_ref()?.sample()
}

impl Nvml {
    fn load() -> Option<Self> {
        // SAFETY: The system SONAME provides the NVML C ABI. Keep the library
        // resident with its typed symbols for as long as they can be called.
        unsafe {
            let library = Library::new("libnvidia-ml.so.1").ok()?;
            Some(Self {
                initialized: Mutex::new(false),
                init: *library.get(b"nvmlInit_v2\0").ok()?,
                count: *library.get(b"nvmlDeviceGetCount_v2\0").ok()?,
                handle: *library.get(b"nvmlDeviceGetHandleByIndex_v2\0").ok()?,
                uuid: *library.get(b"nvmlDeviceGetUUID\0").ok()?,
                name: *library.get(b"nvmlDeviceGetName\0").ok()?,
                utilization: *library.get(b"nvmlDeviceGetUtilizationRates\0").ok()?,
                memory: *library.get(b"nvmlDeviceGetMemoryInfo\0").ok()?,
                memory_v2: library
                    .get(b"nvmlDeviceGetMemoryInfo_v2\0")
                    .ok()
                    .map(|f| *f),
                temperature: *library.get(b"nvmlDeviceGetTemperature\0").ok()?,
                _library: library,
            })
        }
    }

    fn sample(&self) -> Option<Vec<GpuSnapshot>> {
        let mut initialized = self.initialized.lock().ok()?;
        // SAFETY: The symbols are from the retained NVML library, and all
        // pointers refer to writable values of the corresponding C types.
        if !*initialized {
            *initialized = unsafe { (self.init)() } == SUCCESS;
            if !*initialized {
                return None;
            }
        }
        let mut count = 0;
        let status = unsafe { (self.count)(&mut count) };
        if status == UNINITIALIZED {
            *initialized = false;
        }
        if status != SUCCESS {
            return None;
        }
        (0..count).map(|index| self.sample_device(index)).collect()
    }

    fn sample_device(&self, index: c_uint) -> Option<GpuSnapshot> {
        let mut device = ptr::null_mut();
        // SAFETY: Each output points to an initialized, writable C value.
        // All metric calls use a device returned by the initialized library.
        unsafe {
            if (self.handle)(index, &mut device) != SUCCESS || device.is_null() {
                return None;
            }
            let id = read_text(self.uuid, device)?;
            let name = read_text(self.name, device)?;
            let utilization = read_metric(|out| (self.utilization)(device, out))?;
            let memory = if let Some(query) = self.memory_v2 {
                // Derive application VRAM usage independently of the driver's used field.
                read_metric(|out| query(device, out))?.map(|m| {
                    let used = m
                        .total
                        .checked_sub(m.free)
                        .and_then(|v| v.checked_sub(m.reserved));
                    (used, m.total)
                })
            } else {
                read_metric(|out| (self.memory)(device, out))?.map(|m| (Some(m.used), m.total))
            };
            let temperature = read_metric(|out| (self.temperature)(device, TEMPERATURE_GPU, out))?;
            let (used, total) = memory
                .filter(|&(_, total)| total > 0 && total != c_ulonglong::MAX)
                .map_or((None, None), |(used, total)| (used, Some(total)));
            Some(GpuSnapshot {
                id,
                name,
                utilization_percent: utilization.filter(|v| v.gpu <= 100).map(|v| v.gpu.into()),
                memory_used_bytes: used
                    .zip(total)
                    .filter(|(used, total)| used <= total)
                    .map(|(used, _)| used as f64),
                memory_total_bytes: total.map(|total| total as f64),
                temperature_celsius: temperature.filter(|v| *v != c_uint::MAX).map(f64::from),
            })
        }
    }
}

unsafe fn read_text(read: DeviceText, device: Device) -> Option<String> {
    let mut bytes = [0u8; 128];
    // SAFETY: The caller supplies a valid NVML device; the writable buffer
    // has the given length and is valid throughout the call.
    if unsafe { read(device, bytes.as_mut_ptr().cast(), bytes.len() as c_uint) } != SUCCESS {
        return None;
    }
    let text = CStr::from_bytes_until_nul(&bytes).ok()?.to_string_lossy();
    let text = text.trim();
    (!text.is_empty()).then(|| text.to_owned())
}

// Unsupported metrics stay unavailable. Other driver errors invalidate the sample.
fn read_metric<T: Default>(read: impl FnOnce(*mut T) -> c_int) -> Option<Option<T>> {
    let mut value = T::default();
    match read(&mut value) {
        SUCCESS => Some(Some(value)),
        NOT_SUPPORTED | NO_PERMISSION => Some(None),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_sensor_and_driver_failure_are_distinct() {
        assert_eq!(read_metric::<c_uint>(|_| NOT_SUPPORTED), Some(None));
        assert_eq!(read_metric::<c_uint>(|_| NO_PERMISSION), Some(None));
        assert_eq!(read_metric::<c_uint>(|_| UNINITIALIZED), None);
    }
}
