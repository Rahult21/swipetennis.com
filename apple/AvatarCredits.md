# Athlete models

The men’s and women’s USDZ files in `SwipeTennis/Players` use the MakeHuman Community base mesh, anatomical targets, rig weights and system assets. The source identifies Data Collection AB, Joel Palmius and Jonas Hauquier among its contributors. MakeHuman releases its bundled graphical assets under CC0 1.0. [Asset license](https://github.com/makehumancommunity/makehuman/blob/a8bc2d54ff0ac92e78ff71431b1023eda42bf482/LICENSE.md) · [System asset pack](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html)

The derivatives fit each body, close the grip, trim the trousers to sports shorts, remove covered skin, and rebind the meshes and kit to the tennis rig. They use `short01`, `ponytail01`, `low-poly` eyes, `shoes05`, `male_casualsuit06`, and masked skin textures. The skort, visor, headband and collar are built during conversion.

## Rebuilding

Use the MakeHuman asset revision `a8bc2d54ff0ac92e78ff71431b1023eda42bf482`. In a local source directory place `base.obj`, `default.mhskel`, `default_weights.mhw`, and the six adult `{african,asian,caucasian}-{male,female}-young.target` files from that revision. Supply the MakeHuman system asset ZIP as the second argument. The converter uses Python, the Apple USD tools, Swift and Core Graphics. [Source tree](https://github.com/makehumancommunity/makehuman/tree/a8bc2d54ff0ac92e78ff71431b1023eda42bf482/makehuman/data)

```sh
python3 apple/Tools/build_athletes.py /path/to/source /path/to/system-assets.zip apple/SwipeTennis/Players
python3 apple/generate_project.py
```

The ball, court, camera, real-time retargeting and racket contact use the SwipeTennis engine. The licensed movement recordings and their derivatives have separate credits. [Motion credits](MotionCredits.md)
