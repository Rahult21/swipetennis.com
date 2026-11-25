# Native iOS releases

For each commit that changes the SwipeTennis iOS app under `apple/`, run the relevant checks, push the commit to GitHub `main`, and install the signed build from that commit on the user's paired iPhone over Wi-Fi. Verify the remote commit and the device installation. Launch the app to confirm it opens when the phone is unlocked.

If the phone is unavailable, push the commit and report that the iPhone installation is pending. If the installation succeeds while the phone is locked, report installation and launch status separately.
