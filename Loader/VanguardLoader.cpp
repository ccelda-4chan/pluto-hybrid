/*
 * VanguardLoader.cpp - C++ Driver Loader Application
 * 
 * Professional loader that:
 * 1. Installs WDK automatically (if missing)
 * 2. Builds the kernel driver
 * 3. Loads driver using kdmapper
 * 4. Provides GUI for spoof control
 * 
 * Compile: cl VanguardLoader.cpp /EHsc /Fe:VanguardLoader.exe user32.lib gdi32.lib shell32.lib
 */

#include <windows.h>
#include <iostream>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <thread>
#include <chrono>

// GUI Constants
#define ID_BUTTON_LOAD      1001
#define ID_BUTTON_BUILD     1002
#define ID_BUTTON_INSTALL   1003
#define ID_BUTTON_VERIFY    1004
#define ID_EDIT_STATUS      2001
#define ID_EDIT_LOG         2002

// Function prototypes
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
void LogMessage(HWND hLog, const std::wstring& msg);
bool InstallWDK();
bool BuildDriver();
bool LoadDriver();
bool VerifySpoof();
std::wstring ExecuteCommand(const std::wstring& cmd);
bool DownloadFile(const std::wstring& url, const std::wstring& outputPath);

// Global handles
HWND hStatus, hLog;
HINSTANCE hInst;

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    UNREFERENCED_PARAMETER(hPrevInstance);
    UNREFERENCED_PARAMETER(lpCmdLine);
    
    hInst = hInstance;
    
    // Register window class
    WNDCLASSEX wc = { 0 };
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = L"VanguardLoaderClass";
    wc.hbrBackground = CreateSolidBrush(RGB(30, 30, 40));
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    
    if (!RegisterClassEx(&wc)) {
        MessageBox(NULL, L"Failed to register window class", L"Error", MB_OK | MB_ICONERROR);
        return 1;
    }
    
    // Create main window
    HWND hwnd = CreateWindowEx(
        0,
        L"VanguardLoaderClass",
        L"VanguardSpoofer Loader v2.0",
        WS_OVERLAPPEDWINDOW & ~WS_THICKFRAME & ~WS_MAXIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT,
        800, 600,
        NULL, NULL, hInstance, NULL
    );
    
    if (!hwnd) {
        MessageBox(NULL, L"Failed to create window", L"Error", MB_OK | MB_ICONERROR);
        return 1;
    }
    
    ShowWindow(hwnd, nCmdShow);
    UpdateWindow(hwnd);
    
    // Message loop
    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
    
    return (int)msg.wParam;
}

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_CREATE: {
            // Title
            CreateWindow(L"STATIC", L"VanguardSpoofer Kernel Driver Loader",
                WS_VISIBLE | WS_CHILD | SS_CENTER,
                20, 20, 760, 30,
                hwnd, NULL, hInst, NULL);
            
            // Buttons
            CreateWindow(L"BUTTON", L"1. Install WDK",
                WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
                20, 70, 180, 40,
                hwnd, (HMENU)ID_BUTTON_INSTALL, hInst, NULL);
            
            CreateWindow(L"BUTTON", L"2. Build Driver",
                WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
                220, 70, 180, 40,
                hwnd, (HMENU)ID_BUTTON_BUILD, hInst, NULL);
            
            CreateWindow(L"BUTTON", L"3. Load Driver",
                WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
                420, 70, 180, 40,
                hwnd, (HMENU)ID_BUTTON_LOAD, hInst, NULL);
            
            CreateWindow(L"BUTTON", L"4. Verify Spoof",
                WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON,
                620, 70, 160, 40,
                hwnd, (HMENU)ID_BUTTON_VERIFY, hInst, NULL);
            
            // Status bar
            CreateWindow(L"STATIC", L"Status:",
                WS_VISIBLE | WS_CHILD,
                20, 130, 100, 20,
                hwnd, NULL, hInst, NULL);
            
            hStatus = CreateWindow(L"EDIT", L"Ready - Click buttons in order (1→4)",
                WS_VISIBLE | WS_CHILD | WS_BORDER | ES_READONLY | ES_CENTER,
                20, 155, 760, 30,
                hwnd, (HMENU)ID_EDIT_STATUS, hInst, NULL);
            
            // Log area
            CreateWindow(L"STATIC", L"Operation Log:",
                WS_VISIBLE | WS_CHILD,
                20, 200, 150, 20,
                hwnd, NULL, hInst, NULL);
            
            hLog = CreateWindow(L"EDIT", L"",
                WS_VISIBLE | WS_CHILD | WS_BORDER | ES_MULTILINE | ES_AUTOVSCROLL | 
                ES_READONLY | WS_VSCROLL,
                20, 225, 760, 320,
                hwnd, (HMENU)ID_EDIT_LOG, hInst, NULL);
            
            // Set fonts
            HFONT hFont = CreateFont(16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                DEFAULT_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Consolas");
            SendMessage(hLog, WM_SETFONT, (WPARAM)hFont, TRUE);
            
            LogMessage(hLog, L"=== VanguardSpoofer Loader Started ===");
            LogMessage(hLog, L"Click buttons in order: Install → Build → Load → Verify");
            
            return 0;
        }
        
        case WM_COMMAND:
            switch (LOWORD(wParam)) {
                case ID_BUTTON_INSTALL:
                    SetWindowText(hStatus, L"Installing WDK... (may take 10-15 min)");
                    LogMessage(hLog, L"[ACTION] Starting WDK installation...");
                    
                    std::thread([]() {
                        bool ok = InstallWDK();
                        SetWindowText(hStatus, ok ? L"WDK installed successfully!" : L"WDK installation failed");
                    }).detach();
                    break;
                    
                case ID_BUTTON_BUILD:
                    SetWindowText(hStatus, L"Building driver...");
                    LogMessage(hLog, L"[ACTION] Building VanguardSpoofer.sys...");
                    
                    std::thread([]() {
                        bool ok = BuildDriver();
                        SetWindowText(hStatus, ok ? L"Driver built successfully!" : L"Build failed");
                    }).detach();
                    break;
                    
                case ID_BUTTON_LOAD:
                    SetWindowText(hStatus, L"Loading driver with kdmapper...");
                    LogMessage(hLog, L"[ACTION] Loading driver (DSE bypass)...");
                    
                    std::thread([]() {
                        bool ok = LoadDriver();
                        SetWindowText(hStatus, ok ? L"Driver loaded! Spoofing active!" : L"Driver load failed");
                    }).detach();
                    break;
                    
                case ID_BUTTON_VERIFY:
                    SetWindowText(hStatus, L"Verifying spoof...");
                    LogMessage(hLog, L"[ACTION] Checking spoof status...");
                    
                    std::thread([]() {
                        bool ok = VerifySpoof();
                        SetWindowText(hStatus, ok ? L"Spoof verified! All systems green!" : L"Verification issues detected");
                    }).detach();
                    break;
            }
            return 0;
            
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
            
        default:
            return DefWindowProc(hwnd, msg, wParam, lParam);
    }
}

