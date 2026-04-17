/*
 * VanguardSpoofer.h - Header file for Professional Kernel HWID Spoofer
 * 
 * Defines structures, IOCTL codes, and function prototypes
 * 
 * Version: 2.0.0-Professional
 */

#ifndef _VANGUARD_SPOOFER_H_
#define _VANGUARD_SPOOFER_H_

#include <ntddk.h>
#include <ntdddisk.h>
#include <ntddscsi.h>
#include <ntddstor.h>

#ifdef __cplusplus
extern "C" {
#endif

//
// IOCTL Codes for User-Mode Communication
//
#define VANGUARD_SPOOFER_DEVICE 0x8000

#define IOCTL_SET_SPOOF_VALUES    CTL_CODE(VANGUARD_SPOOFER_DEVICE, 0x800, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_GET_STATUS          CTL_CODE(VANGUARD_SPOOFER_DEVICE, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_DISABLE_SPOOFING    CTL_CODE(VANGUARD_SPOOFER_DEVICE, 0x802, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_ENABLE_SPOOFING     CTL_CODE(VANGUARD_SPOOFER_DEVICE, 0x803, METHOD_BUFFERED, FILE_ANY_ACCESS)

//
// Structures
//

typedef struct _SPOOF_CONFIG {
    WCHAR BaseboardSerial[64];
    WCHAR DiskSerial[64];
    WCHAR SystemUUID[64];
    WCHAR ChassisSerial[64];
    WCHAR CPUID[64];
    WCHAR GPUSerial[64];
    WCHAR MACAddress[32];
    BOOLEAN SpoofAll;
} SPOOF_CONFIG, *PSPOOF_CONFIG;

typedef struct _SPOOF_STATUS {
    BOOLEAN Active;
    BOOLEAN WmiHooked;
    BOOLEAN DiskHooked;
    BOOLEAN SmbiosHooked;
    BOOLEAN NicHooked;
    ULONG SpoofCount;
} SPOOF_STATUS, *PSPOOF_STATUS;

//
// SMBIOS Structures
//
#pragma pack(push, 1)

typedef struct _SMBIOS_ENTRY_POINT {
    CHAR AnchorString[4];           // "_SM_"
    UCHAR Checksum;
    UCHAR Length;
    UCHAR MajorVersion;
    UCHAR MinorVersion;
    USHORT MaxStructureSize;
    UCHAR Revision;
    UCHAR Reserved[5];
    CHAR IntermediateAnchor[5];     // "_DMI_"
    UCHAR IntermediateChecksum;
    USHORT TableLength;
    ULONG TableAddress;
    USHORT StructureCount;
    UCHAR BcdRevision;
} SMBIOS_ENTRY_POINT, *PSMBIOS_ENTRY_POINT;

typedef struct _SMBIOS_STRUCTURE {
    UCHAR Type;
    UCHAR Length;
    USHORT Handle;
    // Followed by formatted data, then strings
} SMBIOS_STRUCTURE, *PSMBIOS_STRUCTURE;

// SMBIOS Type 1 - System Information
typedef struct _SMBIOS_TYPE1 {
    SMBIOS_STRUCTURE Header;
    UCHAR Manufacturer;
    UCHAR ProductName;
    UCHAR Version;
    UCHAR SerialNumber;
    GUID UUID;
    UCHAR WakeUpType;
    UCHAR SKUNumber;
    UCHAR Family;
    CHAR Strings[1];  // Variable length
} SMBIOS_TYPE1, *PSMBIOS_TYPE1;

// SMBIOS Type 2 - Baseboard Information
typedef struct _SMBIOS_TYPE2 {
    SMBIOS_STRUCTURE Header;
    UCHAR Manufacturer;
    UCHAR Product;
    UCHAR Version;
    UCHAR SerialNumber;
    UCHAR AssetTag;
    UCHAR FeatureFlags;
    UCHAR LocationInChassis;
    USHORT ChassisHandle;
    UCHAR BoardType;
    UCHAR ObjectHandles;
    CHAR Strings[1];
} SMBIOS_TYPE2, *PSMBIOS_TYPE2;

// SMBIOS Type 3 - Chassis Information
typedef struct _SMBIOS_TYPE3 {
    SMBIOS_STRUCTURE Header;
    UCHAR Manufacturer;
    UCHAR Type;
    UCHAR Version;
    UCHAR SerialNumber;
    UCHAR AssetTag;
    UCHAR BootUpState;
    UCHAR PowerSupplyState;
    UCHAR ThermalState;
    UCHAR SecurityStatus;
    ULONG OEMDefined;
    UCHAR Height;
    UCHAR NumberOfPowerCords;
    UCHAR ContainedElementCount;
    UCHAR ContainedElementRecordLength;
    CHAR Strings[1];
} SMBIOS_TYPE3, *PSMBIOS_TYPE3;

// SMBIOS Type 11 - OEM Strings
typedef struct _SMBIOS_TYPE11 {
    SMBIOS_STRUCTURE Header;
    UCHAR Count;
    CHAR Strings[1];
} SMBIOS_TYPE11, *PSMBIOS_TYPE11;

#pragma pack(pop)

//
// Storage Property Structures
//
#ifndef _WINDOWS_
typedef enum _STORAGE_PROPERTY_ID {
    StorageDeviceProperty = 0,
    StorageAdapterProperty,
    StorageDeviceIdProperty,
    StorageDeviceUniqueIdProperty,
    StorageDeviceWriteCacheProperty,
    StorageMiniportProperty,
    StorageAccessAlignmentProperty,
    StorageDeviceSeekPenaltyProperty,
    StorageDeviceTrimProperty,
    StorageDeviceWriteAggregationProperty,
    StorageDeviceDeviceTelemetryProperty,
    StorageDeviceLBProvisioningProperty,
    StorageDevicePowerProperty,
    StorageDeviceCopyOffloadProperty,
    StorageDeviceResiliencyProperty,
    StorageDeviceMediumTypeProperty,
    StorageDeviceIoCapabilityProperty,
    StorageDeviceProtocolSpecificProperty,
    StorageDeviceTemperatureProperty,
    StorageDevicePhysicalTopologyProperty,
    StorageDeviceAttributesProperty,
    StorageDeviceManagementStatus,
    StorageDeviceIoSpeedsProperty,
    StorageDeviceCapabilityProperty,
    StorageDeviceRuntimeSpareMetadataProperty,
    StorageDevicePortProperty,
    StorageDeviceRpmProperty,
    StorageDeviceLastProperty
} STORAGE_PROPERTY_ID, *PSTORAGE_PROPERTY_ID;

typedef enum _STORAGE_QUERY_TYPE {
    PropertyStandardQuery = 0,
    PropertyExistsQuery,
    PropertyMaskQuery,
    PropertyQueryMaxDefined
} STORAGE_QUERY_TYPE, *PSTORAGE_QUERY_TYPE;

typedef struct _STORAGE_PROPERTY_QUERY {
    STORAGE_PROPERTY_ID PropertyId;
    STORAGE_QUERY_TYPE QueryType;
    UCHAR AdditionalParameters[1];
} STORAGE_PROPERTY_QUERY, *PSTORAGE_PROPERTY_QUERY;

typedef struct _STORAGE_DEVICE_DESCRIPTOR {
    ULONG Version;
    ULONG Size;
    UCHAR DeviceType;
    UCHAR DeviceTypeModifier;
    BOOLEAN RemovableMedia;
    BOOLEAN CommandQueueing;
    ULONG VendorIdOffset;
    ULONG ProductIdOffset;
    ULONG ProductRevisionOffset;
    ULONG SerialNumberOffset;
    STORAGE_BUS_TYPE BusType;
    ULONG RawPropertiesLength;
    UCHAR RawDeviceProperties[1];
} STORAGE_DEVICE_DESCRIPTOR, *PSTORAGE_DEVICE_DESCRIPTOR;
#endif

//
// IOCTL Definitions
//
#ifndef IOCTL_STORAGE_QUERY_PROPERTY
#define IOCTL_STORAGE_QUERY_PROPERTY CTL_CODE(IOCTL_STORAGE_BASE, 0x0500, METHOD_BUFFERED, FILE_ANY_ACCESS)
#endif

//
// Function Pointer Types for Hooks
//
typedef NTSTATUS (*pWmiQueryAllData_t)(
    PVOID Wnode,
    ULONG BufferSize,
    PVOID Buffer,
    PULONG RequiredSize,
    BOOLEAN UsePerfClock
);

typedef NTSTATUS (*pIoctlDiskQueryProperty_t)(
    PDEVICE_OBJECT DeviceObject,
    PIRP Irp
);

typedef NTSTATUS (*pNtQuerySystemInformation_t)(
    SYSTEM_INFORMATION_CLASS SystemInformationClass,
    PVOID SystemInformation,
    ULONG SystemInformationLength,
    PULONG ReturnLength
);

//
// WMI GUIDs (Anti-cheat queries these)
//
// {8F680D7F-2D57-4A8C-953E-80CC2C0F2A6E} - Win32_BaseBoard
// {25B70FD9-9058-4A22-8C99-25A9C59A952C} - Win32_ComputerSystemProduct
// {C7BF4C21-3A9D-4EAA-A0A3-1545C6E3C07A} - Win32_BIOS
// {FEF8C7B0-3F71-4A8C-8C2C-3C2E5E2B6B7A} - Win32_PhysicalMedia

DEFINE_GUID(GUID_WMI_BASEBOARD, 
    0x8F680D7F, 0x2D57, 0x4A8C, 0x95, 0x3E, 0x80, 0xCC, 0x2C, 0x0F, 0x2A, 0x6E);

DEFINE_GUID(GUID_WMI_COMPUTER_PRODUCT,
    0x25B70FD9, 0x9058, 0x4A22, 0x8C, 0x99, 0x25, 0xA9, 0xC5, 0x9A, 0x95, 0x2C);

//
// Driver Function Prototypes
//
NTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath);
VOID DriverUnload(PDRIVER_OBJECT DriverObject);

