# Tennis transition capture

The editable motion asset `SwipeTennis/Core/Motion/tennis-transitions.csv` is adapted from **Tennis-MoCap**, maintained by Juan Diego Pulgarin-Giraldo with Sergio Garcia-Vega, Luis Gerardo Melo-Betancourt, Santiago Ramos-Bermudez, Andres Marino Alvarez-Meza and German Castellanos. The original data and this adapted CSV are available under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). [Original recordings and credits](https://github.com/jdpulgarin/Tennis-MoCap)

The two source recordings are `lvargas_Derecha_7seg.bvh` and `lvargas_VDerecha.bvh`. SwipeTennis uses excerpts of the forehand plant and recovery, and forehand-volley preparation. The conversion evaluates the BVH joint hierarchy, projects offsets into player-relative coordinates, subtracts the starting pose, converts centimetres to metres and resamples from 100 to 50 Hz. Run `Tools/retarget_tennis.py` with those two recordings and an output CSV path to reproduce it. The game blends the measurements with ball contact and foot placement on its own rig.

Pulgarin-Giraldo et al. (2017), [A Similarity Indicator for Differentiating Kinematic Performance Between Qualified Tennis Players](https://doi.org/10.1007/978-3-319-52277-7_38).

## Stroke capture

The separate editable asset `SwipeTennis/Core/Motion/court-strokes.csv` is also adapted from Tennis-MoCap by the credited research team and distributed under CC BY-SA 3.0. It contains five excerpts sampled at 50 Hz from the pinned recordings below. The contact landmark is an estimated reference frame near peak wrist speed. SwipeTennis aligns it with the ball contact computed by the game. [Original data](https://github.com/jdpulgarin/Tennis-MoCap/tree/9af88bb4df4e78b22127719744fdca993ced2733/data) · [License](https://creativecommons.org/licenses/by-sa/3.0/)

| Stroke | Recording | Landmark at 100 Hz |
| --- | --- | --- |
| Serve | lvargas_Servicio_21seg.bvh | 413 |
| Overhead | lvargas_Remate.bvh | 2386 |
| Backhand | lvargas_Reves.bvh | 910 |
| Forehand | lvargas_Derecha_7seg.bvh | 299 |
| Volley | lvargas_VDerecha.bvh | 1227 |

The conversion projects the tracked joints into player-relative coordinates and derives trunk rotations, elbow bending directions, free-hand motion and rear-foot displacement. Racket orientation is calculated separately. To recreate the CSV, run `python3 apple/Tools/bake_stroke_capture.py /path/to/original/recordings apple/SwipeTennis/Core/Motion/court-strokes.csv`.
