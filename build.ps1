param (
  [switch]$run = $false,
  [switch]$test = $false,
  [switch]$publish = $false,
  [switch]$clean = $false)

$ErrorActionPreference = "Stop"

Set-Location -Path $PSScriptRoot

if ($clean) {
  Write-Host "Removing build folders..."
  Remove-Item "deps\dev-cpp" -Recurse -ErrorAction Ignore
  Remove-Item "deps\qt" -Recurse -ErrorAction Ignore 
  Remove-Item "obj" -Recurse -ErrorAction Ignore 
  Remove-Item "publish" -Recurse -ErrorAction Ignore 
  exit 0
}

function ExtractThing {
  param (
    $FriendlyName,
    $ArchivePath,
    $DestinationPath,
    $ExampleFilePath
  )

  if (-not (Test-Path -Path $ExampleFilePath)) {
    Write-Host "Extracting $FriendlyName"
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $DestinationPath -Force
    if (-not (Test-Path -Path $ExampleFilePath)) {
      throw "tried to expand $FriendlyName files, but the expected file $ExampleFilePath wasn't created as a result"
    }
  }
}

ExtractThing -FriendlyName "dev-cpp" -ArchivePath "deps\Dev-Cpp 5.4.1 MinGW 4.7.2 Portable.zip" -DestinationPath "deps\dev-cpp" -ExampleFilePath "deps\dev-cpp\devcppPortable.exe"

ExtractThing -FriendlyName "qt" -ArchivePath "deps\qt-3.3.x-p8.zip" -DestinationPath "deps\qt" -ExampleFilePath "deps\qt\src\widgets\qaction.cpp"

if (-not (Test-Path -Path "deps\qt\modifications-made.txt")) {
  $stuff = Get-Content "deps\qt\misc\link_includes\Makefile.win32-g++"
  $stuff | Foreach-Object { $_ -replace 'CXXFLAGS	=	-O2', 'CXXFLAGS	=	-isystem"$(QTDIR)\..\dev-cpp\MinGW32\include" -O2' } |
    Set-Content "deps\qt\misc\link_includes\Makefile.win32-g++"

  $stuff = Get-Content "deps\qt\misc\configure\Makefile.win32-g++"
  $stuff | Foreach-Object { $_ -replace 'CXXFLAGS	=	-O2', 'CFLAGS	=	-isystem"$(QTDIR)\..\dev-cpp\MinGW32\include" -O2' } |
    Set-Content "deps\qt\misc\configure\Makefile.win32-g++"
    
  $stuff = Get-Content "deps\qt\qmake\Makefile.win32-g++"
  $stuff | Foreach-Object { $_ -replace 'CFLAGS	    =	-c', 'CFLAGS	    =	-isystem"$(QTDIR)\..\dev-cpp\MinGW32\include" -c' } |
    Set-Content "deps\qt\qmake\Makefile.win32-g++"
    
  $stuff = Get-Content "deps\qt\qmake\generators\win32\mingw_make.cpp"
  $stuff | Foreach-Object { $_ -replace '    t << "INCPATH	=	";', 't << "INCPATH	= -isystem\"" << specdir() << "\\..\\..\\..\\dev-cpp\\MinGW32\\include\" ";' } |
    Set-Content "deps\qt\qmake\generators\win32\mingw_make.cpp"
    
  "" | Set-Content "deps\qt\modifications-made.txt"
}

if (-not (Test-Path -Path "deps\qt\successfully-built.txt")) {
  $env:PATH = "$PSScriptRoot\deps\dev-cpp\MinGW32\bin;" + $env:PATH
  Set-Location -Path "$PSScriptRoot\deps\qt"
  & cmd.exe /c configure-mingw.bat
  $ok = ($lastExitCode -eq 0)
  Set-Location -Path $PSScriptRoot
  if (-not $ok) { throw "qt3 didn't build successfully" }
  "" | Set-Content "deps\qt\successfully-built.txt"
}

exit 1

if (-not (Test-Path -Path "obj\lua.o")) {
  Write-Host "Compiling lua.o"
  $luaFiles = (
    "lapi.c", "lcode.c", "lctype.c", "ldebug.c", "ldo.c", "ldump.c", 
    "lfunc.c", "lgc.c", "llex.c", "lmem.c", "lobject.c", "lopcodes.c", "lparser.c", 
    "lstate.c", "lstring.c", "ltable.c", "ltm.c", "lundump.c", "lvm.c", "lzio.c", 
    "lauxlib.c", "lbaselib.c", "lcorolib.c", "ldblib.c", "liolib.c", "lmathlib.c", 
    "loadlib.c", "loslib.c", "lstrlib.c", "ltablib.c", "lutf8lib.c", "linit.c"
    ) | ForEach-Object { "lua-5.4.2\src\$($_)" }
  $unused = [System.IO.Directory]::CreateDirectory("obj");
  & tcc\tcc.exe -r -o obj\lua.o $luaFiles
  if (-not $?) { exit 1 }
}

if ($test) {
  Write-Host "Compiling nateeq.exe"
  & tdm-gcc\bin\g++.exe -g -lwinmm -lopengl32 -o nateeq.exe src\nateeq_main.cpp obj\*.o "-Ilua-5.4.2\src"
  if (-not $?) { exit 1 }

  Write-Host "Running lurds2_testApp.exe"
  & .\lurds2_testApp.exe
}
else {
  # delete old publish directory first, so there's some time between deleting it and recreating it (because delete is async)
  if ($publish) {
    Write-Host "Removing old 'publish' directory"
    Remove-Item "publish" -Recurse -ErrorAction Ignore 
  }

  Write-Host "Compiling lurds2.exe"
  & tcc\tcc.exe -g -lwinmm -lopengl32 -o lurds2.exe src\lurds2_main.c obj\lua.o "-Ilua-5.4.2\src"
  if (-not $?) { exit 1 }

  if ($run) {
    Write-Host "Running lurds2.exe"
    & .\lurds2.exe
  }
  
  if ($publish) {
    Write-Host "Copying files to 'publish' directory"
    $unused = [System.IO.Directory]::CreateDirectory("publish")
    Copy-Item -LiteralPath "lurds2.exe" -Destination "publish"
    Copy-Item -LiteralPath "res" -Destination "publish" -Recurse
  }
}