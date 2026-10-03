class_name RecipeDef
extends Resource
## Something made at a workshop. Instances live in data/recipes/*.tres.

@export var id := ""
@export var display_name := ""
## Resource kind -> amount used up.
@export var inputs: Dictionary = {}
## Resource kind -> amount made.
@export var outputs: Dictionary = {}
@export var work_ticks := 200
## Skill the work is done with and trains.
@export var skill := ""
## Skill -> level the community must know.
@export var requires: Dictionary = {}
## It is only made while the stock of what it makes is below this.
@export var target := 0