NTSTATUS VanguardSpooferCreateClose(PDEVICE_OBJECT DeviceObject, PIRP Irp);
NTSTATUS VanguardSpooferIoctl(PDEVICE_OBJECT DeviceObject, PIRP Irp);
NTSTATUS CreateDevice(PDRIVER_OBJECT DriverObject);

//
// Hook Installation
//
NTSTATUS InstallWmiHooks(void);
NTSTATUS InstallDiskHooks(void);
NTSTATUS InstallSmbiosHooks(void);
NTSTATUS InstallNicHooks(void);

//
// Hook Handlers
//
NTSTATUS HookedWmiQueryAllData(PVOID Wnode, ULONG BufferSize, PVOID Buffer, PULONG RequiredSize, BOOLEAN UsePerfClock);
NTSTATUS HookedIoctlDiskQuery(PDEVICE_OBJECT DeviceObject, PIRP Irp);
NTSTATUS HookedNtQuerySystemInfo(SYSTEM_INFORMATION_CLASS SystemInformationClass, PVOID SystemInformation, ULONG SystemInformationLength, PULONG ReturnLength);

//
// Spoofing Functions
//
NTSTATUS SpoofSMBIOSData(void);
NTSTATUS SpoofDiskSerials(void);
NTSTATUS SpoofNetworkMACs(void);
NTSTATUS SpoofCPUID(void);

