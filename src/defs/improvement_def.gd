class_name ImprovementDef
extends Resource
## A standing benefit the community has for as long as it knows enough.
## Instances live in data/improvements/*.tres.

@export var id := ""
@export var display_name := ""
## Skill -> level the community must know.
@export var requires: Dictionary = {}
## What it changes: "crop_yield", "treatment_heal" or "carcass".
@export var stat := ""
## Multiplier applied to that.
@export var value := 1.0
