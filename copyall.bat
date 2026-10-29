@REM mvtools2
xcopy Sources\x64\Release\mvtools2.dll out\x64\MSVC\ /y
xcopy Sources\x64\Release\mvtools2.dll out\x64\MSVC\ /y
xcopy Sources\x64\Release_v141_xp\mvtools2.dll out\x64\MSVC_XP\ /y
xcopy Sources\x64\Release_v141_xp\mvtools2.dll out\x64\MSVC_XP\ /y
xcopy Sources\x64\Rel_Clang\mvtools2.dll out\x64\ClangCL\ /y
xcopy Sources\x64\Rel_Clang\mvtools2.dll out\x64\ClangCL\ /y
xcopy Sources\x64\IntelCpp\mvtools2.dll out\x64\IntelCpp\ /y
xcopy Sources\x64\IntelCpp\mvtools2.dll out\x64\IntelCpp\ /y

xcopy Sources\Win32\Release\mvtools2.dll out\Win32\MSVC\ /y
xcopy Sources\Win32\Release\mvtools2.dll out\Win32\MSVC\ /y
xcopy Sources\Win32\Release_v141_xp\mvtools2.dll out\Win32\MSVC_XP\ /y
xcopy Sources\Win32\Release_v141_xp\mvtools2.dll out\Win32\MSVC_XP\ /y
xcopy Sources\Win32\Rel_Clang\mvtools2.dll out\Win32\ClangCL\ /y
xcopy Sources\Win32\Rel_Clang\mvtools2.dll out\Win32\ClangCL\ /y
@REM depan
xcopy DePan\x64\Release\DePan.dll out\x64\MSVC\ /y
xcopy DePan\x64\Release_v141_xp\DePan.dll out\x64\MSVC_XP\ /y
xcopy DePan\x64\Rel_Clang\DePan.dll out\x64\ClangCL\ /y
xcopy DePan\x64\IntelCpp\DePan.dll out\x64\IntelCpp\ /y

xcopy DePan\Win32\Release\DePan.dll out\Win32\MSVC\ /y
xcopy DePan\Win32\Release_v141_xp\DePan.dll out\Win32\MSVC_XP\ /y
xcopy DePan\Win32\Rel_Clang\DePan.dll out\Win32\ClangCL\ /y

@REM depanestimate
xcopy DePanEstimate\x64\Release\DePanEstimate.dll out\x64\MSVC\ /y
xcopy DePanEstimate\x64\Release_v141_xp\DePanEstimate.dll out\x64\MSVC_XP\ /y
xcopy DePanEstimate\x64\Rel_Clang\DePanEstimate.dll out\x64\ClangCL\ /y
xcopy DePanEstimate\x64\IntelCpp\DePanEstimate.dll out\x64\IntelCpp\ /y

xcopy DePanEstimate\Win32\Release\DePanEstimate.dll out\Win32\MSVC\ /y
xcopy DePanEstimate\Win32\Release_v141_xp\DePanEstimate.dll out\Win32\MSVC_XP\ /y
xcopy DePanEstimate\Win32\Rel_Clang\DePanEstimate.dll out\Win32\ClangCL\ /y

@REM ARM64
xcopy Sources\ARM64\Release\mvtools2.dll out\ARM64\ /y
xcopy DePan\ARM64\Release\DePan.dll out\ARM64\ /y
xcopy DePanEstimate\ARM64\Release\DePanEstimate.dll out\ARM64\ /y


