/*
    PlutoKernel.sys - WMI Filter Driver for HWID Spoofing
    
    Target: Windows 10/11 x64
    Purpose: Hook WMI queries to return spoofed hardware data
    
    COMPILATION (requires WDK):
    1. Install Windows Driver Kit
    2. Create KMDF project in Visual Studio
    3. Add this file
    4. Build: x64 Release
    5. Sign or use Test Mode
    
    LOADING:
    sc create PlutoKernel type= kernel binPath= C:\Path\To\PlutoKernel.sys
    sc start PlutoKernel
    
    Or use kdmapper for unsigned:
    kdmapper.exe PlutoKernel.sys
*/

#include <ntddk.h>
#include <wdf.h>
#include <wdm.h>

#define DRIVER_TAG 'olpT'  // "Tplo" reversed

// Spoofed values stored in registry
typedef struct _SPOOF_CONFIG {
    WCHAR MachineGUID[40];
    WCHAR SMBIOS_UUID[40];
    WCHAR DiskSerial[100];
    WCHAR MACAddress[20];
    BOOLEAN Enabled;
} SPOOF_CONFIG, *PSPOOF_CONFIG;

SPOOF_CONFIG g_Config = { 0 };

// Original WMI handlers (saved for pass-through)
PDRIVER_OBJECT g_WmiDriverObject = NULL;
PDEVICE_OBJECT g_WmiDeviceObject = NULL;

// Function prototypes
DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD PlutoKernelDeviceAdd;
EVT_WDF_DEVICE_D0_ENTRY PlutoKernelD0Entry;
EVT_WDF_DEVICE_D0_EXIT PlutoKernelD0Exit;
EVT_WDF_IO_QUEUE_IO_DEVICE_CONTROL PlutoKernelIoDeviceControl;

NTSTATUS ReadSpoofConfigFromRegistry(void) {
    UNICODE_STRING valueName;
    UNICODE_STRING registryPath;
    RTL_QUERY_REGISTRY_TABLE queryTable[5];
    
    RtlInitUnicodeString(&registryPath, L"\\Registry\\Machine\\SOFTWARE\\PlutoKernel");
    
    RtlZeroMemory(queryTable, sizeof(queryTable));
    
    // MachineGUID
    RtlInitUnicodeString(&valueName, L"MachineGUID");
    queryTable[0].Flags = RTL_QUERY_REGISTRY_DIRECT;
    queryTable[0].Name = &valueName;
    queryTable[0].EntryContext = g_Config.MachineGUID;
    queryTable[0].DefaultType = REG_SZ;
    queryTable[0].DefaultData = L"00000000-0000-0000-0000-000000000000";
    queryTable[0].DefaultLength = 74;
    
    // SMBIOS UUID
    RtlInitUnicodeString(&valueName, L"SMBIOS_UUID");
    queryTable[1].Flags = RTL_QUERY_REGISTRY_DIRECT;
    queryTable[1].Name = &valueName;
    queryTable[1].EntryContext = g_Config.SMBIOS_UUID;
    queryTable[1].DefaultType = REG_SZ;
    queryTable[1].DefaultData = L"00000000-0000-0000-0000-000000000000";
    queryTable[1].DefaultLength = 74;
    
    // Enabled flag
    RtlInitUnicodeString(&valueName, L"Enabled");
    queryTable[2].Flags = RTL_QUERY_REGISTRY_DIRECT | RTL_QUERY_REGISTRY_TYPECHECK;
    queryTable[2].Name = &valueName;
    queryTable[2].EntryContext = &g_Config.Enabled;
    queryTable[2].DefaultType = REG_DWORD;
    queryTable[2].DefaultData = (PVOID)0;
    queryTable[2].DefaultLength = sizeof(DWORD);
    
    NTSTATUS status = RtlQueryRegistryValues(
        RTL_REGISTRY_ABSOLUTE,
        registryPath.Buffer,
        queryTable,
        NULL,
        NULL
    );
    
    return status;
}

// Hook for IRP_MJ_DEVICE_CONTROL
NTSTATUS HookDeviceControl(PDEVICE_OBJECT DeviceObject, PIRP Irp) {
    PIO_STACK_LOCATION irpStack;
    ULONG ioctl;
    PVOID inputBuffer;
    PVOID outputBuffer;
    ULONG inputBufferLength;
    ULONG outputBufferLength;
    
    irpStack = IoGetCurrentIrpStackLocation(Irp);
    ioctl = irpStack->Parameters.DeviceIoControl.IoControlCode;
    inputBuffer = Irp->AssociatedIrp.SystemBuffer;
    outputBuffer = Irp->AssociatedIrp.SystemBuffer;
    inputBufferLength = irpStack->Parameters.DeviceIoControl.InputBufferLength;
    outputBufferLength = irpStack->Parameters.DeviceIoControl.OutputBufferLength;
    
    // Check if this is a WMI query
    if (ioctl == IOCTL_WMI_QUERY_ALL_DATA || 
        ioctl == IOCTL_WMI_QUERY_SINGLE_INSTANCE ||
        ioctl == IOCTL_WMI_EXECUTE_METHOD) {
        
        // Log the query (debug only)
        // KdPrint(("PlutoKernel: WMI Query intercepted\n"));
        
        // TODO: Parse WMI query and modify response
        // This requires parsing WNODE_HEADER and WMI data structures
        // For production, implement full WMI response modification
    }
    
    // Pass through to original driver
    // Note: In production, you'd modify the response here before completing
    
    return IoCallDriver(DeviceObject, Irp);
}

