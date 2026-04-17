/*
    PlutoKernel.h - Header file for kernel driver
*/

#ifndef _PLUTOKERNEL_H_
#define _PLUTOKERNEL_H_

#include <ntddk.h>
#include <wdf.h>

// Custom IOCTLs for user-mode communication
#define PLUTO_KERNEL_DEVICE_TYPE 0x8000

#define IOCTL_PLUTO_SET_SPOOF    CTL_CODE(PLUTO_KERNEL_DEVICE_TYPE, 0x800, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_PLUTO_GET_STATUS   CTL_CODE(PLUTO_KERNEL_DEVICE_TYPE, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_PLUTO_ENABLE       CTL_CODE(PLUTO_KERNEL_DEVICE_TYPE, 0x802, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_PLUTO_DISABLE      CTL_CODE(PLUTO_KERNEL_DEVICE_TYPE, 0x803, METHOD_BUFFERED, FILE_ANY_ACCESS)

// Spoof configuration structure (shared with user-mode)
typedef struct _PLUTO_SPOOF_CONFIG {
    BOOLEAN Enabled;
    WCHAR MachineGUID[40];
    WCHAR SMBIOS_UUID[40];
    WCHAR DiskSerial0[100];
    WCHAR DiskSerial1[100];
    WCHAR MACAddress0[20];
    WCHAR MACAddress1[20];
} PLUTO_SPOOF_CONFIG, *PPLUTO_SPOOF_CONFIG;

// WMI target classes to spoof
typedef enum _PLUTO_WMI_CLASS {
    WmiClassComputerSystemProduct,   // UUID
    WmiClassBaseBoard,               // Motherboard serial
    WmiClassBIOS,                    // BIOS serial
    WmiClassDiskDrive,               // Disk serial
    WmiClassPhysicalMedia,           // Physical disk
    WmiClassNetworkAdapter,          // MAC address
    WmiClassMax
} PLUTO_WMI_CLASS;

// Function prototypes
DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD PlutoKernelDeviceAdd;
EVT_WDF_DEVICE_D0_ENTRY PlutoKernelD0Entry;
EVT_WDF_DEVICE_D0_EXIT PlutoKernelD0Exit;
EVT_WDF_IO_QUEUE_IO_DEVICE_CONTROL PlutoKernelIoDeviceControl;

// WMI filter functions
NTSTATUS RegisterWmiFilter(WDFDEVICE Device);
VOID UnregisterWmiFilter(WDFDEVICE Device);
NTSTATUS ModifyWmiResponse(PWNODE_HEADER WnodeHeader, PLUTO_WMI_CLASS Class);

// Utility functions
NTSTATUS ReadRegistryConfig(PUNICODE_STRING RegistryPath, PPLUTO_SPOOF_CONFIG Config);
NTSTATUS WriteRegistryConfig(PUNICODE_STRING RegistryPath, PPLUTO_SPOOF_CONFIG Config);

#endif // _PLUTOKERNEL_H_