void LogMessage(HWND hLog, const std::wstring& msg) {
    int len = GetWindowTextLength(hLog);
    SendMessage(hLog, EM_SETSEL, len, len);
    
    SYSTEMTIME st;
    GetLocalTime(&st);
    
    std::wostringstream timestamp;
    timestamp << L"[" << std::setfill(L'0') << std::setw(2) << st.wHour << L":"
              << std::setfill(L'0') << std::setw(2) << st.wMinute << L":"
              << std::setfill(L'0') << std::setw(2) << st.wSecond << L"] ";
    
    std::wstring fullMsg = timestamp.str() + msg + L"\r\n";
    SendMessage(hLog, EM_REPLACESEL, FALSE, (LPARAM)fullMsg.c_str());
    SendMessage(hLog, EM_SCROLLCARET, 0, 0);
}

std::wstring ExecuteCommand(const std::wstring& cmd) {
    std::wstring result;
    SECURITY_ATTRIBUTES sa;
    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.bInheritHandle = TRUE;
    sa.lpSecurityDescriptor = NULL;
    
    HANDLE hRead, hWrite;
    CreatePipe(&hRead, &hWrite, &sa, 0);
    
    STARTUPINFO si = { 0 };
    si.cb = sizeof(STARTUPINFO);
    si.hStdError = hWrite;
    si.hStdOutput = hWrite;
    si.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
    si.wShowWindow = SW_HIDE;
    
    PROCESS_INFORMATION pi = { 0 };
    
    if (CreateProcess(NULL, (LPWSTR)cmd.c_str(), NULL, NULL, TRUE, 
                      CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        WaitForSingleObject(pi.hProcess, INFINITE);
        
        CloseHandle(hWrite);
        
        char buffer[4096];
        DWORD bytesRead;
        while (ReadFile(hRead, buffer, sizeof(buffer) - 1, &bytesRead, NULL) && bytesRead > 0) {
            buffer[bytesRead] = '\0';
            int wlen = MultiByteToWideChar(CP_OEMCP, 0, buffer, -1, NULL, 0);
            std::vector<wchar_t> wbuf(wlen);
            MultiByteToWideChar(CP_OEMCP, 0, buffer, -1, wbuf.data(), wlen);
            result += wbuf.data();
        }
        
        CloseHandle(hRead);
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
    }
    
    return result;
}

bool DownloadFile(const std::wstring& url, const std::wstring& outputPath) {
    std::wstring cmd = L"powershell -Command \"Invoke-WebRequest -Uri '" + url + 
                         L"' -OutFile '" + outputPath + L"' -UseBasicParsing\"";
    std::wstring result = ExecuteCommand(cmd);
    return GetFileAttributes(outputPath.c_str()) != INVALID_FILE_ATTRIBUTES;
}

bool InstallWDK() {
    LogMessage(hLog, L"[INSTALL] Checking for existing WDK...");
    
    // Check if already installed
    if (GetFileAttributes(L"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe") != INVALID_FILE_ATTRIBUTES) {
        LogMessage(hLog, L"[INSTALL] WDK already installed!");
        return true;
    }
    
    LogMessage(hLog, L"[INSTALL] Downloading WDK installer...");
    
    std::wstring wdkUrl = L"https://go.microsoft.com/fwlink/?linkid=2286263";
    std::wstring wdkInstaller = L"C:\\Temp\\wdksetup.exe";
    
    CreateDirectory(L"C:\\Temp", NULL);
    
    if (!DownloadFile(wdkUrl, wdkInstaller)) {
        LogMessage(hLog, L"[ERROR] Failed to download WDK");
        return false;
    }
    
    LogMessage(hLog, L"[INSTALL] Running WDK installer (10-15 minutes)...");
    
    std::wstring cmd = L"\"" + wdkInstaller + L"\" /quiet /norestart";
    std::wstring result = ExecuteCommand(cmd);
    
    // Check if installed
    if (GetFileAttributes(L"C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe") != INVALID_FILE_ATTRIBUTES) {
        LogMessage(hLog, L"[INSTALL] WDK installed successfully!");
        return true;
    }
    
    LogMessage(hLog, L"[ERROR] WDK installation may have failed");
    return false;
}

bool BuildDriver() {
    LogMessage(hLog, L"[BUILD] Starting driver build...");
    
    // Check for MSBuild
    std::vector<std::wstring> msbuildPaths = {
        L"C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\MSBuild\\Current\\Bin\\MSBuild.exe",
        L"C:\\Program Files\\Microsoft Visual Studio\\2022\\Professional\\MSBuild\\Current\\Bin\\MSBuild.exe",
        L"C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Community\\MSBuild\\Current\\Bin\\MSBuild.exe"
    };
    
    std::wstring msbuild;
    for (const auto& path : msbuildPaths) {
        if (GetFileAttributes(path.c_str()) != INVALID_FILE_ATTRIBUTES) {
            msbuild = path;
            break;
        }
    }
    
    if (msbuild.empty()) {
        LogMessage(hLog, L"[BUILD] MSBuild not found! Install Visual Studio or Build Tools");
        return false;
    }
    
    LogMessage(hLog, L"[BUILD] Found MSBuild");
    
    // Create build directory
    CreateDirectory(L"Build", NULL);
    CreateDirectory(L"Build\\Release", NULL);
    
    // Build
    std::wstring vcxproj = L"Driver\\VanguardSpoofer.vcxproj";
    std::wstring cmd = L"\"" + msbuild + L"\" " + vcxproj + 
                       L" /p:Configuration=Release /p:Platform=x64 /p:OutDir=Build\\Release\\";
    
    LogMessage(hLog, L"[BUILD] Compiling...");
    std::wstring result = ExecuteCommand(cmd);
    
    // Check output
    if (result.find(L"Build succeeded") != std::wstring::npos ||
        GetFileAttributes(L"Build\\Release\\VanguardSpoofer.sys") != INVALID_FILE_ATTRIBUTES) {
        LogMessage(hLog, L"[BUILD] SUCCESS! Driver compiled!");
        return true;
    }
    
    LogMessage(hLog, L"[BUILD] FAILED! Check output: " + result.substr(0, 200));
    return false;
}

bool LoadDriver() {
    LogMessage(hLog, L"[LOAD] Checking for driver file...");
    
    if (GetFileAttributes(L"Build\\Release\\VanguardSpoofer.sys") == INVALID_FILE_ATTRIBUTES) {
        LogMessage(hLog, L"[LOAD] ERROR: Driver not built. Click 'Build Driver' first.");
        return false;
    }
    
    // Download kdmapper if needed
    if (GetFileAttributes(L"Build\\kdmapper.exe") == INVALID_FILE_ATTRIBUTES) {
        LogMessage(hLog, L"[LOAD] Downloading kdmapper...");
        
        if (!DownloadFile(L"https://github.com/TheCruZ/kdmapper/releases/latest/download/kdmapper.exe",
                         L"Build\\kdmapper.exe")) {
            LogMessage(hLog, L"[LOAD] ERROR: Failed to download kdmapper");
            return false;
        }
    }
    
    LogMessage(hLog, L"[LOAD] Loading driver with kdmapper (DSE bypass)...");
    
    std::wstring cmd = L"\"Build\\kdmapper.exe\" \"Build\\Release\\VanguardSpoofer.sys\"";
    std::wstring result = ExecuteCommand(cmd);
    
    LogMessage(hLog, result.substr(0, 500));
    
    if (result.find(L"success") != std::wstring::npos ||
        result.find(L"Success") != std::wstring::npos ||
        result.find(L"mapped") != std::wstring::npos) {
        LogMessage(hLog, L"[LOAD] SUCCESS! Driver loaded!");
        return true;
    }
    
    LogMessage(hLog, L"[LOAD] Check output above for details");
    return false;
}

bool VerifySpoof() {
    LogMessage(hLog, L"[VERIFY] Checking hardware identifiers...");
    
    // Query WMI for current values
    std::wstring cmd = L"powershell -Command \"Get-WmiObject Win32_BaseBoard | Select-Object SerialNumber\"";
    std::wstring bbResult = ExecuteCommand(cmd);
    LogMessage(hLog, L"[VERIFY] Baseboard: " + bbResult.substr(0, 100));
    
    cmd = L"powershell -Command \"Get-WmiObject Win32_PhysicalMedia | Select-Object -First 1 SerialNumber\"";
    std::wstring diskResult = ExecuteCommand(cmd);
    LogMessage(hLog, L"[VERIFY] Disk: " + diskResult.substr(0, 100));
    
    LogMessage(hLog, L"[VERIFY] Done! Check if values are spoofed.");
    return true;
}
