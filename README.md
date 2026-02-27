Notes to self, 2/27/26:

I already know that files I upload through `az storage file upload-batch` are visible via UNC from my local desktop.

I also already know that when those files happen to be a `.nupkg` file, they show up nicely on my local desktop as installable PowerShell modules.

Now _(regardless of file extension; the `.nupkg` was a diversion)_, it's time to work on Azure File Sync itself.

Next steps are to:

1. Set up sync objects in Azure.
2. Set up a Windows VM in Azure.
3. RDP into the Windows VM and install the Azure File Sync agent and "register" the VM as a "registered server."
4. Set up the "server" side of the sync group in Azure.
5. Put some more files into the share via `az storage file upload-batch`.
6. RDP into the Windows VM and see if I can see the new files on its filesystem.
7. If feeling it, add some elegance by tidying up the previous steps so they're more idempotent and can be done with smoother IaC execution instead of ClickOps.

If that works, then I'm done proving out my concept with Azure File Sync and developing IaC code.

Whatever reasons I might have in mind for writing files to a Windows server, in the first place, is beyond the scope of this proof of concept, and doesn't belong in this repo and shouldn't take any more of my time, when developing designs.  That's for Windows server sysadmins to worry about implementing, for now.