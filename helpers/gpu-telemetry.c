#include <dlfcn.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>

#define NVML_SUCCESS 0
#define NVML_TEMPERATURE_GPU 0

typedef int nvmlReturn_t;
typedef struct nvmlDevice_st *nvmlDevice_t;

typedef struct {
  unsigned int gpu;
  unsigned int memory;
} nvmlUtilization_t;

typedef struct {
  unsigned long long total;
  unsigned long long free;
  unsigned long long used;
} nvmlMemory_t;

struct telemetry {
  double usage;
  double temperature;
  bool has_temperature;
  unsigned long long memory_used;
  unsigned long long memory_total;
  bool has_memory;
};

static void *load_symbol(void *library, const char *name) {
  dlerror();
  void *symbol = dlsym(library, name);
  return dlerror() == NULL ? symbol : NULL;
}

static int collect_nvidia(struct telemetry *telemetry) {
  void *library = dlopen("libnvidia-ml.so.1", RTLD_LAZY | RTLD_LOCAL);
  if (library == NULL)
    library = dlopen("libnvidia-ml.so", RTLD_LAZY | RTLD_LOCAL);
  if (library == NULL)
    return -1;

  nvmlReturn_t (*init)(void) = load_symbol(library, "nvmlInit_v2");
  if (init == NULL)
    init = load_symbol(library, "nvmlInit");
  nvmlReturn_t (*shutdown)(void) = load_symbol(library, "nvmlShutdown");
  nvmlReturn_t (*get_count)(unsigned int *) =
      load_symbol(library, "nvmlDeviceGetCount_v2");
  if (get_count == NULL)
    get_count = load_symbol(library, "nvmlDeviceGetCount");
  nvmlReturn_t (*get_device)(unsigned int, nvmlDevice_t *) =
      load_symbol(library, "nvmlDeviceGetHandleByIndex_v2");
  if (get_device == NULL)
    get_device = load_symbol(library, "nvmlDeviceGetHandleByIndex");
  nvmlReturn_t (*get_utilization)(nvmlDevice_t, nvmlUtilization_t *) =
      load_symbol(library, "nvmlDeviceGetUtilizationRates");
  nvmlReturn_t (*get_temperature)(nvmlDevice_t, unsigned int, unsigned int *) =
      load_symbol(library, "nvmlDeviceGetTemperature");
  nvmlReturn_t (*get_memory)(nvmlDevice_t, nvmlMemory_t *) =
      load_symbol(library, "nvmlDeviceGetMemoryInfo");

  if (init == NULL || shutdown == NULL || get_count == NULL ||
      get_device == NULL || get_utilization == NULL) {
    dlclose(library);
    return -1;
  }

  if (init() != NVML_SUCCESS) {
    dlclose(library);
    return -1;
  }

  unsigned int count = 0;
  bool found = false;
  nvmlDevice_t selected = NULL;
  if (get_count(&count) == NVML_SUCCESS) {
    for (unsigned int i = 0; i < count; i++) {
      nvmlDevice_t device = NULL;
      nvmlUtilization_t utilization = {0};
      if (get_device(i, &device) != NVML_SUCCESS || device == NULL)
        continue;
      if (get_utilization(device, &utilization) != NVML_SUCCESS ||
          utilization.gpu > 100)
        continue;
      if (!found || utilization.gpu > telemetry->usage) {
        telemetry->usage = utilization.gpu;
        selected = device;
        found = true;
      }
    }
  }

  if (found && get_temperature != NULL) {
    unsigned int temperature = 0;
    if (get_temperature(selected, NVML_TEMPERATURE_GPU, &temperature) ==
            NVML_SUCCESS &&
        temperature > 0 && temperature < 200) {
      telemetry->temperature = temperature;
      telemetry->has_temperature = true;
    }
  }

  if (found && get_memory != NULL) {
    nvmlMemory_t memory = {0};
    if (get_memory(selected, &memory) == NVML_SUCCESS && memory.total > 0) {
      telemetry->memory_used = memory.used;
      telemetry->memory_total = memory.total;
      telemetry->has_memory = true;
    }
  }

  shutdown();
  dlclose(library);
  return found ? 0 : -1;
}

int main(void) {
  struct telemetry telemetry = {
      .usage = -1.0,
      .temperature = -1.0,
      .has_temperature = false,
      .memory_used = 0,
      .memory_total = 0,
      .has_memory = false,
  };

  if (collect_nvidia(&telemetry) != 0) {
    fprintf(stderr, "no supported NVIDIA telemetry backend\n");
    return 3;
  }
  if (!isfinite(telemetry.usage) || telemetry.usage < 0.0 ||
      telemetry.usage > 100.0)
    return 4;

  printf("backend\tnvidia\n");
  printf("usage\t%.2f\n", telemetry.usage);
  if (telemetry.has_temperature)
    printf("temperature\t%.2f\n", telemetry.temperature);
  if (telemetry.has_memory) {
    printf("memory_used\t%llu\n", telemetry.memory_used);
    printf("memory_total\t%llu\n", telemetry.memory_total);
  }
  return 0;
}
