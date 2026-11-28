# Athlete models

The men’s and women’s USDZ files in `SwipeTennis/Players` use the MakeHuman Community base mesh, anatomical targets, rig weights and system assets. The source identifies Data Collection AB, Joel Palmius and Jonas Hauquier among its contributors. MakeHuman releases its bundled graphical assets under CC0 1.0. [Asset license](https://github.com/makehumancommunity/makehuman/blob/a8bc2d54ff0ac92e78ff71431b1023eda42bf482/LICENSE.md) · [System asset pack](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html)

The two original young-adult athletes use separate face and body recipes. The women’s and men’s builds blend 70 and 96 percent of their respective muscle targets, with additional shaping of the back, hips, legs and face. A fitted scoop-neck tank and a flared skort form the women’s tour outfit. The men’s outfit pairs a midnight-blue panelled polo with longer graphite shorts. The locker room allows either athlete to use any of the kit pieces.

The converter uses `short01`, `ponytail01`, `low-poly` eyes, `shoes05`, `male_casualsuit06`, facial cards and masked skin textures. It builds the tank, binding, skort, visor, headband, wristbands and polo trim during conversion. Skin and garments share corrective joints at quarter intervals around the shoulders, elbows, hips and knees. Overlapping skin under the armholes, shorts and socks keeps the body covered as those joints flex. The brow and cheek joints carry facial expressions through live play and replay.

## Rebuilding

Use the MakeHuman asset revision `a8bc2d54ff0ac92e78ff71431b1023eda42bf482`. In a local source directory place `base.obj`, `default.mhskel` and `default_weights.mhw`. From `makehuman/data/targets` in that revision, copy the files listed in `athlete_targets("female")` and `athlete_targets("male")` into the same directory, using their basenames and the `.target` extension. Supply the MakeHuman system asset ZIP as the second argument. The converter uses Python, the Apple USD tools, Swift and Core Graphics. [Source tree](https://github.com/makehumancommunity/makehuman/tree/a8bc2d54ff0ac92e78ff71431b1023eda42bf482/makehuman/data)

```sh
python3 apple/Tools/build_athletes.py /path/to/source /path/to/system-assets.zip apple/SwipeTennis/Players
python3 apple/generate_project.py
```

The ball, court, camera, real-time retargeting and racket contact use the SwipeTennis engine. The licensed movement recordings and their derivatives have separate credits. [Motion credits](MotionCredits.md)

## Venue light

The three sky and lighting maps use CC0 photographs from Poly Haven. Daylight uses Kloppenheim 03 Pure Sky. Clay and night use separate grades of Kloppenheim 06 Pure Sky. [Daylight panorama](https://polyhaven.com/a/kloppenheim_03_puresky) · [Evening panorama](https://polyhaven.com/a/kloppenheim_06_puresky) · [License](https://polyhaven.com/license)

To rebuild the maps, download the 1K Radiance versions and run the following command from the repository root.

```sh
swift apple/Tools/bake_match_materials.swift kloppenheim_03_puresky_1k.hdr kloppenheim_06_puresky_1k.hdr apple/SwipeTennis/Assets.xcassets
```


## Spectators and first-run film

The seated audience uses the same CC0 body and kit meshes. The atlas contains twelve original seated figures seen from eight directions. Each section of the stands selects its view as the camera moves. The tree silhouettes use a repeatable branch-and-leaf generator.

```sh
swift apple/Tools/bake_grandstand.swift apple/SwipeTennis/Players apple/SwipeTennis/Assets.xcassets/grandstand-spectators.imageset/seated.png
swift -O apple/Tools/bake_stadium_trees.swift apple/SwipeTennis/Assets.xcassets/venue-trees.imageset/grove.png
```

The four chapters of the first-run film use the native Stroke studio's **Export 0.5× video** action. Export Serve, Run, Forehand and Backhand, then assemble the clips and gesture overlays. Use a new output path and replace the bundled `Media/QuickStart.mp4` after reviewing the result.

```sh
swift apple/Tools/make_quick_start.swift /tmp/QuickStart.mp4 serve.mp4 run.mp4 forehand.mp4 backhand.mp4
```
