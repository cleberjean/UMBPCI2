@echo off
if not exist UMBPCI2.SYS goto Link
del umbpci2.sys

:Link
tlink /t umbpci2.obj, umbpci2.sys /3
 
echo.
if errorlevel > 0 goto Error
echo UMBPCI2.SYS created.
goto End

Error:
echo An Error Ocurred! UMBPCI.SYS not created.

:End
echo.
