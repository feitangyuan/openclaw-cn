@echo off
setlocal

set "LOCAL_INSTALL=%~dp0install.sh"
if exist "%LOCAL_INSTALL%" (
  bash "%LOCAL_INSTALL%"
  goto :eof
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$tmp = Join-Path $env:TEMP 'openclaw-install.sh'; Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/feitangyuan/openclaw-cn/main/install.sh' -OutFile $tmp; bash $tmp"
