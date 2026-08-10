extends Node
## Static accessor for the BattleRegistry autoload that works both in normal
## game runs and in `-s` headless test runs (where autoload global identifiers
## are NOT registered, only the root child node exists).

class_name RegistryAccess

static func get_registry() -> Node:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		return tree.root.get_node_or_null("BattleRegistry")
	return null

static func get_spectator() -> Node:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		return tree.root.get_node_or_null("SpectatorCam")
	return null

static func get_commander_manager() -> Node:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		return tree.root.get_node_or_null("CommanderManager")
	return null

static func get_engagement() -> Node:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		return tree.root.get_node_or_null("EngagementTracker")
	return null