//
// Utility Functions
//
PVOID FindWmiProviderFunction(const char* FunctionName);
PVOID FindDiskDriverDispatch(void);
NTSTATUS ReplaceUnicodeString(PUNICODE_STRING Target, PUNICODE_STRING Source);
BOOLEAN IsTargetWmiGuid(LPCGUID Guid);
BOOLEAN IsTargetDiskIoctl(ULONG IoctlCode);

//
// Memory Hooking (Simplified)
//
NTSTATUS InstallInlineHook(PVOID TargetFunction, PVOID HookFunction, PVOID* OriginalFunction);
NTSTATUS RemoveInlineHook(PVOID OriginalFunction);

//
// Global Variables (extern)
//
extern PDRIVER_OBJECT g_DriverObject;
extern UNICODE_STRING g_SpoofedBaseboardSerial;
extern UNICODE_STRING g_SpoofedDiskSerial;
extern UNICODE_STRING g_SpoofedSystemUUID;

extern pWmiQueryAllData_t g_OriginalWmiQueryAllData;
extern pIoctlDiskQueryProperty_t g_OriginalIoctlDiskQuery;
extern pNtQuerySystemInformation_t g_OriginalNtQuerySystemInfo;

#ifdef __cplusplus
}
#endif

#endif // _VANGUARD_SPOOFER_H_
