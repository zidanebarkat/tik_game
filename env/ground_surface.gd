## Tags a ground StaticBody3D with the surface material beneath a character.
## Values like "stone", "dirt", "grass". Read by the surface-aware footstep
## feedback system (env build Part 4).
extends StaticBody3D

@export var surface_type: String = "stone"
