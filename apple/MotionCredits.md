# Tennis transition capture

The editable motion asset `SwipeTennis/Core/Motion/tennis-transitions.csv` is adapted from **Tennis-MoCap**, maintained by Juan Diego Pulgarin-Giraldo with Sergio Garcia-Vega, Luis Gerardo Melo-Betancourt, Santiago Ramos-Bermudez, Andres Marino Alvarez-Meza and German Castellanos. The original data and this adapted CSV are available under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). [Original recordings and credits](https://github.com/jdpulgarin/Tennis-MoCap)

The two source recordings are `lvargas_Derecha_7seg.bvh` and `lvargas_VDerecha.bvh`. SwipeTennis uses excerpts of the forehand plant and recovery, and forehand-volley preparation. The conversion evaluates the BVH joint hierarchy, projects offsets into player-relative coordinates, subtracts the starting pose, converts centimetres to metres and resamples from 100 to 50 Hz. Run `Tools/retarget_tennis.py` with those two recordings and an output CSV path to reproduce it. The game blends the measurements with ball contact and foot placement on its own rig.

Pulgarin-Giraldo et al. (2017), [A Similarity Indicator for Differentiating Kinematic Performance Between Qualified Tennis Players](https://doi.org/10.1007/978-3-319-52277-7_38).
