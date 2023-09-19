# Remove-IntuneDevices.ps1

Instructions for setup:
- Press Windows+X, then click "Windows PowerShell (Admin)" or "Terminal (Admin)"
- Authenticate as admin
- Paste in: `Set-ExecutionPolicy Unrestricted ; Install-Module Microsoft.Graph ; Install-Module Microsoft.Graph.Intune`
- Close the PowerShell window
- Download and extract the attached file

Instructions for use:
- Prepare a CSV file with a column named SerialNumber
- Right click `Remove-IntuneDevices.ps1`
- Click Run with PowerShell
- Follow the prompts
  - To remove devices from Intune, choose the CSV file using the first file picker
  - To remove from Intune, Autopilot, and Azure AD, click Cancel on the first file picker, then choose the CSV file using the second file picker
  - If asked, log in with your Microsoft account and accept the permissions
- Logs are outputted as a CSV file with the date to the directory of the chosen CSV file
