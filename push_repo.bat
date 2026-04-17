@echo off
echo Pushing Pluto Hybrid to GitHub...
cd /d C:\Users\Sam\CascadeProjects\van\pluto-hybrid-github
git remote remove origin 2>nul
git remote add origin https://github.com/ccelda-4chan/pluto-hybrid.git
git push -u origin main
echo.
if %errorlevel% == 0 (
    echo Success!
    echo.
    echo Repository URL: https://github.com/ccelda-4chan/pluto-hybrid
    echo.
    echo Test commands:
    echo irm https://raw.githubusercontent.com/ccelda-4chan/pluto-hybrid/main/PlutoHybrid.ps1 ^| iex
    echo irm https://raw.githubusercontent.com/ccelda-4chan/pluto-hybrid/main/PlutoHybrid-GUI.ps1 ^| iex
) else (
    echo Push failed. Check credentials.
)
pause
