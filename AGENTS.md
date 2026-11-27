# Native iOS releases

For each commit that changes the SwipeTennis iOS app under `apple/`, run the relevant checks and push the commit to GitHub `main`. Install the signed build from that commit over Wi-Fi on iPhone16pro-RT (iPhone 16 Pro). Include Ruchi 17 Pro Max (iPhone 17 Pro Max) only when the user specifically requests that device for the release.

Verify the remote commit and the installed build on each requested device. Launch the app on each unlocked target. If a target is unavailable or locked, report its installation and launch status separately.