// SSDT Hook approach (classic but detectable)
// Modern approach: Filter driver on WMI stack

NTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath) {
    NTSTATUS status;
    WDF_DRIVER_CONFIG config;
    WDFDRIVER driver;
    
    UNREFERENCED_PARAMETER(RegistryPath);
    
    KdPrint(("PlutoKernel: DriverEntry called\n"));
    
    // Read spoof configuration from registry
    status = ReadSpoofConfigFromRegistry();
    if (!NT_SUCCESS(status)) {
        KdPrint(("PlutoKernel: Failed to read config: 0x%08X\n", status));
        // Continue with defaults
    }
    
    if (!g_Config.Enabled) {
        KdPrint(("PlutoKernel: Spoofing disabled in registry\n"));
        return STATUS_SUCCESS;  // Load but do nothing
    }
    
    KdPrint(("PlutoKernel: Spoofing enabled\n"));
    KdPrint(("PlutoKernel: MachineGUID: %ws\n", g_Config.MachineGUID));
    
    // Initialize WDF driver
    WDF_DRIVER_CONFIG_INIT(&config, PlutoKernelDeviceAdd);
    
    status = WdfDriverCreate(
        DriverObject,
        RegistryPath,
        WDF_NO_OBJECT_ATTRIBUTES,
        &config,
        &driver
    );
    
    if (!NT_SUCCESS(status)) {
        KdPrint(("PlutoKernel: WdfDriverCreate failed: 0x%08X\n", status));
        return status;
    }
    
    return STATUS_SUCCESS;
}

NTSTATUS PlutoKernelDeviceAdd(WDFDRIVER Driver, PWDFDEVICE_INIT DeviceInit) {
    NTSTATUS status;
    WDFDEVICE device;
    WDF_IO_QUEUE_CONFIG queueConfig;
    WDFQUEUE queue;
    
    UNREFERENCED_PARAMETER(Driver);
    
    KdPrint(("PlutoKernel: DeviceAdd called\n"));
    
    status = WdfDeviceCreate(&DeviceInit, WDF_NO_OBJECT_ATTRIBUTES, &device);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    
    // Create default I/O queue
    WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(&queueConfig, WdfIoQueueDispatchParallel);
    queueConfig.EvtIoDeviceControl = PlutoKernelIoDeviceControl;
    
    status = WdfIoQueueCreate(device, &queueConfig, WDF_NO_OBJECT_ATTRIBUTES, &queue);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    
    // Register for WMI
    // Note: Full WMI registration requires additional setup
    
    return STATUS_SUCCESS;
}

NTSTATUS PlutoKernelD0Entry(WDFDEVICE Device, WDF_POWER_DEVICE_STATE PreviousState) {
    UNREFERENCED_PARAMETER(Device);
    UNREFERENCED_PARAMETER(PreviousState);
    
    KdPrint(("PlutoKernel: D0Entry\n"));
    return STATUS_SUCCESS;
}

NTSTATUS PlutoKernelD0Exit(WDFDEVICE Device, WDF_POWER_DEVICE_STATE TargetState) {
    UNREFERENCED_PARAMETER(Device);
    UNREFERENCED_PARAMETER(TargetState);
    
    KdPrint(("PlutoKernel: D0Exit\n"));
    return STATUS_SUCCESS;
}

VOID PlutoKernelIoDeviceControl(
    WDFQUEUE Queue,
    WDFREQUEST Request,
    size_t OutputBufferLength,
    size_t InputBufferLength,
    ULONG IoControlCode
) {
    UNREFERENCED_PARAMETER(Queue);
    UNREFERENCED_PARAMETER(OutputBufferLength);
    UNREFERENCED_PARAMETER(InputBufferLength);
    
    // Handle custom IOCTLs from user-mode
    switch (IoControlCode) {
        case 0x80002000:  // IOCTL_PLUTO_SET_SPOOF
            // Update spoof configuration
            WdfRequestComplete(Request, STATUS_SUCCESS);
            break;
            
        case 0x80002004:  // IOCTL_PLUTO_GET_STATUS
            // Return current spoof status
            WdfRequestComplete(Request, STATUS_SUCCESS);
            break;
            
        default:
            WdfRequestComplete(Request, STATUS_INVALID_DEVICE_REQUEST);
            break;
    }
}

/*
    ADVANCED: Mini-filter Registration (Recommended for production)
    
    Instead of SSDT hooks, register as a WMI mini-filter:
    
    1. Register with IoRegisterFsRegistrationChange
    2. Attach to WMI device stack
    3. Filter IRP_MJ_DEVICE_CONTROL
    4. Modify WMI responses
    
    This is more stable and less detectable than SSDT hooks.
*/

/*
    WMI QUERY MODIFICATION
    
    To modify WMI queries (Win32_ComputerSystemProduct, Win32_DiskDrive, etc.):
    
    1. Parse WNODE_HEADER from IRP
    2. Identify target class (Win32_ComputerSystemProduct for UUID)
    3. Modify WNODE_INSTANCE_NAMES or WNODE_SINGLE_INSTANCE
    4. Replace SerialNumber, UUID, etc. with spoofed values
    5. Complete IRP with modified data
    
    Structures:
    - WNODE_HEADER (wmistr.h)
    - WNODE_ALL_DATA
    - WNODE_SINGLE_INSTANCE
    - WNODE_METHOD_ITEM
*/
